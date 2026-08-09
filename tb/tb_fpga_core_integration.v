// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
`timescale 1ns/1ps

module tb_top;

    localparam integer MIN_FRAME_LEN = 64;
    localparam integer MAX_FRAME_LEN = 1520;
    localparam integer RX_BEAT_TIMEOUT_CYCLES = 20000;
    localparam integer TX_IDLE_TIMEOUT_CYCLES = 20000;
    localparam integer LINK_WAIT_TIMEOUT_CYCLES = 2500000;
    localparam integer NEG_WAIT_TIMEOUT_CYCLES = 500000;
    localparam integer MAC_CLK_EDGE_TIMEOUT_CYCLES = 50000;
    localparam integer MAX_CAPTURE_BEATS = 512;
    localparam integer TEST_TIMEOUT_NS = 100_000_000;
    localparam LEN_TRACE = 1'b0;

    reg clk_300mhz_p = 1'b0;
    wire clk_300mhz_n;
    reg reset = 1'b1;

    wire [3:0] pcie_rx_p;
    wire [3:0] pcie_rx_n;
    wire [3:0] pcie_tx_p;
    wire [3:0] pcie_tx_n;
    reg pcie_mgt_refclk_p = 1'b0;
    wire pcie_mgt_refclk_n;
    reg pcie_reset_n = 1'b0;

    wire sfp0_rx_p;
    wire sfp0_rx_n;
    wire sfp0_tx_p;
    wire sfp0_tx_n;

    reg sfp_mgt_refclk_0_p = 1'b0;
    wire sfp_mgt_refclk_0_n;

    wire gtrefclk_out_p;
    wire gtrefclk_out_n;
    wire sfp_1_led;
    wire sfp_2_led;
    wire mmcm_locked_led;
    wire pcie_lnk_up_led;
    wire clk_100mhz_ibufg_led;

    wire i2c_scl;
    wire i2c_rst_n;
    wire i2c_sda;

    reg test_started = 1'b0;
    reg tx_hs = 1'b0;
    integer frame_len_iter;
    integer passed_frames = 0;
    integer cfg_min_frame_len = MIN_FRAME_LEN;
    integer cfg_max_frame_len = 65;
    time last_tx_mac_clk_edge = 0;
    time last_rx_mac_clk_edge = 0;
    time last_hls_clk_edge = 0;
    integer tx_mac_hs_count = 0;
    integer rx_mac_hs_count = 0;
    integer rx_plain_hs_count = 0;
    integer tx_hls_in_count = 0;
    integer tx_hls_out_count = 0;
    integer rx_hls_in_count = 0;
    integer rx_hls_out_count = 0;

    reg capture_active = 1'b0;
    reg capture_bank = 1'b0;
    reg capture_done = 1'b0;
    integer capture_idx = 0;
    integer cap0_beats = 0;
    integer cap1_beats = 0;

    reg [63:0] cap0_data [0:MAX_CAPTURE_BEATS-1];
    reg [7:0]  cap0_keep [0:MAX_CAPTURE_BEATS-1];
    reg        cap0_last [0:MAX_CAPTURE_BEATS-1];
    reg [63:0] cap1_data [0:MAX_CAPTURE_BEATS-1];
    reg [7:0]  cap1_keep [0:MAX_CAPTURE_BEATS-1];
    reg        cap1_last [0:MAX_CAPTURE_BEATS-1];

    reg [127:0] last_rx_tag = 128'd0;
    reg         last_rx_tag_valid = 1'b0;
    integer icv_match_count = 0;
    integer icv_mismatch_count = 0;
    reg [31:0] pn_last = 32'd0;
    reg pn_init = 1'b0;
    integer pn_seen_count = 0;
    integer pn_anomaly_count = 0;

    integer before_mismatch;
    integer before_anomaly;
    reg [31:0] pn_hi;
    reg [31:0] pn_lo;

    localparam time TX_MAC_CLK_STALL_TIMEOUT = 20_000_000;

    assign clk_300mhz_n = ~clk_300mhz_p;
    assign pcie_mgt_refclk_n = ~pcie_mgt_refclk_p;
    assign sfp_mgt_refclk_0_n = ~sfp_mgt_refclk_0_p;

    // Keep PCIe RX idle; no host BFM in this testbench.
    assign pcie_rx_p = 4'b0;
    assign pcie_rx_n = ~pcie_rx_p;

    // Keep only optical electrical loopback on SFP0 enabled.
    assign sfp0_rx_p = sfp0_tx_p;
    assign sfp0_rx_n = sfp0_tx_n;

    pullup(i2c_scl);
    pullup(i2c_sda);

    always #1.667 clk_300mhz_p = ~clk_300mhz_p;
    always #5.000 pcie_mgt_refclk_p = ~pcie_mgt_refclk_p;
    always #3.200 sfp_mgt_refclk_0_p = ~sfp_mgt_refclk_0_p;

    always @(posedge dut.core_inst.mac[0].u_macsec_tx.mac_clk) begin
        last_tx_mac_clk_edge <= $time;

        if (capture_active &&
            dut.core_inst.axis_eth_tx_mac_tvalid[0] &&
            dut.core_inst.axis_eth_tx_mac_tready[0]) begin
            if (capture_idx < MAX_CAPTURE_BEATS) begin
                if (capture_bank == 1'b0) begin
                    cap0_data[capture_idx] <= dut.core_inst.axis_eth_tx_mac_tdata[63:0];
                    cap0_keep[capture_idx] <= dut.core_inst.axis_eth_tx_mac_tkeep[7:0];
                    cap0_last[capture_idx] <= dut.core_inst.axis_eth_tx_mac_tlast[0];
                end else begin
                    cap1_data[capture_idx] <= dut.core_inst.axis_eth_tx_mac_tdata[63:0];
                    cap1_keep[capture_idx] <= dut.core_inst.axis_eth_tx_mac_tkeep[7:0];
                    cap1_last[capture_idx] <= dut.core_inst.axis_eth_tx_mac_tlast[0];
                end

                if (dut.core_inst.axis_eth_tx_mac_tlast[0]) begin
                    if (capture_bank == 1'b0) begin
                        cap0_beats <= capture_idx + 1;
                    end else begin
                        cap1_beats <= capture_idx + 1;
                    end
                    capture_done <= 1'b1;
                    capture_active <= 1'b0;
                    capture_idx <= 0;
                end else begin
                    capture_idx <= capture_idx + 1;
                end
            end else begin
                $display("FAIL: capture overflow");
                $finish;
            end
        end

        if (dut.core_inst.axis_eth_tx_mac_tvalid[0] &&
            dut.core_inst.axis_eth_tx_mac_tready[0]) begin
            tx_mac_hs_count <= tx_mac_hs_count + 1;
            if (tx_mac_hs_count < 4) begin
                $display("TRACE: tx_mac_hs count=%0d data=%h keep=%h last=%b sim_time=%0t",
                    tx_mac_hs_count + 1,
                    dut.core_inst.axis_eth_tx_mac_tdata[63:0],
                    dut.core_inst.axis_eth_tx_mac_tkeep[7:0],
                    dut.core_inst.axis_eth_tx_mac_tlast[0],
                    $time);
            end
        end
    end

    always @(posedge dut.core_inst.mac[0].u_macsec_rx.mac_clk) begin
        last_rx_mac_clk_edge <= $time;

        if (dut.core_inst.axis_eth_rx_mac_tvalid[0]) begin
            rx_mac_hs_count <= rx_mac_hs_count + 1;
            if (rx_mac_hs_count < 4) begin
                $display("TRACE: rx_mac_seen count=%0d data=%h keep=%h last=%b sim_time=%0t",
                    rx_mac_hs_count + 1,
                    dut.core_inst.axis_eth_rx_mac_tdata[63:0],
                    dut.core_inst.axis_eth_rx_mac_tkeep[7:0],
                    dut.core_inst.axis_eth_rx_mac_tlast[0],
                    $time);
            end
        end

        if (dut.core_inst.axis_eth_rx_tvalid[0]) begin
            rx_plain_hs_count <= rx_plain_hs_count + 1;
            if (rx_plain_hs_count < 4) begin
                $display("TRACE: rx_plain_seen count=%0d data=%h keep=%h last=%b sim_time=%0t",
                    rx_plain_hs_count + 1,
                    dut.core_inst.axis_eth_rx_tdata[63:0],
                    dut.core_inst.axis_eth_rx_tkeep[7:0],
                    dut.core_inst.axis_eth_rx_tlast[0],
                    $time);
            end
        end
    end

    always @(posedge dut.core_inst.clk_250mhz) begin
        last_hls_clk_edge <= $time;

        if (dut.core_inst.mac[0].u_macsec_tx.bridge_plaintext_empty_n &&
            dut.core_inst.mac[0].u_macsec_tx.bridge_plaintext_read) begin
            tx_hls_in_count <= tx_hls_in_count + 1;
            if (tx_hls_in_count < 4) begin
                $display("TRACE: tx_hls_in count=%0d data=%h sim_time=%0t",
                    tx_hls_in_count + 1,
                    dut.core_inst.mac[0].u_macsec_tx.bridge_plaintext_dout,
                    $time);
            end
        end

        if (dut.core_inst.mac[0].u_macsec_tx.ip_ciphertext_write) begin
            tx_hls_out_count <= tx_hls_out_count + 1;
            if (tx_hls_out_count < 4) begin
                $display("TRACE: tx_hls_out count=%0d data=%h state=%0d tx_pn=%h iv=%h plen=%h sim_time=%0t",
                    tx_hls_out_count + 1,
                    dut.core_inst.mac[0].u_macsec_tx.ip_ciphertext_din,
                    dut.core_inst.mac[0].u_macsec_tx.u_encrypt.state_reg,
                    dut.core_inst.mac[0].u_macsec_tx.u_encrypt.tx_pn,
                    dut.core_inst.mac[0].u_macsec_tx.u_encrypt.iv_reg,
                    dut.core_inst.mac[0].u_macsec_tx.u_encrypt.plaintext_length_reg,
                    $time);
            end
        end

        if (LEN_TRACE && dut.core_inst.mac[0].u_macsec_tx.ip_length_write) begin
            $display("TRACE: tx_hls_len_write len_bits=%0d len_hex=%h sim_time=%0t",
                dut.core_inst.mac[0].u_macsec_tx.ip_length_din,
                dut.core_inst.mac[0].u_macsec_tx.ip_length_din,
                $time);
        end
    end

    always @(posedge dut.core_inst.mac[0].u_macsec_rx.hls_clk) begin
        if (dut.core_inst.mac[0].u_macsec_rx.bridge_ciphertext_empty_n &&
            dut.core_inst.mac[0].u_macsec_rx.bridge_ciphertext_read) begin
            rx_hls_in_count <= rx_hls_in_count + 1;
            if (rx_hls_in_count < 4) begin
                $display("TRACE: rx_hls_in count=%0d data=%h sim_time=%0t",
                    rx_hls_in_count + 1,
                    dut.core_inst.mac[0].u_macsec_rx.bridge_ciphertext_dout,
                    $time);
            end
        end

        if (dut.core_inst.mac[0].u_macsec_rx.ip_plaintext_write) begin
            rx_hls_out_count <= rx_hls_out_count + 1;
            if (rx_hls_out_count < 4) begin
                $display("TRACE: rx_hls_out count=%0d data=%h state=%0d clen=%h sim_time=%0t",
                    rx_hls_out_count + 1,
                    dut.core_inst.mac[0].u_macsec_rx.ip_plaintext_din,
                    dut.core_inst.mac[0].u_macsec_rx.u_decrypt.state_reg,
                    dut.core_inst.mac[0].u_macsec_rx.u_decrypt.ciphertext_length_reg,
                    $time);
            end
        end

        if (dut.core_inst.mac[0].u_macsec_rx.tag_fifo_rd_en &&
            !dut.core_inst.mac[0].u_macsec_rx.tag_fifo_empty) begin
            last_rx_tag <= dut.core_inst.mac[0].u_macsec_rx.tag_fifo_dout[127:0];
            last_rx_tag_valid <= 1'b1;
        end

        if (dut.core_inst.mac[0].u_macsec_rx.dec_ctag_sideband_valid) begin
            if (last_rx_tag_valid &&
                dut.core_inst.mac[0].u_macsec_rx.dec_ctag_sideband === last_rx_tag) begin
                icv_match_count <= icv_match_count + 1;
            end else begin
                icv_mismatch_count <= icv_mismatch_count + 1;
            end
            last_rx_tag_valid <= 1'b0;
        end

        if (LEN_TRACE && dut.core_inst.mac[0].u_macsec_rx.ip_length_write) begin
            $display("TRACE: rx_hls_len_write len_bits=%0d len_hex=%h sim_time=%0t",
                dut.core_inst.mac[0].u_macsec_rx.ip_length_din,
                dut.core_inst.mac[0].u_macsec_rx.ip_length_din,
                $time);
        end
    end

    always @(posedge dut.core_inst.mac[0].u_macsec_rx.mac_clk) begin
        if (dut.core_inst.mac[0].u_macsec_rx.strip_pn_valid &&
            dut.core_inst.mac[0].u_macsec_rx.strip_pn_ready) begin
            pn_seen_count <= pn_seen_count + 1;
            if (pn_init && (dut.core_inst.mac[0].u_macsec_rx.strip_pn <= pn_last)) begin
                pn_anomaly_count <= pn_anomaly_count + 1;
            end
            pn_last <= dut.core_inst.mac[0].u_macsec_rx.strip_pn;
            pn_init <= 1'b1;
        end
    end

    function [7:0] payload_byte;
        input integer frame_len;
        input integer frame_idx;
        input integer byte_idx;
        reg [31:0] mix;
        begin
            mix = (frame_len * 3) + (frame_idx * 17) + (byte_idx * 29) + (byte_idx >> 1);
            payload_byte = mix[7:0] ^ 8'h5A;
        end
    endfunction

    task build_beat;
        input integer frame_len;
        input integer frame_idx;
        input integer beat_idx;
        output [63:0] beat_data;
        output [7:0] beat_keep;
        output beat_last;
        integer lane;
        integer byte_idx;
        reg [63:0] data_tmp;
        reg [7:0] keep_tmp;
        begin
            data_tmp = 64'd0;
            keep_tmp = 8'd0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                byte_idx = beat_idx * 8 + lane;
                if (byte_idx < frame_len) begin
                    data_tmp[lane*8 +: 8] = payload_byte(frame_len, frame_idx, byte_idx);
                    keep_tmp[lane] = 1'b1;
                end
            end
            beat_data = data_tmp;
            beat_keep = keep_tmp;
            beat_last = (beat_idx == ((frame_len + 7) / 8 - 1));
        end
    endtask

    task wait_data_path_ready;
        integer wait_cycles;
        integer mac_clk_ready;
        integer mac_clk_edge_count;
        integer mac_clk_wait_cycles;
        reg mac_clk_prev;
        begin
            wait_cycles = 0;
            $display("INFO: waiting data path ready...");
            begin : wait_path_ready_loop
                while (1'b1) begin
                    if (mmcm_locked_led === 1'b1 &&
                        dut.core_inst.eth_rx_status[0] === 1'b1 &&
                        dut.core_inst.eth_tx_status[0] === 1'b1 &&
                        dut.sfp0_rx_block_lock === 1'b1) begin
                        $display("INFO: data path condition met cycles=%0d mmcm_locked=%b eth_rx_status=%b eth_tx_status=%b rx_block_lock=%b sim_time=%0t",
                            wait_cycles, mmcm_locked_led, dut.core_inst.eth_rx_status[0], dut.core_inst.eth_tx_status[0], dut.sfp0_rx_block_lock, $time);
                        disable wait_path_ready_loop;
                    end

                    @(posedge clk_300mhz_p);
                    wait_cycles = wait_cycles + 1;

                    if ((wait_cycles % 5000) == 0) begin
                        $display("INFO: wait_data_path cycles=%0d mmcm_locked=%b sfp_1_led=%b eth_rx_status=%b eth_tx_status=%b rx_block_lock=%b sfp_rx_rst=%b sfp_tx_rst=%b clk_250=%b rst_250=%b sim_time=%0t",
                            wait_cycles, mmcm_locked_led, sfp_1_led,
                            dut.core_inst.eth_rx_status[0], dut.core_inst.eth_tx_status[0],
                            dut.sfp0_rx_block_lock, dut.sfp0_rx_rst_int, dut.sfp0_tx_rst_int,
                            dut.core_inst.clk_250mhz, dut.core_inst.rst_250mhz, $time);
                    end
                    if (wait_cycles > LINK_WAIT_TIMEOUT_CYCLES) begin
                        $display("FAIL: data path not ready within timeout");
                        $display("      mmcm_locked=%b sfp_1_led=%b eth_rx_status=%b eth_tx_status=%b rx_block_lock=%b sfp_rx_rst=%b sfp_tx_rst=%b",
                            mmcm_locked_led, sfp_1_led,
                            dut.core_inst.eth_rx_status[0], dut.core_inst.eth_tx_status[0],
                            dut.sfp0_rx_block_lock, dut.sfp0_rx_rst_int, dut.sfp0_tx_rst_int);
                        $finish;
                    end
                end
            end

            $display("INFO: data path status ready, waiting MAC clock edges...");
            mac_clk_ready = 0;
            mac_clk_edge_count = 0;
            mac_clk_wait_cycles = 0;
            mac_clk_prev = dut.core_inst.mac[0].u_macsec_tx.mac_clk;

            while (!mac_clk_ready && (mac_clk_wait_cycles < MAC_CLK_EDGE_TIMEOUT_CYCLES)) begin
                @(posedge clk_300mhz_p);
                mac_clk_wait_cycles = mac_clk_wait_cycles + 1;

                if ((mac_clk_prev === 1'b0) &&
                    (dut.core_inst.mac[0].u_macsec_tx.mac_clk === 1'b1)) begin
                    mac_clk_edge_count = mac_clk_edge_count + 1;
                    if (mac_clk_edge_count >= 256) begin
                        mac_clk_ready = 1;
                    end
                end

                mac_clk_prev = dut.core_inst.mac[0].u_macsec_tx.mac_clk;
            end

            if (!mac_clk_ready) begin
                $display("FAIL: MAC clock edges did not arrive within timeout");
                $display("      mac_clk=%b mmcm_locked=%b sfp_1_led=%b eth_rx_status=%b eth_tx_status=%b",
                    dut.core_inst.mac[0].u_macsec_tx.mac_clk,
                    mmcm_locked_led, sfp_1_led,
                    dut.core_inst.eth_rx_status[0], dut.core_inst.eth_tx_status[0]);
                $finish;
            end

            $display("INFO: data path ready at sim_time=%0t", $time);
        end
    endtask

    task send_frame;
        input integer frame_len;
        input integer frame_idx;
        integer beat_count;
        integer beat_idx;
        integer wait_idle_cycles;
        reg [63:0] tx_data;
        reg [7:0] tx_keep;
        reg tx_last;
        begin
            if (frame_idx < 4 || (frame_idx % 64) == 0 || frame_idx >= 20000 || frame_len == cfg_max_frame_len) begin
                $display("INFO: send_frame start len=%0d idx=%0d sim_time=%0t", frame_len, frame_idx, $time);
            end
            beat_count = (frame_len + 7) / 8;

            wait_idle_cycles = 0;
            while (!(dut.core_inst.mac[0].u_macsec_tx.u_in_bridge.state == 3'd0 &&
                     dut.core_inst.mac[0].u_macsec_tx.u_in_bridge.first_beat_pending == 1'b0 &&
                     dut.core_inst.mac[0].u_macsec_tx.u_in_bridge.flush_in_progress == 1'b0)) begin
                @(posedge dut.core_inst.mac[0].u_macsec_tx.mac_clk);
                wait_idle_cycles = wait_idle_cycles + 1;
                if (wait_idle_cycles > TX_IDLE_TIMEOUT_CYCLES) begin
                    $display("FAIL: TX idle wait timeout len=%0d frame_idx=%0d waited_cycles=%0d state=%0d first_pending=%b flush=%b",
                        frame_len, frame_idx, wait_idle_cycles,
                        dut.core_inst.mac[0].u_macsec_tx.u_in_bridge.state,
                        dut.core_inst.mac[0].u_macsec_tx.u_in_bridge.first_beat_pending,
                        dut.core_inst.mac[0].u_macsec_tx.u_in_bridge.flush_in_progress);
                    $finish;
                end
            end
            @(negedge dut.core_inst.mac[0].u_macsec_tx.mac_clk);
            if (frame_idx < 4 || (frame_idx % 64) == 0 || frame_idx >= 20000 || frame_len == cfg_max_frame_len) begin
                $display("INFO: send_frame tx idle ready len=%0d idx=%0d state=%0d sim_time=%0t",
                    frame_len, frame_idx, dut.core_inst.mac[0].u_macsec_tx.u_in_bridge.state, $time);
            end

            for (beat_idx = 0; beat_idx < beat_count; beat_idx = beat_idx + 1) begin
                build_beat(frame_len, frame_idx, beat_idx, tx_data, tx_keep, tx_last);

                force dut.core_inst.axis_eth_tx_tdata[63:0] = tx_data;
                force dut.core_inst.axis_eth_tx_tkeep[7:0] = tx_keep;
                force dut.core_inst.axis_eth_tx_tvalid[0] = 1'b1;
                force dut.core_inst.axis_eth_tx_tlast[0] = tx_last;

                tx_hs = 1'b0;
                while (!tx_hs) begin
                    @(posedge dut.core_inst.mac[0].u_macsec_tx.mac_clk);
                    if (dut.core_inst.axis_eth_tx_tready[0] === 1'b1) begin
                        tx_hs = 1'b1;
                    end
                end
                @(negedge dut.core_inst.mac[0].u_macsec_tx.mac_clk);
            end

            force dut.core_inst.axis_eth_tx_tdata[63:0] = 64'd0;
            force dut.core_inst.axis_eth_tx_tkeep[7:0] = 8'd0;
            force dut.core_inst.axis_eth_tx_tvalid[0] = 1'b0;
            force dut.core_inst.axis_eth_tx_tlast[0] = 1'b0;
            if (frame_idx < 4 || (frame_idx % 64) == 0 || frame_idx >= 20000 || frame_len == cfg_max_frame_len) begin
                $display("INFO: send_frame done len=%0d idx=%0d beats=%0d sim_time=%0t",
                    frame_len, frame_idx, beat_count, $time);
            end
        end
    endtask

    task check_frame;
        input integer frame_len;
        input integer frame_idx;
        integer beat_count;
        integer beat_idx;
        integer got_hs;
        integer wait_cycles;
        integer byte_lane;
        reg [63:0] exp_data;
        reg [7:0] exp_keep;
        reg exp_last;
        reg [63:0] got_data_masked;
        reg [63:0] exp_data_masked;
        begin
            if (frame_idx < 4 || (frame_idx % 64) == 0 || frame_idx >= 20000 || frame_len == cfg_max_frame_len) begin
                $display("INFO: check_frame start len=%0d idx=%0d sim_time=%0t", frame_len, frame_idx, $time);
            end
            beat_count = (frame_len + 7) / 8;

            for (beat_idx = 0; beat_idx < beat_count; beat_idx = beat_idx + 1) begin
                build_beat(frame_len, frame_idx, beat_idx, exp_data, exp_keep, exp_last);
                got_hs = 0;
                wait_cycles = 0;
                while (got_hs == 0) begin
                    @(posedge dut.core_inst.mac[0].u_macsec_rx.mac_clk);
                    wait_cycles = wait_cycles + 1;
                    if ((wait_cycles % 5000) == 0) begin
                        $display("INFO: check_frame waiting len=%0d idx=%0d beat=%0d waited=%0d rx_valid=%b rx_ready=%b rx_mac_valid=%b rx_mac_last=%b tx_mac_valid=%b tx_mac_ready=%b sim_time=%0t",
                            frame_len, frame_idx, beat_idx, wait_cycles,
                            dut.core_inst.axis_eth_rx_tvalid[0], dut.core_inst.axis_eth_rx_tready[0],
                            dut.core_inst.axis_eth_rx_mac_tvalid[0], dut.core_inst.axis_eth_rx_mac_tlast[0],
                            dut.core_inst.axis_eth_tx_mac_tvalid[0], dut.core_inst.axis_eth_tx_mac_tready[0],
                            $time);
                    end
                    if (wait_cycles > RX_BEAT_TIMEOUT_CYCLES) begin
                        $display("FAIL: RX beat timeout len=%0d frame_idx=%0d beat=%0d waited_cycles=%0d",
                            frame_len, frame_idx, beat_idx, wait_cycles);
                        $display("      eth_rx_status=%b eth_tx_status=%b rx_block_lock=%b rx_valid=%b rx_ready=%b rx_last=%b",
                            dut.core_inst.eth_rx_status[0], dut.core_inst.eth_tx_status[0], dut.sfp0_rx_block_lock,
                            dut.core_inst.axis_eth_rx_tvalid[0], dut.core_inst.axis_eth_rx_tready[0], dut.core_inst.axis_eth_rx_tlast[0]);
                        $display("      rx_mac_valid=%b rx_mac_last=%b tx_mac_valid=%b tx_mac_ready=%b tx_mac_last=%b",
                            dut.core_inst.axis_eth_rx_mac_tvalid[0], dut.core_inst.axis_eth_rx_mac_tlast[0],
                            dut.core_inst.axis_eth_tx_mac_tvalid[0], dut.core_inst.axis_eth_tx_mac_tready[0], dut.core_inst.axis_eth_tx_mac_tlast[0]);
                        $display("      hs_count tx_mac=%0d rx_mac=%0d rx_plain=%0d",
                            tx_mac_hs_count, rx_mac_hs_count, rx_plain_hs_count);
                        $display("      hls_count tx_in=%0d tx_out=%0d",
                            tx_hls_in_count, tx_hls_out_count);
                        $display("      hls_count rx_in=%0d rx_out=%0d",
                            rx_hls_in_count, rx_hls_out_count);
                        $display("      mac_rx_clk=%b mac_tx_clk=%b clk_250=%b rst_250=%b",
                            dut.core_inst.mac[0].u_macsec_rx.mac_clk, dut.core_inst.mac[0].u_macsec_tx.mac_clk,
                            dut.core_inst.clk_250mhz, dut.core_inst.rst_250mhz);
                        $display("      last_rx_mac_clk_edge=%0t last_tx_mac_clk_edge=%0t last_hls_clk_edge=%0t",
                            last_rx_mac_clk_edge, last_tx_mac_clk_edge, last_hls_clk_edge);
                        $finish;
                    end
                    if (test_started &&
                        dut.core_inst.axis_eth_rx_tvalid[0]) begin
                        got_hs = 1;
                        got_data_masked = 64'd0;
                        exp_data_masked = 64'd0;
                        for (byte_lane = 0; byte_lane < 8; byte_lane = byte_lane + 1) begin
                            if (exp_keep[byte_lane]) begin
                                got_data_masked[byte_lane*8 +: 8] =
                                    dut.core_inst.axis_eth_rx_tdata[byte_lane*8 +: 8];
                                exp_data_masked[byte_lane*8 +: 8] =
                                    exp_data[byte_lane*8 +: 8];
                            end
                        end

                        if (got_data_masked !== exp_data_masked ||
                            dut.core_inst.axis_eth_rx_tkeep[7:0] !== exp_keep ||
                            dut.core_inst.axis_eth_rx_tlast[0] !== exp_last) begin
                            $display("FAIL: RX mismatch len=%0d frame_idx=%0d beat=%0d", frame_len, frame_idx, beat_idx);
                            $display("      got data=%h keep=%h last=%b",
                                dut.core_inst.axis_eth_rx_tdata[63:0],
                                dut.core_inst.axis_eth_rx_tkeep[7:0],
                                dut.core_inst.axis_eth_rx_tlast[0]);
                            $display("      exp data=%h keep=%h last=%b", exp_data, exp_keep, exp_last);
                            $display("      got_masked=%h exp_masked=%h", got_data_masked, exp_data_masked);
                            $display("      tx_len_bits_reg=%0d rx_len_bits_reg=%0d",
                                dut.core_inst.mac[0].u_macsec_tx.u_encrypt.plaintext_length_reg,
                                dut.core_inst.mac[0].u_macsec_rx.u_decrypt.ciphertext_length_reg);
                            $display("      tx_out_bytes frame_len=%0d frame_cnt=%0d state=%0d",
                                dut.core_inst.mac[0].u_macsec_tx.u_out_bridge.frame_length_bytes_reg,
                                dut.core_inst.mac[0].u_macsec_tx.u_out_bridge.frame_byte_count_reg,
                                dut.core_inst.mac[0].u_macsec_tx.u_out_bridge.state_reg);
                            $display("      rx_out_bytes frame_len=%0d frame_cnt=%0d state=%0d",
                                dut.core_inst.mac[0].u_macsec_rx.u_out_bridge.frame_length_bytes_reg,
                                dut.core_inst.mac[0].u_macsec_rx.u_out_bridge.frame_byte_count_reg,
                                dut.core_inst.mac[0].u_macsec_rx.u_out_bridge.state_reg);
                            $display("      tx_in_bits frame_bytes=%0d state=%0d first_pending=%b flush=%b",
                                dut.core_inst.mac[0].u_macsec_tx.u_in_bridge.frame_byte_count,
                                dut.core_inst.mac[0].u_macsec_tx.u_in_bridge.state,
                                dut.core_inst.mac[0].u_macsec_tx.u_in_bridge.first_beat_pending,
                                dut.core_inst.mac[0].u_macsec_tx.u_in_bridge.flush_in_progress);
                            $display("      rx_in_bits frame_bytes=%0d state=%0d first_pending=%b flush=%b",
                                dut.core_inst.mac[0].u_macsec_rx.u_in_bridge.frame_byte_count,
                                dut.core_inst.mac[0].u_macsec_rx.u_in_bridge.state,
                                dut.core_inst.mac[0].u_macsec_rx.u_in_bridge.first_beat_pending,
                                dut.core_inst.mac[0].u_macsec_rx.u_in_bridge.flush_in_progress);
                            $finish;
                        end
                    end
                end
            end

            if (frame_idx < 4 || (frame_idx % 64) == 0 || frame_idx >= 20000 || frame_len == cfg_max_frame_len) begin
                $display("INFO: check_frame done len=%0d idx=%0d beats=%0d sim_time=%0t",
                    frame_len, frame_idx, beat_count, $time);
            end
        end
    endtask

    task start_capture;
        input integer bank;
        begin
            capture_done = 1'b0;
            capture_active = 1'b1;
            capture_idx = 0;
            capture_bank = bank[0];
            if (bank == 0) begin
                cap0_beats = 0;
            end else begin
                cap1_beats = 0;
            end
            @(posedge dut.core_inst.mac[0].u_macsec_tx.mac_clk);
        end
    endtask

    task wait_capture_done;
        integer wait_cycles;
        begin
            wait_cycles = 0;
            while (!capture_done) begin
                @(posedge dut.core_inst.mac[0].u_macsec_tx.mac_clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > NEG_WAIT_TIMEOUT_CYCLES) begin
                    $display("FAIL: capture timeout");
                    $finish;
                end
            end
        end
    endtask

    task send_frame_with_capture;
        input integer frame_len;
        input integer frame_idx;
        input integer bank;
        begin
            start_capture(bank);
            send_frame(frame_len, frame_idx);
            wait_capture_done();
        end
    endtask

    task inject_rx_mac_frame;
        input integer bank;
        input integer flip_last_tag_bit;
        input integer override_pn;
        input [31:0] pn_value;
        integer beats;
        integer i;
        reg [63:0] inj_data;
        reg [7:0] inj_keep;
        reg inj_last;
        begin
            if (bank == 0) begin
                beats = cap0_beats;
            end else begin
                beats = cap1_beats;
            end

            if (beats < 4) begin
                $display("FAIL: invalid captured frame beats=%0d bank=%0d", beats, bank);
                $finish;
            end

            force dut.core_inst.axis_eth_rx_mac_tuser = {97{1'b0}};

            for (i = 0; i < beats; i = i + 1) begin
                if (bank == 0) begin
                    inj_data = cap0_data[i];
                    inj_keep = cap0_keep[i];
                    inj_last = cap0_last[i];
                end else begin
                    inj_data = cap1_data[i];
                    inj_keep = cap1_keep[i];
                    inj_last = cap1_last[i];
                end

                if (override_pn && i == (beats - 3)) begin
                    inj_data[31:0] = pn_value;
                end

                if (flip_last_tag_bit && i == (beats - 1)) begin
                    inj_data[0] = ~inj_data[0];
                end

                force dut.core_inst.axis_eth_rx_mac_tdata[63:0] = inj_data;
                force dut.core_inst.axis_eth_rx_mac_tkeep[7:0] = inj_keep;
                force dut.core_inst.axis_eth_rx_mac_tvalid[0] = 1'b1;
                force dut.core_inst.axis_eth_rx_mac_tlast[0] = inj_last;
                @(posedge dut.core_inst.mac[0].u_macsec_rx.mac_clk);
            end

            force dut.core_inst.axis_eth_rx_mac_tdata[63:0] = 64'd0;
            force dut.core_inst.axis_eth_rx_mac_tkeep[7:0] = 8'd0;
            force dut.core_inst.axis_eth_rx_mac_tvalid[0] = 1'b0;
            force dut.core_inst.axis_eth_rx_mac_tlast[0] = 1'b0;
            repeat (16) @(posedge dut.core_inst.mac[0].u_macsec_rx.mac_clk);

            release dut.core_inst.axis_eth_rx_mac_tdata[63:0];
            release dut.core_inst.axis_eth_rx_mac_tkeep[7:0];
            release dut.core_inst.axis_eth_rx_mac_tvalid[0];
            release dut.core_inst.axis_eth_rx_mac_tlast[0];
            release dut.core_inst.axis_eth_rx_mac_tuser;
        end
    endtask

    task wait_icv_mismatch_increment;
        input integer before_count;
        integer wait_cycles;
        begin
            wait_cycles = 0;
            while (icv_mismatch_count <= before_count) begin
                @(posedge dut.core_inst.mac[0].u_macsec_rx.hls_clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > NEG_WAIT_TIMEOUT_CYCLES) begin
                    $display("FAIL: expected ICV mismatch was not observed");
                    $finish;
                end
            end
        end
    endtask

    task wait_pn_anomaly_increment;
        input integer before_count;
        integer wait_cycles;
        begin
            wait_cycles = 0;
            while (pn_anomaly_count <= before_count) begin
                @(posedge dut.core_inst.mac[0].u_macsec_rx.mac_clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > NEG_WAIT_TIMEOUT_CYCLES) begin
                    $display("FAIL: expected PN anomaly was not observed");
                    $finish;
                end
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("MIN_LEN=%d", cfg_min_frame_len)) begin
            cfg_min_frame_len = MIN_FRAME_LEN;
        end
        if (!$value$plusargs("MAX_LEN=%d", cfg_max_frame_len)) begin
            cfg_max_frame_len = MAX_FRAME_LEN;
        end
        if (cfg_min_frame_len < MIN_FRAME_LEN) begin
            cfg_min_frame_len = MIN_FRAME_LEN;
        end
        if (cfg_max_frame_len > MAX_FRAME_LEN) begin
            cfg_max_frame_len = MAX_FRAME_LEN;
        end
        if (cfg_max_frame_len < cfg_min_frame_len) begin
            cfg_max_frame_len = cfg_min_frame_len;
        end
        $display("INFO: frame sweep configured min=%0d max=%0d", cfg_min_frame_len, cfg_max_frame_len);
    end

    initial begin
        $display("INFO: tb override SFP_COUNT_125US=%0d", dut.SFP_COUNT_125US);
        $display("INFO: tb_top boot at sim_time=%0t", $time);
    end

    initial begin
        $display("INFO: reset sequence start at sim_time=%0t reset=%b pcie_reset_n=%b",
            $time, reset, pcie_reset_n);
        #100;
        reset = 1'b0;
        $display("INFO: reset deasserted at sim_time=%0t reset=%b", $time, reset);
        #200;
        pcie_reset_n = 1'b1;
        $display("INFO: pcie_reset_n asserted at sim_time=%0t pcie_reset_n=%b", $time, pcie_reset_n);
    end

    initial begin
        $display("INFO: main test initial waiting reset/pcie reset at sim_time=%0t", $time);
        wait(reset == 1'b0);
        $display("INFO: observed reset low at sim_time=%0t", $time);
        wait(pcie_reset_n == 1'b1);
        $display("INFO: observed pcie_reset_n high at sim_time=%0t", $time);
        #200;

        // No PCIe host BFM in this testbench; drive a clean HLS reset pulse, then release.
        force dut.core_inst.rst_250mhz = 1'b1;
        repeat (16) @(posedge dut.core_inst.clk_250mhz);
        force dut.core_inst.rst_250mhz = 1'b0;
        $display("INFO: forcing core rst_250mhz pulse done at sim_time=%0t", $time);

        test_started = 1'b1;
        $display("INFO: test_started asserted at sim_time=%0t", $time);

        // Initialize source-side inputs.
        force dut.core_inst.axis_eth_tx_tdata[63:0] = 64'd0;
        force dut.core_inst.axis_eth_tx_tkeep[7:0] = 8'd0;
        force dut.core_inst.axis_eth_tx_tvalid[0] = 1'b0;
        force dut.core_inst.axis_eth_tx_tlast[0] = 1'b0;

        wait_data_path_ready();
        $display("INFO: starting positive sweep sim_time=%0t", $time);

        // 1) Positive sweep on real eth_mac/phy path (no internal MAC bypass).
        for (frame_len_iter = cfg_min_frame_len; frame_len_iter <= cfg_max_frame_len; frame_len_iter = frame_len_iter + 1) begin
            send_frame(frame_len_iter, frame_len_iter - cfg_min_frame_len);
            check_frame(frame_len_iter, frame_len_iter - cfg_min_frame_len);
            passed_frames = passed_frames + 1;

            if (frame_len_iter == cfg_min_frame_len ||
                frame_len_iter == cfg_max_frame_len ||
                (frame_len_iter % 64) == 0) begin
                $display("PROGRESS: verified frame_len=%0d bytes (%0d/%0d) sim_time=%0t",
                    frame_len_iter, passed_frames, (cfg_max_frame_len - cfg_min_frame_len + 1), $time);
            end

            repeat (8) @(posedge dut.core_inst.mac[0].u_macsec_tx.mac_clk);
        end

        $display("PASS: fpga_core MACsec real-path plaintext sweep %0d..%0d bytes (%0d frames)",
            cfg_min_frame_len, cfg_max_frame_len, passed_frames);

        // 2) Negative test: replay frame (expect PN anomaly).
        send_frame_with_capture(256, 20001, 0);
        check_frame(256, 20001);
        before_anomaly = pn_anomaly_count;
        inject_rx_mac_frame(0, 0, 0, 32'd0);
        wait_pn_anomaly_increment(before_anomaly);
        $display("PASS: negative replay test observed PN anomaly (count=%0d)", pn_anomaly_count);

        // 3) Negative test: tag tamper (expect ICV mismatch).
        send_frame_with_capture(320, 20002, 1);
        check_frame(320, 20002);
        before_mismatch = icv_mismatch_count;
        inject_rx_mac_frame(1, 1, 1, pn_last + 32'd1);
        wait_icv_mismatch_increment(before_mismatch);
        $display("PASS: negative tag tamper test observed ICV mismatch (count=%0d)", icv_mismatch_count);

        // 4) Negative test: PN out-of-order injection (expect PN anomaly).
        pn_hi = pn_last + 32'd4;
        pn_lo = pn_last + 32'd3;
        before_anomaly = pn_anomaly_count;
        inject_rx_mac_frame(1, 0, 1, pn_hi);
        inject_rx_mac_frame(0, 0, 1, pn_lo);
        wait_pn_anomaly_increment(before_anomaly);
        $display("PASS: negative PN reorder test observed PN anomaly (count=%0d)", pn_anomaly_count);

        $display("PASS: all requested tests completed. sweep=%0d frames icv_match=%0d icv_mismatch=%0d pn_seen=%0d pn_anomaly=%0d",
            passed_frames, icv_match_count, icv_mismatch_count, pn_seen_count, pn_anomaly_count);
        $display("PASS: hls handshake counters tx_hls_in=%0d tx_hls_out=%0d rx_hls_in=%0d rx_hls_out=%0d",
            tx_hls_in_count, tx_hls_out_count, rx_hls_in_count, rx_hls_out_count);
        $finish;
    end

    initial begin
        #TEST_TIMEOUT_NS;
        $display("FAIL: timeout waiting for MACsec integration tests");
        $display("      frames_passed=%0d expected=%0d icv_match=%0d icv_mismatch=%0d pn_seen=%0d pn_anomaly=%0d",
            passed_frames, (cfg_max_frame_len - cfg_min_frame_len + 1),
            icv_match_count, icv_mismatch_count, pn_seen_count, pn_anomaly_count);
        $finish;
    end

    initial begin
        wait(test_started == 1'b1);
        forever begin
            #100000;
            if (($time - last_tx_mac_clk_edge) > TX_MAC_CLK_STALL_TIMEOUT) begin
                $display("FAIL: tx mac_clk stall detected at sim_time=%0t frame_len_iter=%0d passed_frames=%0d last_edge=%0t",
                    $time, frame_len_iter, passed_frames, last_tx_mac_clk_edge);
                $finish;
            end
        end
    end

    fpga #(
        .SFP_COUNT_125US(195)
    )
    dut (
        .clk_300mhz_p(clk_300mhz_p),
        .clk_300mhz_n(clk_300mhz_n),
        .reset(reset),
        .pcie_rx_p(pcie_rx_p),
        .pcie_rx_n(pcie_rx_n),
        .pcie_tx_p(pcie_tx_p),
        .pcie_tx_n(pcie_tx_n),
        .pcie_mgt_refclk_p(pcie_mgt_refclk_p),
        .pcie_mgt_refclk_n(pcie_mgt_refclk_n),
        .pcie_reset_n(pcie_reset_n),
        .sfp0_rx_p(sfp0_rx_p),
        .sfp0_rx_n(sfp0_rx_n),
        .sfp0_tx_p(sfp0_tx_p),
        .sfp0_tx_n(sfp0_tx_n),
        .sfp_mgt_refclk_0_p(sfp_mgt_refclk_0_p),
        .sfp_mgt_refclk_0_n(sfp_mgt_refclk_0_n),
        .gtrefclk_out_p(gtrefclk_out_p),
        .gtrefclk_out_n(gtrefclk_out_n),
        .sfp_1_led(sfp_1_led),
        .sfp_2_led(sfp_2_led),
        .mmcm_locked_led(mmcm_locked_led),
        .pcie_lnk_up_led(pcie_lnk_up_led),
        .clk_100mhz_ibufg_led(clk_100mhz_ibufg_led),
        .i2c_scl(i2c_scl),
        .i2c_rst_n(i2c_rst_n),
        .i2c_sda(i2c_sda)
    );

endmodule
