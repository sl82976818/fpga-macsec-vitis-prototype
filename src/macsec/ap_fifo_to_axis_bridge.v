// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
// ==============================================================
// AP_FIFO to AXI-Stream Bridge
// ==============================================================
// Converts AP_FIFO (128-bit) from HLS AES-GCM IP to AXI-Stream (64-bit)
// format with clock domain crossing from HLS domain to MAC domain.
// ==============================================================

`timescale 1ns / 1ps

`include "macsec_types.vh"

module ap_fifo_to_axis_bridge #
(
    parameter integer MAC_DATA_BYTES  = `MACSEC_MAC_KEEP_WIDTH,
    parameter integer BLOCK_SIZE_BYTES = `MACSEC_BLOCK_SIZE_BYTES,
    parameter integer SAME_CLK = 0
)
(
    // ===========================================================
    // HLS Clock Domain (200 MHz)
    // ===========================================================
    input  wire                            hls_clk,
    input  wire                            hls_rst,

    // ===========================================================
    // AP_FIFO Input (from HLS AES-GCM IP)
    // ===========================================================
    input  wire [`MACSEC_HLS_DATA_WIDTH-1:0] s_ciphertext_dout,
    input  wire                            s_ciphertext_empty_n,
    output wire                            s_ciphertext_read,

    input  wire [`MACSEC_ICV_WIDTH-1:0]    s_tag_dout,
    input  wire                            s_tag_empty_n,
    output wire                            s_tag_read,

    // Length is in bits
    input  wire [63:0]                     s_length_dout,
    input  wire                            s_length_empty_n,
    output wire                            s_length_read,

    input  wire                            s_end_dout,
    input  wire                            s_end_empty_n,
    output wire                            s_end_read,

    // ===========================================================
    // MAC Clock Domain (156.25 MHz)
    // ===========================================================
    input  wire                            mac_clk,
    input  wire                            mac_rst,

    output wire [`MACSEC_MAC_DATA_WIDTH-1:0]  m_axis_tdata,
    output wire [MAC_DATA_BYTES-1:0]            m_axis_tkeep,
    output wire                                m_axis_tvalid,
    input  wire                                m_axis_tready,
    output wire                                m_axis_tlast,

    output wire [`MACSEC_ICV_WIDTH-1:0]         icv,
    output wire                                icv_valid,
    input  wire                                icv_ready
);

    localparam [1:0]
        ST_IDLE      = 2'd0,
        ST_SEND_LOW  = 2'd1,
        ST_SEND_UP   = 2'd2;

    reg [1:0] state_reg = ST_IDLE;

    reg [`MACSEC_HLS_DATA_WIDTH-1:0] block_data_reg = {`MACSEC_HLS_DATA_WIDTH{1'b0}};
    reg [31:0] frame_length_bytes_reg = 32'd0;
    reg [31:0] frame_byte_count_reg = 32'd0;
    reg        frame_active_reg = 1'b0;

    reg [`MACSEC_MAC_DATA_WIDTH-1:0] m_axis_tdata_reg = {`MACSEC_MAC_DATA_WIDTH{1'b0}};
    reg [MAC_DATA_BYTES-1:0]         m_axis_tkeep_reg = {MAC_DATA_BYTES{1'b0}};
    reg                               m_axis_tvalid_reg = 1'b0;
    reg                               m_axis_tlast_reg = 1'b0;

    reg [`MACSEC_ICV_WIDTH-1:0] icv_reg = {`MACSEC_ICV_WIDTH{1'b0}};
    reg                         icv_valid_reg = 1'b0;

    wire [`MACSEC_HLS_DATA_WIDTH-1:0] ciphertext_fifo_dout;
    wire ciphertext_fifo_empty;
    wire ciphertext_fifo_full;
    wire ciphertext_fifo_wr_en;
    reg  ciphertext_fifo_rd_en_reg = 1'b0;

    wire [63:0] length_fifo_dout;
    wire length_fifo_empty;
    wire length_fifo_full;
    wire length_fifo_wr_en;
    reg  length_fifo_rd_en_reg = 1'b0;

    wire end_fifo_dout;
    wire end_fifo_empty;
    wire end_fifo_full;
    wire end_fifo_wr_en;
    reg  end_fifo_rd_en_reg = 1'b0;

    wire [`MACSEC_ICV_WIDTH-1:0] tag_fifo_dout;
    wire tag_fifo_empty;
    wire tag_fifo_full;
    wire tag_fifo_wr_en;
    reg  tag_fifo_rd_en_reg = 1'b0;

    wire out_hs;
    reg [31:0] remaining_bytes_reg;
    reg [3:0] beat_bytes_reg;
    reg [31:0] length_bytes_calc;

    assign out_hs = m_axis_tvalid_reg && m_axis_tready;

    function [MAC_DATA_BYTES-1:0] keep_mask;
        input [3:0] byte_count;
        begin
            case (byte_count)
                4'd0: keep_mask = 8'h00;
                4'd1: keep_mask = 8'h01;
                4'd2: keep_mask = 8'h03;
                4'd3: keep_mask = 8'h07;
                4'd4: keep_mask = 8'h0F;
                4'd5: keep_mask = 8'h1F;
                4'd6: keep_mask = 8'h3F;
                4'd7: keep_mask = 8'h7F;
                default: keep_mask = 8'hFF;
            endcase
        end
    endfunction

    function [3:0] beat_byte_count;
        input [31:0] remaining;
        begin
            if (remaining >= 32'd8) begin
                beat_byte_count = 4'd8;
            end else begin
                beat_byte_count = remaining[3:0];
            end
        end
    endfunction

    // ===========================================================
    // HLS-side read control
    // ===========================================================
    assign s_ciphertext_read = s_ciphertext_empty_n && !ciphertext_fifo_full;
    assign s_tag_read = s_tag_empty_n && !tag_fifo_full;
    assign s_length_read = s_length_empty_n && !length_fifo_full;
    // We reconstruct frame boundaries from length + ciphertext count.
    // Still drain HLS end stream so it never backpressures the crypto core.
    assign s_end_read = s_end_empty_n;

    assign ciphertext_fifo_wr_en = s_ciphertext_read;
    assign tag_fifo_wr_en = s_tag_read;
    assign length_fifo_wr_en = s_length_read;
    assign end_fifo_wr_en = 1'b0;

    // ===========================================================
    // CDC FIFOs (HLS -> MAC)
    // ===========================================================
    generate if (SAME_CLK) begin : g_ciphertext_fifo_sync
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(`MACSEC_CDC_FIFO_DEPTH),
        .READ_DATA_WIDTH(`MACSEC_HLS_DATA_WIDTH),
        .WRITE_DATA_WIDTH(`MACSEC_HLS_DATA_WIDTH),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(10),
        .PROG_EMPTY_THRESH(10),
        .USE_ADV_FEATURES("0000")
    ) u_ciphertext_fifo (
        .sleep(1'b0),
        .rst(hls_rst || mac_rst),
        .wr_en(ciphertext_fifo_wr_en),
        .din(s_ciphertext_dout),
        .full(ciphertext_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(ciphertext_fifo_rd_en_reg),
        .dout(ciphertext_fifo_dout),
        .empty(ciphertext_fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr(),
        .wr_clk(mac_clk)
    );
    end else begin : g_ciphertext_fifo_async
    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2),
        .FIFO_WRITE_DEPTH(`MACSEC_CDC_FIFO_DEPTH),
        .READ_DATA_WIDTH(`MACSEC_HLS_DATA_WIDTH),
        .READ_MODE("fwft"),
        .USE_ADV_FEATURES("0000"),
        .WRITE_DATA_WIDTH(`MACSEC_HLS_DATA_WIDTH),
        .PROG_FULL_THRESH(10),
        .RD_DATA_COUNT_WIDTH(1),
        .SIM_ASSERT_CHK(0),
        .PROG_EMPTY_THRESH(10),
        .FULL_RESET_VALUE(1),
        .WR_DATA_COUNT_WIDTH(1)
    ) u_ciphertext_fifo (
        .sleep(1'b0),
        .rst(hls_rst || mac_rst),
        .wr_clk(hls_clk),
        .wr_en(ciphertext_fifo_wr_en),
        .din(s_ciphertext_dout),
        .full(ciphertext_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_clk(mac_clk),
        .rd_en(ciphertext_fifo_rd_en_reg),
        .dout(ciphertext_fifo_dout),
        .empty(ciphertext_fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr()
    );
    end endgenerate

    generate if (SAME_CLK) begin : g_length_fifo_sync
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(16),
        .READ_DATA_WIDTH(64),
        .WRITE_DATA_WIDTH(64),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(10),
        .PROG_EMPTY_THRESH(2),
        .USE_ADV_FEATURES("0000")
    ) u_length_fifo (
        .sleep(1'b0),
        .rst(hls_rst || mac_rst),
        .wr_en(length_fifo_wr_en),
        .din(s_length_dout),
        .full(length_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(length_fifo_rd_en_reg),
        .dout(length_fifo_dout),
        .empty(length_fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr(),
        .wr_clk(mac_clk)
    );
    end else begin : g_length_fifo_async
    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2),
        .FIFO_WRITE_DEPTH(16),
        .READ_DATA_WIDTH(64),
        .READ_MODE("fwft"),
        .USE_ADV_FEATURES("0000"),
        .WRITE_DATA_WIDTH(64),
        .PROG_FULL_THRESH(10),
        .RD_DATA_COUNT_WIDTH(1),
        .SIM_ASSERT_CHK(0),
        .PROG_EMPTY_THRESH(2),
        .FULL_RESET_VALUE(1),
        .WR_DATA_COUNT_WIDTH(1)
    ) u_length_fifo (
        .sleep(1'b0),
        .rst(hls_rst || mac_rst),
        .wr_clk(hls_clk),
        .wr_en(length_fifo_wr_en),
        .din(s_length_dout),
        .full(length_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_clk(mac_clk),
        .rd_en(length_fifo_rd_en_reg),
        .dout(length_fifo_dout),
        .empty(length_fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr()
    );
    end endgenerate

    generate if (SAME_CLK) begin : g_end_fifo_sync
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(16),
        .READ_DATA_WIDTH(1),
        .WRITE_DATA_WIDTH(1),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(10),
        .PROG_EMPTY_THRESH(2),
        .USE_ADV_FEATURES("0000")
    ) u_end_fifo (
        .sleep(1'b0),
        .rst(hls_rst || mac_rst),
        .wr_en(end_fifo_wr_en),
        .din(s_end_dout),
        .full(end_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(end_fifo_rd_en_reg),
        .dout(end_fifo_dout),
        .empty(end_fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr(),
        .wr_clk(mac_clk)
    );
    end else begin : g_end_fifo_async
    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2),
        .FIFO_WRITE_DEPTH(16),
        .READ_DATA_WIDTH(1),
        .READ_MODE("fwft"),
        .USE_ADV_FEATURES("0000"),
        .WRITE_DATA_WIDTH(1),
        .PROG_FULL_THRESH(10),
        .RD_DATA_COUNT_WIDTH(1),
        .SIM_ASSERT_CHK(0),
        .PROG_EMPTY_THRESH(2),
        .FULL_RESET_VALUE(1),
        .WR_DATA_COUNT_WIDTH(1)
    ) u_end_fifo (
        .sleep(1'b0),
        .rst(hls_rst || mac_rst),
        .wr_clk(hls_clk),
        .wr_en(end_fifo_wr_en),
        .din(s_end_dout),
        .full(end_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_clk(mac_clk),
        .rd_en(end_fifo_rd_en_reg),
        .dout(end_fifo_dout),
        .empty(end_fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr()
    );
    end endgenerate

    generate if (SAME_CLK) begin : g_tag_fifo_sync
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(16),
        .READ_DATA_WIDTH(`MACSEC_ICV_WIDTH),
        .WRITE_DATA_WIDTH(`MACSEC_ICV_WIDTH),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(10),
        .PROG_EMPTY_THRESH(2),
        .USE_ADV_FEATURES("0000")
    ) u_tag_fifo (
        .sleep(1'b0),
        .rst(hls_rst || mac_rst),
        .wr_en(tag_fifo_wr_en),
        .din(s_tag_dout),
        .full(tag_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(tag_fifo_rd_en_reg),
        .dout(tag_fifo_dout),
        .empty(tag_fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr(),
        .wr_clk(mac_clk)
    );
    end else begin : g_tag_fifo_async
    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2),
        .FIFO_WRITE_DEPTH(16),
        .READ_DATA_WIDTH(`MACSEC_ICV_WIDTH),
        .READ_MODE("fwft"),
        .USE_ADV_FEATURES("0000"),
        .WRITE_DATA_WIDTH(`MACSEC_ICV_WIDTH),
        .PROG_FULL_THRESH(10),
        .RD_DATA_COUNT_WIDTH(1),
        .SIM_ASSERT_CHK(0),
        .PROG_EMPTY_THRESH(2),
        .FULL_RESET_VALUE(1),
        .WR_DATA_COUNT_WIDTH(1)
    ) u_tag_fifo (
        .sleep(1'b0),
        .rst(hls_rst || mac_rst),
        .wr_clk(hls_clk),
        .wr_en(tag_fifo_wr_en),
        .din(s_tag_dout),
        .full(tag_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_clk(mac_clk),
        .rd_en(tag_fifo_rd_en_reg),
        .dout(tag_fifo_dout),
        .empty(tag_fifo_empty),
        .prog_empty(),
        .rd_data_count(),
        .underflow(),
        .rd_rst_busy(),
        .almost_empty(),
        .data_valid(),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr(),
        .dbiterr()
    );
    end endgenerate

    // ===========================================================
    // MAC-side data path
    // ===========================================================
    always @(posedge mac_clk) begin
        if (mac_rst) begin
            state_reg <= ST_IDLE;
            block_data_reg <= {`MACSEC_HLS_DATA_WIDTH{1'b0}};
            frame_length_bytes_reg <= 32'd0;
            frame_byte_count_reg <= 32'd0;
            frame_active_reg <= 1'b0;
            m_axis_tdata_reg <= {`MACSEC_MAC_DATA_WIDTH{1'b0}};
            m_axis_tkeep_reg <= {MAC_DATA_BYTES{1'b0}};
            m_axis_tvalid_reg <= 1'b0;
            m_axis_tlast_reg <= 1'b0;
            icv_reg <= {`MACSEC_ICV_WIDTH{1'b0}};
            icv_valid_reg <= 1'b0;
            ciphertext_fifo_rd_en_reg <= 1'b0;
            length_fifo_rd_en_reg <= 1'b0;
            end_fifo_rd_en_reg <= 1'b0;
            tag_fifo_rd_en_reg <= 1'b0;
            remaining_bytes_reg <= 32'd0;
            beat_bytes_reg <= 4'd0;
            length_bytes_calc <= 32'd0;
        end else begin
            ciphertext_fifo_rd_en_reg <= 1'b0;
            length_fifo_rd_en_reg <= 1'b0;
            end_fifo_rd_en_reg <= 1'b0;
            tag_fifo_rd_en_reg <= 1'b0;

            if (icv_valid_reg && icv_ready) begin
                icv_valid_reg <= 1'b0;
            end

            if (!icv_valid_reg && !tag_fifo_empty) begin
                icv_reg <= tag_fifo_dout;
                icv_valid_reg <= 1'b1;
                tag_fifo_rd_en_reg <= 1'b1;
            end

            if (out_hs) begin
                m_axis_tvalid_reg <= 1'b0;
            end

            case (state_reg)
                ST_IDLE: begin
                    if (!ciphertext_fifo_empty) begin
                        if (!frame_active_reg) begin
                            if (!length_fifo_empty) begin
                                length_bytes_calc <= {1'b0, length_fifo_dout[31:3]} + (|length_fifo_dout[2:0]);
                                frame_length_bytes_reg <= {1'b0, length_fifo_dout[31:3]} + (|length_fifo_dout[2:0]);
                                frame_byte_count_reg <= 32'd0;
                                frame_active_reg <= 1'b1;
                                length_fifo_rd_en_reg <= 1'b1;
                                block_data_reg <= ciphertext_fifo_dout;
                                ciphertext_fifo_rd_en_reg <= 1'b1;
                                state_reg <= ST_SEND_LOW;
                            end
                        end else begin
                            block_data_reg <= ciphertext_fifo_dout;
                            ciphertext_fifo_rd_en_reg <= 1'b1;
                            state_reg <= ST_SEND_LOW;
                        end
                    end
                end

                ST_SEND_LOW: begin
                    if (!m_axis_tvalid_reg) begin
                        remaining_bytes_reg <= frame_length_bytes_reg - frame_byte_count_reg;
                        beat_bytes_reg <= beat_byte_count(frame_length_bytes_reg - frame_byte_count_reg);
                        // Emit lower 64 bits first.
                        m_axis_tdata_reg <= block_data_reg[63:0];
                        m_axis_tkeep_reg <= keep_mask(beat_byte_count(frame_length_bytes_reg - frame_byte_count_reg));
                        m_axis_tlast_reg <= (frame_length_bytes_reg - frame_byte_count_reg <= 32'd8);
                        m_axis_tvalid_reg <= 1'b1;
                    end else if (out_hs) begin
                        if (frame_length_bytes_reg - frame_byte_count_reg <= 32'd8) begin
                            frame_byte_count_reg <= 32'd0;
                            frame_active_reg <= 1'b0;
                            state_reg <= ST_IDLE;
                        end else begin
                            frame_byte_count_reg <= frame_byte_count_reg + 32'd8;
                            state_reg <= ST_SEND_UP;
                        end
                    end
                end

                ST_SEND_UP: begin
                    if (!m_axis_tvalid_reg) begin
                        remaining_bytes_reg <= frame_length_bytes_reg - frame_byte_count_reg;
                        beat_bytes_reg <= beat_byte_count(frame_length_bytes_reg - frame_byte_count_reg);
                        m_axis_tdata_reg <= block_data_reg[127:64];
                        m_axis_tkeep_reg <= keep_mask(beat_byte_count(frame_length_bytes_reg - frame_byte_count_reg));
                        m_axis_tlast_reg <= (frame_length_bytes_reg - frame_byte_count_reg <= 32'd8);
                        m_axis_tvalid_reg <= 1'b1;
                    end else if (out_hs) begin
                        if (frame_length_bytes_reg - frame_byte_count_reg <= 32'd8) begin
                            frame_byte_count_reg <= 32'd0;
                            frame_active_reg <= 1'b0;
                        end else begin
                            frame_byte_count_reg <= frame_byte_count_reg + 32'd8;
                        end
                        state_reg <= ST_IDLE;
                    end
                end

                default: begin
                    state_reg <= ST_IDLE;
                end
            endcase
        end
    end

    assign m_axis_tdata = m_axis_tdata_reg;
    assign m_axis_tkeep = m_axis_tkeep_reg;
    assign m_axis_tvalid = m_axis_tvalid_reg;
    assign m_axis_tlast = m_axis_tlast_reg;

    assign icv = icv_reg;
    assign icv_valid = icv_valid_reg;

endmodule
