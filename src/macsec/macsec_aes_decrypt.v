// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
`timescale 1ns / 1ps

`include "macsec_types.vh"

module macsec_aes_decrypt #
(
    parameter integer HLS_DATA_WIDTH = `MACSEC_HLS_DATA_WIDTH
)
(
    input  wire                       hls_clk,
    input  wire                       hls_rst,

    input  wire [127:0]               aes_key,
    input  wire [31:0]                ssci,
    input  wire [31:0]                rx_pn,
    input  wire                       key_valid,
    output wire                       busy,

    input  wire [HLS_DATA_WIDTH-1:0]  s_ciphertext_dout,
    input  wire                       s_ciphertext_empty_n,
    output wire                       s_ciphertext_read,

    input  wire [HLS_DATA_WIDTH-1:0]  s_tag_dout,
    input  wire                       s_tag_empty_n,
    output wire                       s_tag_read,

    input  wire [63:0]                s_length_dout,
    input  wire                       s_length_empty_n,
    output wire                       s_length_read,

    input  wire                       s_end_dout,
    input  wire                       s_end_empty_n,
    output wire                       s_end_read,

    output wire [HLS_DATA_WIDTH-1:0]  m_plaintext_din,
    input  wire                       m_plaintext_full_n,
    output wire                       m_plaintext_write,

    output wire [HLS_DATA_WIDTH-1:0]  m_computed_tag_din,
    input  wire                       m_computed_tag_full_n,
    output wire                       m_computed_tag_write,

    output wire [63:0]                m_length_din,
    input  wire                       m_length_full_n,
    output wire                       m_length_write,

    output wire                       m_end_din,
    input  wire                       m_end_full_n,
    output wire                       m_end_write
);

    localparam [1:0]
        ST_IDLE = 2'd0,
        ST_PRIME = 2'd1,
        ST_RUN  = 2'd2;
    localparam DEBUG_LOG = 1'b0;

    reg [1:0] state_reg = ST_IDLE;

    reg [127:0] key_reg = 128'd0;
    reg [95:0] iv_reg = 96'd0;
    reg [127:0] aad_reg = 128'd0;
    reg [63:0] aad_length_reg = 64'd0;
    reg [63:0] ciphertext_length_reg = 64'd0;
    reg [15:0] blocks_remaining_reg = 16'd0;
    reg [15:0] blocks_expected_reg = 16'd0;
    reg        payload_consumed_reg = 1'b0;
    reg        ap_start_reg = 1'b0;
    reg        length_pop_reg = 1'b0;
    reg        tag_pop_reg = 1'b0;
    reg        end_pop_reg = 1'b0;
    reg [127:0] received_tag_reg = 128'd0;

    (* keep = "true" *) reg [31:0] perf_run_cycles_last_reg = 32'd0;
    (* keep = "true" *) reg [31:0] perf_run_cycles_acc_reg = 32'd0;
    (* keep = "true" *) reg [31:0] perf_frames_done_reg = 32'd0;
    (* keep = "true" *) reg [31:0] perf_blocks_read_last_reg = 32'd0;
    (* keep = "true" *) reg [31:0] perf_blocks_read_acc_reg = 32'd0;
    reg [31:0] run_cycles_reg = 32'd0;
    reg [31:0] blocks_read_reg = 32'd0;

    wire can_start;
    wire can_restart;
    wire ip_ap_done;
    wire ip_ap_idle;
    wire ip_ap_ready;
    wire ip_ciphertext_read;

    assign can_restart = key_valid &&
        s_ciphertext_empty_n &&
        s_tag_empty_n &&
        s_length_empty_n &&
        s_end_empty_n &&
        m_plaintext_full_n &&
        m_computed_tag_full_n &&
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
            ciphertext_length_reg <= 64'd0;
            blocks_remaining_reg <= 16'd0;
            blocks_expected_reg <= 16'd0;
            payload_consumed_reg <= 1'b0;
            ap_start_reg <= 1'b0;
            length_pop_reg <= 1'b0;
            tag_pop_reg <= 1'b0;
            end_pop_reg <= 1'b0;
            received_tag_reg <= 128'd0;
            perf_run_cycles_last_reg <= 32'd0;
            perf_run_cycles_acc_reg <= 32'd0;
            perf_frames_done_reg <= 32'd0;
            perf_blocks_read_last_reg <= 32'd0;
            perf_blocks_read_acc_reg <= 32'd0;
            run_cycles_reg <= 32'd0;
            blocks_read_reg <= 32'd0;
        end else begin


            ap_start_reg <= 1'b0;
            length_pop_reg <= 1'b0;
            tag_pop_reg <= 1'b0;
            end_pop_reg <= 1'b0;

            case (state_reg)
                ST_IDLE: begin
                    payload_consumed_reg <= 1'b0;
                    if (can_start) begin
                        ap_start_reg <= 1'b1;
                        if (DEBUG_LOG) begin
                            $display("[%t] %m DEC_START rx_pn=%0d len_bits=%0d tag=%h",
                                $time, rx_pn, s_length_dout, s_tag_dout);
                        end
                        key_reg <= aes_key;
                        iv_reg <= {ssci, rx_pn, 32'h5C5C5C5C};
                        aad_reg <= {80'd0, 16'h0001, ssci};
                        aad_length_reg <= 64'd48;
                        ciphertext_length_reg <= s_length_dout;
                        blocks_remaining_reg <= (s_length_dout[63:7] + |s_length_dout[6:0]);
                        blocks_expected_reg <= (s_length_dout[63:7] + |s_length_dout[6:0]);
                        received_tag_reg <= s_tag_dout;
                        length_pop_reg <= 1'b1;
                        tag_pop_reg <= 1'b1;
                        end_pop_reg <= 1'b1;
                        run_cycles_reg <= 32'd0;
                        blocks_read_reg <= 32'd0;
                        state_reg <= ST_PRIME;
                    end
                end
                ST_PRIME: begin

                    state_reg <= ST_RUN;
                end
                ST_RUN: begin
                    run_cycles_reg <= run_cycles_reg + 32'd1;
                    if (ip_ciphertext_read && blocks_remaining_reg != 16'd0) begin
                        blocks_remaining_reg <= blocks_remaining_reg - 16'd1;
                        blocks_read_reg <= blocks_read_reg + 32'd1;
                        if (blocks_remaining_reg == 16'd1) begin
                            payload_consumed_reg <= 1'b1;
                        end
                    end

                    if (ip_ap_done) begin
                        if (DEBUG_LOG) begin
                            $display("[%t] %m DEC_DONE", $time);
                        end
                        perf_run_cycles_last_reg <= run_cycles_reg;
                        perf_run_cycles_acc_reg <= perf_run_cycles_acc_reg + run_cycles_reg;
                        perf_blocks_read_last_reg <= blocks_read_reg;
                        perf_blocks_read_acc_reg <= perf_blocks_read_acc_reg + blocks_read_reg;
                        perf_frames_done_reg <= perf_frames_done_reg + 32'd1;
                        if (can_restart && (ip_ap_idle || ip_ap_ready)) begin
                            ap_start_reg <= 1'b1;
                            payload_consumed_reg <= 1'b0;
                            key_reg <= aes_key;
                            iv_reg <= {ssci, rx_pn, 32'h5C5C5C5C};
                            aad_reg <= {80'd0, 16'h0001, ssci};
                            aad_length_reg <= 64'd48;
                            ciphertext_length_reg <= s_length_dout;
                            blocks_remaining_reg <= (s_length_dout[63:7] + |s_length_dout[6:0]);
                            blocks_expected_reg <= (s_length_dout[63:7] + |s_length_dout[6:0]);
                            received_tag_reg <= s_tag_dout;
                            length_pop_reg <= 1'b1;
                            tag_pop_reg <= 1'b1;
                            end_pop_reg <= 1'b1;
                            run_cycles_reg <= 32'd0;
                            blocks_read_reg <= 32'd0;
                            state_reg <= ST_PRIME;
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

    assign s_ciphertext_read = (state_reg == ST_RUN) ? ip_ciphertext_read : 1'b0;
    assign s_tag_read = tag_pop_reg;
    assign s_length_read = length_pop_reg;
    assign s_end_read = end_pop_reg;

    hls_aes128gcm_dec u_hls_aes128gcm_dec (
        .ap_clk(hls_clk),
        .ap_rst(hls_rst),
        .ap_start(ap_start_reg),
        .ap_done(ip_ap_done),
        .ap_idle(ip_ap_idle),
        .ap_ready(ip_ap_ready),

        .ciphertext_dout(s_ciphertext_dout),
        .ciphertext_empty_n(state_reg == ST_RUN ? s_ciphertext_empty_n : 1'b0),
        .ciphertext_read(ip_ciphertext_read),

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

        .ciphertext_length_dout(ciphertext_length_reg),
        .ciphertext_length_empty_n(state_reg == ST_RUN),
        .ciphertext_length_read(),

        .end_length_dout(payload_consumed_reg),
        .end_length_empty_n(state_reg == ST_RUN),
        .end_length_read(),

        .plaintext_din(m_plaintext_din),
        .plaintext_full_n(m_plaintext_full_n),
        .plaintext_write(m_plaintext_write),

        .plaintext_length_din(m_length_din),
        .plaintext_length_full_n(m_length_full_n),
        .plaintext_length_write(m_length_write),

        .tag_din(m_computed_tag_din),
        .tag_full_n(m_computed_tag_full_n),
        .tag_write(m_computed_tag_write),

        .end_tag_din(m_end_din),
        .end_tag_full_n(m_end_full_n),
        .end_tag_write(m_end_write)
    );

endmodule
