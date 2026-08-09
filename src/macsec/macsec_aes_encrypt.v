// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
`timescale 1ns / 1ps

`include "macsec_types.vh"

module macsec_aes_encrypt #
(
    parameter integer HLS_DATA_WIDTH = `MACSEC_HLS_DATA_WIDTH,
    parameter [31:0]  PN_INIT = 32'd1
)
(
    input  wire                       hls_clk,
    input  wire                       hls_rst,

    input  wire [127:0]               aes_key,
    input  wire [31:0]                ssci,
    input  wire                       key_valid,
    output reg  [31:0]                tx_pn,
    output wire                       busy,

    input  wire [HLS_DATA_WIDTH-1:0]  s_plaintext_dout,
    input  wire                       s_plaintext_empty_n,
    output wire                       s_plaintext_read,

    input  wire [63:0]                s_length_dout,
    input  wire                       s_length_empty_n,
    output wire                       s_length_read,

    input  wire                       s_end_dout,
    input  wire                       s_end_empty_n,
    output wire                       s_end_read,

    output wire [HLS_DATA_WIDTH-1:0]  m_ciphertext_din,
    input  wire                       m_ciphertext_full_n,
    output wire                       m_ciphertext_write,

    output wire [HLS_DATA_WIDTH-1:0]  m_tag_din,
    input  wire                       m_tag_full_n,
    output wire                       m_tag_write,

    output wire [63:0]                m_length_din,
    input  wire                       m_length_full_n,
    output wire                       m_length_write,

    output wire                       m_end_din,
    input  wire                       m_end_full_n,
    output wire                       m_end_write
);

    localparam [1:0]
        ST_IDLE = 2'd0,
        ST_RUN  = 2'd1;

    reg [1:0] state_reg = ST_IDLE;

    reg [127:0] key_reg = 128'd0;
    reg [95:0] iv_reg = 96'd0;
    reg [127:0] aad_reg = 128'd0;
    reg [63:0] aad_length_reg = 64'd0;
    reg [63:0] plaintext_length_reg = 64'd0;
    reg [15:0] blocks_remaining_reg = 16'd0;
    reg [15:0] blocks_expected_reg = 16'd0;
    reg        payload_consumed_reg = 1'b0;
    reg        ap_start_reg = 1'b0;
    reg        length_pop_reg = 1'b0;
    reg        end_pop_reg = 1'b0;
    // Perf observability counters (hierarchical debug only)
    (* keep = "true" *) reg [31:0] perf_run_cycles_last_reg = 32'd0;
    (* keep = "true" *) reg [31:0] perf_run_cycles_acc_reg = 32'd0;
    (* keep = "true" *) reg [31:0] perf_frames_done_reg = 32'd0;
    (* keep = "true" *) reg [31:0] perf_blocks_read_last_reg = 32'd0;
    (* keep = "true" *) reg [31:0] perf_blocks_read_acc_reg = 32'd0;
    (* keep = "true" *) reg [31:0] dbg_ap_start_cnt_reg = 32'd0;
    (* keep = "true" *) reg [31:0] dbg_len_pop_cnt_reg = 32'd0;
    (* keep = "true" *) reg [31:0] dbg_end_pop_cnt_reg = 32'd0;
    (* keep = "true" *) reg [31:0] dbg_plain_read_cnt_reg = 32'd0;
    (* keep = "true" *) reg [31:0] dbg_ap_done_cnt_reg = 32'd0;
    reg [31:0] run_cycles_reg = 32'd0;
    reg [31:0] blocks_read_reg = 32'd0;

    wire can_start;
    wire can_restart;
    wire ip_ap_done;
    wire ip_ap_idle;
    wire ip_ap_ready;
    wire ip_plaintext_read;
    wire ip_end_length_read;

    assign can_restart = key_valid &&
        s_plaintext_empty_n &&
        s_length_empty_n &&
        s_end_empty_n &&
        m_ciphertext_full_n &&
        m_tag_full_n &&
        m_length_full_n &&
        m_end_full_n;
    assign can_start = can_restart && ip_ap_idle;

    always @(posedge hls_clk) begin
        if (hls_rst) begin
            state_reg <= ST_IDLE;
            key_reg <= 128'd0;
            iv_reg <= 96'd0;
            aad_reg <= 128'd0;
            aad_length_reg <= 64'd0;
            plaintext_length_reg <= 64'd0;
            blocks_remaining_reg <= 16'd0;
            blocks_expected_reg <= 16'd0;
            payload_consumed_reg <= 1'b0;
            ap_start_reg <= 1'b0;
            length_pop_reg <= 1'b0;
            end_pop_reg <= 1'b0;
            tx_pn <= PN_INIT;
            perf_run_cycles_last_reg <= 32'd0;
            perf_run_cycles_acc_reg <= 32'd0;
            perf_frames_done_reg <= 32'd0;
            perf_blocks_read_last_reg <= 32'd0;
            perf_blocks_read_acc_reg <= 32'd0;
            run_cycles_reg <= 32'd0;
            blocks_read_reg <= 32'd0;
            dbg_ap_start_cnt_reg <= 32'd0;
            dbg_len_pop_cnt_reg <= 32'd0;
            dbg_end_pop_cnt_reg <= 32'd0;
            dbg_plain_read_cnt_reg <= 32'd0;
            dbg_ap_done_cnt_reg <= 32'd0;
        end else begin
            // ap_ctrl_hs requires ap_start as a pulse per transaction.
            // Keep frame-level continuity by pulsing again at done boundary.
            ap_start_reg <= 1'b0;
            length_pop_reg <= 1'b0;
            end_pop_reg <= 1'b0;

            case (state_reg)
                ST_IDLE: begin
                    payload_consumed_reg <= 1'b0;
                    if (can_start) begin
                        ap_start_reg <= 1'b1;
                        dbg_ap_start_cnt_reg <= dbg_ap_start_cnt_reg + 32'd1;
                        key_reg <= aes_key;
                        iv_reg <= {ssci, tx_pn, 32'h5C5C5C5C};
                        aad_reg <= {80'd0, 16'h0001, ssci};
                        aad_length_reg <= 64'd48;
                        plaintext_length_reg <= s_length_dout;
                        blocks_remaining_reg <= (s_length_dout[63:7] + |s_length_dout[6:0]);
                        blocks_expected_reg <= (s_length_dout[63:7] + |s_length_dout[6:0]);
                        length_pop_reg <= 1'b1;
                        end_pop_reg <= 1'b1;
                        dbg_len_pop_cnt_reg <= dbg_len_pop_cnt_reg + 32'd1;
                        dbg_end_pop_cnt_reg <= dbg_end_pop_cnt_reg + 32'd1;
                        run_cycles_reg <= 32'd0;
                        blocks_read_reg <= 32'd0;
                        state_reg <= ST_RUN;
                    end
                end
                ST_RUN: begin
                    run_cycles_reg <= run_cycles_reg + 32'd1;
                    if (ip_plaintext_read && blocks_remaining_reg != 16'd0) begin
                        blocks_remaining_reg <= blocks_remaining_reg - 16'd1;
                        blocks_read_reg <= blocks_read_reg + 32'd1;
                        dbg_plain_read_cnt_reg <= dbg_plain_read_cnt_reg + 32'd1;
                        if (blocks_remaining_reg == 16'd1) begin
                            payload_consumed_reg <= 1'b1;
                        end
                    end

                    if (ip_ap_done) begin
                        dbg_ap_done_cnt_reg <= dbg_ap_done_cnt_reg + 32'd1;
                        tx_pn <= tx_pn + 32'd1;
                        perf_run_cycles_last_reg <= run_cycles_reg;
                        perf_run_cycles_acc_reg <= perf_run_cycles_acc_reg + run_cycles_reg;
                        perf_blocks_read_last_reg <= blocks_read_reg;
                        perf_blocks_read_acc_reg <= perf_blocks_read_acc_reg + blocks_read_reg;
                        perf_frames_done_reg <= perf_frames_done_reg + 32'd1;
                        // Continuous streaming restart: consume next frame
                        // metadata at done boundary when available.
                        if (can_restart && (ip_ap_idle || ip_ap_ready)) begin
                            ap_start_reg <= 1'b1;
                            dbg_ap_start_cnt_reg <= dbg_ap_start_cnt_reg + 32'd1;
                            payload_consumed_reg <= 1'b0;
                            key_reg <= aes_key;
                            iv_reg <= {ssci, tx_pn + 32'd1, 32'h5C5C5C5C};
                            aad_reg <= {80'd0, 16'h0001, ssci};
                            aad_length_reg <= 64'd48;
                            plaintext_length_reg <= s_length_dout;
                            blocks_remaining_reg <= (s_length_dout[63:7] + |s_length_dout[6:0]);
                            blocks_expected_reg <= (s_length_dout[63:7] + |s_length_dout[6:0]);
                            length_pop_reg <= 1'b1;
                            end_pop_reg <= 1'b1;
                            dbg_len_pop_cnt_reg <= dbg_len_pop_cnt_reg + 32'd1;
                            dbg_end_pop_cnt_reg <= dbg_end_pop_cnt_reg + 32'd1;
                            run_cycles_reg <= 32'd0;
                            blocks_read_reg <= 32'd0;
                            state_reg <= ST_RUN;
                        end else begin
                            state_reg <= ST_IDLE;
                        end
                    end
                end
                default: begin
                    state_reg <= ST_IDLE;
                end
            endcase
        end
    end

    assign busy = state_reg != ST_IDLE;

    assign s_plaintext_read = (state_reg == ST_RUN) ? ip_plaintext_read : 1'b0;
    assign s_length_read = length_pop_reg;
    assign s_end_read = end_pop_reg;

    hls_aes128gcm_enc u_hls_aes128gcm_enc (
        .ap_clk(hls_clk),
        .ap_rst(hls_rst),
        .ap_start(ap_start_reg),
        .ap_done(ip_ap_done),
        .ap_idle(ip_ap_idle),
        .ap_ready(ip_ap_ready),

        .plaintext_dout(s_plaintext_dout),
        .plaintext_empty_n(state_reg == ST_RUN ? s_plaintext_empty_n : 1'b0),
        .plaintext_read(ip_plaintext_read),

        .cipherkey_dout(key_reg),
        .cipherkey_empty_n(state_reg == ST_RUN),
        .cipherkey_read(),

        .IV_dout(iv_reg),
        .IV_empty_n(state_reg == ST_RUN),
        .IV_read(),

        .AAD_dout(aad_reg),
        .AAD_empty_n(state_reg == ST_RUN),
        .AAD_read(),

        .AAD_length_dout(aad_length_reg),
        .AAD_length_empty_n(state_reg == ST_RUN),
        .AAD_length_read(),

        .plaintext_length_dout(plaintext_length_reg),
        .plaintext_length_empty_n(state_reg == ST_RUN),
        .plaintext_length_read(),

        .end_length_dout(payload_consumed_reg),
        .end_length_empty_n(state_reg == ST_RUN),
        .end_length_read(ip_end_length_read),

        .ciphertext_din(m_ciphertext_din),
        .ciphertext_full_n(m_ciphertext_full_n),
        .ciphertext_write(m_ciphertext_write),

        .ciphertext_length_din(m_length_din),
        .ciphertext_length_full_n(m_length_full_n),
        .ciphertext_length_write(m_length_write),

        .tag_din(m_tag_din),
        .tag_full_n(m_tag_full_n),
        .tag_write(m_tag_write),

        .end_tag_din(m_end_din),
        .end_tag_full_n(m_end_full_n),
        .end_tag_write(m_end_write)
    );

endmodule
