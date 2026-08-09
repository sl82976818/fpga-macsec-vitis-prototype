// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
`timescale 1ns / 1ps

`include "macsec_types.vh"

module macsec_rx_wrapper #
(
    parameter integer MAC_DATA_BYTES  = `MACSEC_MAC_KEEP_WIDTH,
    parameter integer BLOCK_SIZE_BYTES = `MACSEC_BLOCK_SIZE_BYTES,
    parameter integer USER_WIDTH = 1,
    parameter         PROTECT_ENABLE = 1'b1
)
(
    input  wire                               mac_clk,
    input  wire                               mac_rst,

    input  wire [`MACSEC_MAC_DATA_WIDTH-1:0] s_axis_tdata,
    input  wire [MAC_DATA_BYTES-1:0]          s_axis_tkeep,
    input  wire                               s_axis_tvalid,
    output wire                               s_axis_tready,
    input  wire                               s_axis_tlast,
    input  wire [USER_WIDTH-1:0]              s_axis_tuser,

    output wire [`MACSEC_MAC_DATA_WIDTH-1:0] m_axis_tdata,
    output wire [MAC_DATA_BYTES-1:0]          m_axis_tkeep,
    output wire                               m_axis_tvalid,
    input  wire                               m_axis_tready,
    output wire                               m_axis_tlast,
    output wire [USER_WIDTH-1:0]              m_axis_tuser,

    input  wire                               hls_clk,
    input  wire                               hls_rst,

    input  wire [127:0]                       aes_key,
    input  wire [31:0]                        ssci,
    input  wire [31:0]                        rx_pn,
    input  wire                               enable,
    output wire                               busy,

    output wire [`MACSEC_ICV_WIDTH-1:0]      computed_icv,
    output wire                               icv_valid,
    input  wire [`MACSEC_ICV_WIDTH-1:0]      received_icv,
    input  wire                               icv_check_enable
);

    // Preserve only Ethernet L2 header (DA/SA/EtherType) in clear text.
    localparam integer HEADER_BYTES = 14;
    localparam integer HEADER_BEAT0_BYTES = (HEADER_BYTES >= MAC_DATA_BYTES) ? MAC_DATA_BYTES : HEADER_BYTES;
    localparam integer HEADER_BEAT1_BYTES = (HEADER_BYTES > MAC_DATA_BYTES) ? (HEADER_BYTES - MAC_DATA_BYTES) : 0;
    localparam integer HEADER_FIFO_DEPTH = 32;
    localparam integer HEADER_FIFO_PTR_WIDTH = 5;
    localparam [1:0]
        OUT_IDLE   = 2'd0,
        OUT_HEADER = 2'd1,
        OUT_DEC    = 2'd2;

    wire [`MACSEC_MAC_DATA_WIDTH-1:0] strip_payload_tdata;
    wire [MAC_DATA_BYTES-1:0]         strip_payload_tkeep;
    wire                              strip_payload_tvalid;
    wire                              strip_payload_tready;
    wire                              strip_payload_tlast;
    wire [127:0]                      strip_tag;
    wire                              strip_tag_valid;
    wire                              strip_tag_ready;
    wire [31:0]                       strip_pn;
    wire                              strip_pn_valid;
    wire                              strip_pn_ready;
    wire [15:0]                       strip_ethertype;
    wire                              strip_ethertype_valid;
    wire                              strip_ethertype_ready;
    wire                              strip_in_ready;
    localparam integer PAYLOAD_FIFO_DEPTH = 2048;
    localparam integer PAYLOAD_FIFO_CNT_WIDTH = 11;

    wire [`MACSEC_MAC_DATA_WIDTH-1:0] payload_fifo_tdata;
    wire [MAC_DATA_BYTES-1:0]         payload_fifo_tkeep;
    wire                              payload_fifo_tvalid;
    wire                              payload_fifo_tready;
    wire                              payload_fifo_tlast;
    wire                              strip_push_beat;

    wire [159:0]                      tag_fifo_dout;
    wire                              tag_fifo_full;
    wire                              tag_fifo_empty;
    wire                              tag_fifo_wr_en;
    wire                              tag_fifo_rd_en;
    localparam integer ETHERTYPE_FIFO_DEPTH = 32;
    reg [15:0] ethertype_fifo_mem [0:ETHERTYPE_FIFO_DEPTH-1];
    reg [4:0]  ethertype_fifo_wr_ptr_reg = 5'd0;
    reg [4:0]  ethertype_fifo_rd_ptr_reg = 5'd0;
    reg [5:0]  ethertype_fifo_count_reg = 6'd0;

    wire [`MACSEC_HLS_DATA_WIDTH-1:0] bridge_ciphertext_dout;
    wire bridge_ciphertext_empty_n;
    wire bridge_ciphertext_read;
    wire in_bridge_ready;
    wire [63:0] bridge_length_dout;
    wire bridge_length_empty_n;
    wire bridge_length_read;
    wire bridge_end_dout;
    wire bridge_end_empty_n;
    wire bridge_end_read;

    wire [`MACSEC_HLS_DATA_WIDTH-1:0] ip_plaintext_din;
    wire ip_plaintext_write;
    wire [`MACSEC_HLS_DATA_WIDTH-1:0] ip_computed_tag_din;
    wire ip_computed_tag_write;
    wire [63:0] ip_length_din;
    wire ip_length_write;
    wire ip_end_din;
    wire ip_end_write;

    wire [127:0] plain_fifo_dout;
    wire         plain_fifo_full;
    wire         plain_fifo_empty;
    wire         plain_fifo_wr_en;
    wire         plain_fifo_rd_en;
    wire [127:0] ctag_fifo_dout;
    wire         ctag_fifo_full;
    wire         ctag_fifo_empty;
    wire         ctag_fifo_wr_en;
    wire         ctag_fifo_rd_en;

    wire [63:0]  plen_fifo_dout;
    wire         plen_fifo_full;
    wire         plen_fifo_empty;
    wire         plen_fifo_wr_en;
    wire         plen_fifo_rd_en;

    wire         pend_fifo_dout;
    wire         pend_fifo_full;
    wire         pend_fifo_empty;
    wire         pend_fifo_wr_en;
    wire         pend_fifo_rd_en;

    wire out_bridge_plain_read;
    wire out_bridge_ctag_read;
    wire out_bridge_plen_read;
    wire out_bridge_pend_read;

    wire [`MACSEC_MAC_DATA_WIDTH-1:0] dec_payload_tdata;
    wire [MAC_DATA_BYTES-1:0]         dec_payload_tkeep;
    wire                              dec_payload_tvalid;
    wire                              dec_payload_tready;
    wire                              dec_payload_tlast;
    wire [`MACSEC_MAC_DATA_WIDTH-1:0] strip_compact_tdata;
    wire [MAC_DATA_BYTES-1:0]         strip_compact_tkeep;
    wire                              strip_compact_tvalid;
    wire                              strip_compact_tready;
    wire                              strip_compact_tlast;
    wire [127:0]                      dec_ctag_sideband;
    wire                              dec_ctag_sideband_valid;

    wire dec_busy;
    wire decrypt_tag_read;

    reg [HEADER_BYTES*8-1:0] in_header_reg = {HEADER_BYTES*8{1'b0}};
    reg [4:0]                in_header_count_reg = 5'd0;
    reg [HEADER_BYTES*8-1:0] split_header_next_reg;
    reg [4:0]                split_header_count_next_reg;
    reg [`MACSEC_MAC_DATA_WIDTH-1:0] split_payload_data_reg;
    reg [MAC_DATA_BYTES-1:0]          split_payload_keep_reg;

    reg [HEADER_BYTES*8-1:0] header_fifo_mem [0:HEADER_FIFO_DEPTH-1];
    reg [HEADER_FIFO_PTR_WIDTH-1:0] header_fifo_wr_ptr_reg = {HEADER_FIFO_PTR_WIDTH{1'b0}};
    reg [HEADER_FIFO_PTR_WIDTH-1:0] header_fifo_rd_ptr_reg = {HEADER_FIFO_PTR_WIDTH{1'b0}};
    reg [HEADER_FIFO_PTR_WIDTH:0]   header_fifo_count_reg = {HEADER_FIFO_PTR_WIDTH+1{1'b0}};
    reg [HEADER_BYTES*8-1:0]        header_push_data_reg = {HEADER_BYTES*8{1'b0}};
    reg                             header_push_pending_reg = 1'b0;
    reg                             header_push_drop_reg = 1'b0;
    reg [HEADER_BYTES*8-1:0]        out_header_reg = {HEADER_BYTES*8{1'b0}};
    reg [1:0]                       out_state_reg = OUT_IDLE;

    wire header_fifo_empty;
    wire header_fifo_full;
    wire [HEADER_BYTES*8-1:0] header_fifo_head;
    wire ethertype_fifo_empty;
    wire ethertype_fifo_full;
    wire [15:0] ethertype_fifo_head;
    wire split_payload_present;
    wire s_axis_ready_int;
    wire in_axis_hs;
    wire s_axis_frame_end_hs;
    wire pause_header_match_next;
    wire drop_pause_frame_now;
    wire out_axis_hs;
    wire out_start_hs;
    wire crypto_enable;

    wire [`MACSEC_MAC_DATA_WIDTH-1:0] out_tdata_int;
    wire [MAC_DATA_BYTES-1:0]         out_tkeep_int;
    wire                              out_tvalid_int;
    wire                              out_tlast_int;
    wire [USER_WIDTH-1:0]             out_tuser_int;
    wire                              out_tready_int;
    wire [`MACSEC_MAC_DATA_WIDTH-1:0] out_compact_tdata;
    wire [MAC_DATA_BYTES-1:0]         out_compact_tkeep;
    wire                              out_compact_tvalid;
    wire                              out_compact_tlast;
    wire [USER_WIDTH-1:0]             out_compact_tuser;


    integer i;
    integer hdr_count_tmp;
    integer payload_idx_tmp;
    reg drop_pause_frame_reg = 1'b0;

    function [MAC_DATA_BYTES-1:0] keep_mask_from_count;
        input integer byte_count;
        integer n;
        begin
            keep_mask_from_count = {MAC_DATA_BYTES{1'b0}};
            for (n = 0; n < MAC_DATA_BYTES; n = n + 1) begin
                if (n < byte_count) begin
                    keep_mask_from_count[n] = 1'b1;
                end
            end
        end
    endfunction

    function is_pause_ctrl_header;
        input [HEADER_BYTES*8-1:0] hdr;
        begin
            if (HEADER_BYTES < 16) begin
                is_pause_ctrl_header = 1'b0;
            end else begin
            // DA=01:80:C2:00:00:01, EtherType=0x8808, opcode=0x0001
            is_pause_ctrl_header =
                (hdr[0*8 +: 8]  == 8'h01) &&
                (hdr[1*8 +: 8]  == 8'h80) &&
                (hdr[2*8 +: 8]  == 8'hC2) &&
                (hdr[3*8 +: 8]  == 8'h00) &&
                (hdr[4*8 +: 8]  == 8'h00) &&
                (hdr[5*8 +: 8]  == 8'h01) &&
                (hdr[12*8 +: 8] == 8'h88) &&
                (hdr[13*8 +: 8] == 8'h08) &&
                (hdr[14*8 +: 8] == 8'h00) &&
                (hdr[15*8 +: 8] == 8'h01);
            end
        end
    endfunction

    assign header_fifo_empty = (header_fifo_count_reg == 0);
    assign header_fifo_full  = (header_fifo_count_reg == HEADER_FIFO_DEPTH);
    assign header_fifo_head  = header_fifo_mem[header_fifo_rd_ptr_reg];
    assign ethertype_fifo_empty = (ethertype_fifo_count_reg == 0);
    assign ethertype_fifo_full  = (ethertype_fifo_count_reg == ETHERTYPE_FIFO_DEPTH);
    assign ethertype_fifo_head  = ethertype_fifo_mem[ethertype_fifo_rd_ptr_reg];
    assign crypto_enable = enable && PROTECT_ENABLE;

    assign split_payload_present = |split_payload_keep_reg;
    // Do not accept a new frame while previous frame header is still pending
    // enqueue; otherwise back-to-back frame ends can overwrite pending header
    // metadata and desynchronize header/ethertype pairing.
    assign s_axis_ready_int = payload_fifo_tready && !header_push_pending_reg;
    assign strip_push_beat = in_axis_hs && split_payload_present && !drop_pause_frame_now;
    assign strip_payload_tready = strip_compact_tready;
    assign in_axis_hs = s_axis_tvalid && s_axis_tready && crypto_enable;
    assign s_axis_frame_end_hs = in_axis_hs && s_axis_tlast;
    assign pause_header_match_next = (split_header_count_next_reg == HEADER_BYTES) &&
        is_pause_ctrl_header(split_header_next_reg);
    assign drop_pause_frame_now = drop_pause_frame_reg || (!drop_pause_frame_reg && pause_header_match_next);
    assign out_axis_hs = out_tvalid_int && out_tready_int;
    assign out_start_hs = enable && (out_state_reg == OUT_IDLE) && out_axis_hs;

    always @* begin
        split_header_next_reg = in_header_reg;
        split_header_count_next_reg = in_header_count_reg;
        split_payload_data_reg = {`MACSEC_MAC_DATA_WIDTH{1'b0}};
        split_payload_keep_reg = {MAC_DATA_BYTES{1'b0}};

        hdr_count_tmp = in_header_count_reg;
        payload_idx_tmp = 0;

        for (i = 0; i < MAC_DATA_BYTES; i = i + 1) begin
            if (s_axis_tkeep[i]) begin
                if (hdr_count_tmp < HEADER_BYTES) begin
                    split_header_next_reg[hdr_count_tmp*8 +: 8] = s_axis_tdata[i*8 +: 8];
                    hdr_count_tmp = hdr_count_tmp + 1;
                end else begin
                    split_payload_data_reg[payload_idx_tmp*8 +: 8] = s_axis_tdata[i*8 +: 8];
                    split_payload_keep_reg[payload_idx_tmp] = 1'b1;
                    payload_idx_tmp = payload_idx_tmp + 1;
                end
            end
        end

        split_header_count_next_reg = hdr_count_tmp[4:0];
    end

    assign strip_tag_ready = !tag_fifo_full && !ethertype_fifo_full;
    assign strip_pn_ready = !tag_fifo_full && !ethertype_fifo_full;
    assign strip_ethertype_ready = !tag_fifo_full && !ethertype_fifo_full;
    assign tag_fifo_wr_en = strip_tag_valid && strip_pn_valid && strip_ethertype_valid &&
        strip_tag_ready && strip_pn_ready && strip_ethertype_ready;
    assign tag_fifo_rd_en = decrypt_tag_read;

    assign plain_fifo_wr_en = ip_plaintext_write && !plain_fifo_full;
    assign plain_fifo_rd_en = out_bridge_plain_read && !plain_fifo_empty;
    assign ctag_fifo_wr_en = ip_computed_tag_write && !ctag_fifo_full;
    assign ctag_fifo_rd_en = out_bridge_ctag_read && !ctag_fifo_empty;
    assign plen_fifo_wr_en = ip_length_write && !plen_fifo_full;
    assign plen_fifo_rd_en = out_bridge_plen_read && !plen_fifo_empty;
    assign pend_fifo_wr_en = ip_end_write && !pend_fifo_full;
    assign pend_fifo_rd_en = out_bridge_pend_read && !pend_fifo_empty;

    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(64),
        .READ_DATA_WIDTH(128),
        .WRITE_DATA_WIDTH(128),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(56),
        .PROG_EMPTY_THRESH(4),
        .USE_ADV_FEATURES("0000")
    )
    u_plain_fifo_hls (
        .sleep(1'b0),
        .rst(hls_rst),
        .wr_en(plain_fifo_wr_en),
        .din(ip_plaintext_din),
        .full(plain_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(plain_fifo_rd_en),
        .dout(plain_fifo_dout),
        .empty(plain_fifo_empty),
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
        .wr_clk(hls_clk)
    );

    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(16),
        .READ_DATA_WIDTH(128),
        .WRITE_DATA_WIDTH(128),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(12),
        .PROG_EMPTY_THRESH(2),
        .USE_ADV_FEATURES("0000")
    )
    u_ctag_fifo_hls (
        .sleep(1'b0),
        .rst(hls_rst),
        .wr_en(ctag_fifo_wr_en),
        .din(ip_computed_tag_din),
        .full(ctag_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(ctag_fifo_rd_en),
        .dout(ctag_fifo_dout),
        .empty(ctag_fifo_empty),
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
        .wr_clk(hls_clk)
    );

    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(32),
        .READ_DATA_WIDTH(64),
        .WRITE_DATA_WIDTH(64),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(24),
        .PROG_EMPTY_THRESH(4),
        .USE_ADV_FEATURES("0000")
    )
    u_plen_fifo_hls (
        .sleep(1'b0),
        .rst(hls_rst),
        .wr_en(plen_fifo_wr_en),
        .din(ip_length_din),
        .full(plen_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(plen_fifo_rd_en),
        .dout(plen_fifo_dout),
        .empty(plen_fifo_empty),
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
        .wr_clk(hls_clk)
    );

    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(32),
        .READ_DATA_WIDTH(1),
        .WRITE_DATA_WIDTH(1),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(24),
        .PROG_EMPTY_THRESH(4),
        .USE_ADV_FEATURES("0000")
    )
    u_pend_fifo_hls (
        .sleep(1'b0),
        .rst(hls_rst),
        .wr_en(pend_fifo_wr_en),
        .din(ip_end_din),
        .full(pend_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(pend_fifo_rd_en),
        .dout(pend_fifo_dout),
        .empty(pend_fifo_empty),
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
        .wr_clk(hls_clk)
    );

    always @(posedge mac_clk) begin
        if (mac_rst) begin
            in_header_reg <= {HEADER_BYTES*8{1'b0}};
            in_header_count_reg <= 5'd0;
            drop_pause_frame_reg <= 1'b0;
        end else if (in_axis_hs) begin
            if (!drop_pause_frame_reg && pause_header_match_next) begin
                drop_pause_frame_reg <= 1'b1;
            end
            if (s_axis_tlast) begin
                in_header_reg <= {HEADER_BYTES*8{1'b0}};
                in_header_count_reg <= 5'd0;
                drop_pause_frame_reg <= 1'b0;
            end else begin
                in_header_reg <= split_header_next_reg;
                in_header_count_reg <= split_header_count_next_reg;
            end
        end
    end

    axis_fifo #(
        .DEPTH(PAYLOAD_FIFO_DEPTH),
        .DATA_WIDTH(`MACSEC_MAC_DATA_WIDTH),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(MAC_DATA_BYTES),
        .LAST_ENABLE(1),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0),
        .RAM_PIPELINE(2),
        .FRAME_FIFO(0)
    )
    payload_fifo_inst (
        .clk(mac_clk),
        .rst(mac_rst),
        .s_axis_tdata(split_payload_data_reg),
        .s_axis_tkeep(split_payload_keep_reg),
        .s_axis_tvalid(strip_push_beat),
        .s_axis_tready(payload_fifo_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tid(8'd0),
        .s_axis_tdest(8'd0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(payload_fifo_tdata),
        .m_axis_tkeep(payload_fifo_tkeep),
        .m_axis_tvalid(payload_fifo_tvalid),
        .m_axis_tready(strip_in_ready),
        .m_axis_tlast(payload_fifo_tlast),
        .m_axis_tid(),
        .m_axis_tdest(),
        .m_axis_tuser(),
        .pause_req(1'b0),
        .pause_ack(),
        .status_depth(),
        .status_depth_commit(),
        .status_overflow(),
        .status_bad_frame(),
        .status_good_frame()
    );

    always @(posedge mac_clk) begin
        if (mac_rst) begin
            header_fifo_wr_ptr_reg <= {HEADER_FIFO_PTR_WIDTH{1'b0}};
            header_fifo_rd_ptr_reg <= {HEADER_FIFO_PTR_WIDTH{1'b0}};
            header_fifo_count_reg <= {HEADER_FIFO_PTR_WIDTH+1{1'b0}};
            header_push_pending_reg <= 1'b0;
            header_push_drop_reg <= 1'b0;
            header_push_data_reg <= {HEADER_BYTES*8{1'b0}};
        end else begin
            if (header_push_pending_reg) begin
                if (header_push_drop_reg) begin
                    header_push_pending_reg <= 1'b0;
                end else if (!header_fifo_full && !out_start_hs) begin
                    header_fifo_mem[header_fifo_wr_ptr_reg] <= header_push_data_reg;
                    header_fifo_wr_ptr_reg <= header_fifo_wr_ptr_reg + 1'b1;
                    header_fifo_count_reg <= header_fifo_count_reg + 1'b1;
                    header_push_pending_reg <= 1'b0;
                end else if (!header_fifo_full && out_start_hs && !header_fifo_empty) begin
                    header_fifo_mem[header_fifo_wr_ptr_reg] <= header_push_data_reg;
                    header_fifo_wr_ptr_reg <= header_fifo_wr_ptr_reg + 1'b1;
                    header_fifo_rd_ptr_reg <= header_fifo_rd_ptr_reg + 1'b1;
                    header_push_pending_reg <= 1'b0;
                end else if (header_fifo_full && out_start_hs && !header_fifo_empty) begin
                    header_fifo_mem[header_fifo_wr_ptr_reg] <= header_push_data_reg;
                    header_fifo_wr_ptr_reg <= header_fifo_wr_ptr_reg + 1'b1;
                    header_fifo_rd_ptr_reg <= header_fifo_rd_ptr_reg + 1'b1;
                    header_push_pending_reg <= 1'b0;
                end
            end else if (out_start_hs && !header_fifo_empty) begin
                header_fifo_rd_ptr_reg <= header_fifo_rd_ptr_reg + 1'b1;
                header_fifo_count_reg <= header_fifo_count_reg - 1'b1;
            end

            if (s_axis_frame_end_hs && !header_push_pending_reg) begin
                header_push_data_reg <= split_header_next_reg;
                header_push_pending_reg <= 1'b1;
                header_push_drop_reg <= drop_pause_frame_now;
            end
        end
    end

    always @(posedge mac_clk) begin
        if (mac_rst) begin
            ethertype_fifo_wr_ptr_reg <= 5'd0;
            ethertype_fifo_rd_ptr_reg <= 5'd0;
            ethertype_fifo_count_reg <= 6'd0;
        end else begin
            if (tag_fifo_wr_en && !out_start_hs && !ethertype_fifo_full) begin
                ethertype_fifo_mem[ethertype_fifo_wr_ptr_reg] <= strip_ethertype;
                ethertype_fifo_wr_ptr_reg <= ethertype_fifo_wr_ptr_reg + 1'b1;
                ethertype_fifo_count_reg <= ethertype_fifo_count_reg + 1'b1;
            end else if (!tag_fifo_wr_en && out_start_hs && !ethertype_fifo_empty) begin
                ethertype_fifo_rd_ptr_reg <= ethertype_fifo_rd_ptr_reg + 1'b1;
                ethertype_fifo_count_reg <= ethertype_fifo_count_reg - 1'b1;
            end else if (tag_fifo_wr_en && out_start_hs && !ethertype_fifo_full && !ethertype_fifo_empty) begin
                ethertype_fifo_mem[ethertype_fifo_wr_ptr_reg] <= strip_ethertype;
                ethertype_fifo_wr_ptr_reg <= ethertype_fifo_wr_ptr_reg + 1'b1;
                ethertype_fifo_rd_ptr_reg <= ethertype_fifo_rd_ptr_reg + 1'b1;
            end
        end
    end

    always @(posedge mac_clk) begin
        if (mac_rst) begin
            out_state_reg <= OUT_IDLE;
            out_header_reg <= {HEADER_BYTES*8{1'b0}};
        end else if (crypto_enable) begin
            case (out_state_reg)
                OUT_IDLE: begin
                    if (out_start_hs) begin
                        out_header_reg <= {
                            ethertype_fifo_head[7:0],
                            ethertype_fifo_head[15:8],
                            header_fifo_head[12*8-1:0]
                        };
                        out_state_reg <= OUT_HEADER;
                    end
                end
                OUT_HEADER: begin
                    if (out_axis_hs) begin
                        out_state_reg <= OUT_DEC;
                    end
                end
                OUT_DEC: begin
                    if (out_axis_hs && dec_payload_tlast) begin
                        out_state_reg <= OUT_IDLE;
                    end
                end
                default: out_state_reg <= OUT_IDLE;
            endcase
        end else begin
            out_state_reg <= OUT_IDLE;
        end
    end

    macsec_tag_strip #(
        // Input to tag_strip excludes Ethernet header, so accept any payload length
        // that still carries mandatory MACsec authentication data.
        .MIN_FRAME_BYTES(24)
    )
    u_tag_strip (
        .clk(mac_clk),
        .rst(mac_rst),
        .s_axis_tdata(payload_fifo_tdata),
        .s_axis_tkeep(payload_fifo_tkeep),
        .s_axis_tvalid(payload_fifo_tvalid),
        .s_axis_tready(strip_in_ready),
        .s_axis_tlast(payload_fifo_tlast),
        .m_tag(strip_tag),
        .m_tag_valid(strip_tag_valid),
        .m_tag_ready(strip_tag_ready),
        .m_pn(strip_pn),
        .m_pn_valid(strip_pn_valid),
        .m_pn_ready(strip_pn_ready),
        .m_ethertype(strip_ethertype),
        .m_ethertype_valid(strip_ethertype_valid),
        .m_ethertype_ready(strip_ethertype_ready),
        .m_axis_tdata(strip_payload_tdata),
        .m_axis_tkeep(strip_payload_tkeep),
        .m_axis_tvalid(strip_payload_tvalid),
        .m_axis_tready(strip_compact_tready),
        .m_axis_tlast(strip_payload_tlast)
    );

    xpm_fifo_async #(
        .CDC_SYNC_STAGES(2),
        .FIFO_WRITE_DEPTH(16),
        .READ_DATA_WIDTH(176),
        .READ_MODE("fwft"),
        .USE_ADV_FEATURES("0000"),
        .WRITE_DATA_WIDTH(176),
        .PROG_FULL_THRESH(10),
        .RD_DATA_COUNT_WIDTH(1),
        .SIM_ASSERT_CHK(0),
        .PROG_EMPTY_THRESH(2),
        .FULL_RESET_VALUE(1),
        .WR_DATA_COUNT_WIDTH(1)
    ) u_tag_cdc_fifo (
        .sleep(1'b0),
        .rst(hls_rst || mac_rst),
        .wr_clk(mac_clk),
        .wr_en(tag_fifo_wr_en),
        .din({strip_ethertype, strip_pn, strip_tag}),
        .full(tag_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_clk(hls_clk),
        .rd_en(tag_fifo_rd_en),
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

    axis_keep_compactor_rx #(
        .DATA_WIDTH(`MACSEC_MAC_DATA_WIDTH),
        .KEEP_WIDTH(MAC_DATA_BYTES),
        .USER_WIDTH(1),
        .BUFFER_BYTES(32)
    )
    u_in_compactor (
        .clk(mac_clk),
        .rst(mac_rst),
        .s_axis_tdata(strip_payload_tdata),
        .s_axis_tkeep(strip_payload_tkeep),
        .s_axis_tvalid(strip_payload_tvalid),
        .s_axis_tready(strip_compact_tready),
        .s_axis_tlast(strip_payload_tlast),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(strip_compact_tdata),
        .m_axis_tkeep(strip_compact_tkeep),
        .m_axis_tvalid(strip_compact_tvalid),
        .m_axis_tready(in_bridge_ready),
        .m_axis_tlast(strip_compact_tlast),
        .m_axis_tuser()
    );

    axis_to_ap_fifo_bridge u_in_bridge (
        .mac_clk(mac_clk),
        .mac_rst(mac_rst),
        .s_axis_tdata(strip_compact_tdata),
        .s_axis_tkeep(strip_compact_tkeep),
        .s_axis_tvalid(strip_compact_tvalid),
        .s_axis_tready(in_bridge_ready),
        .s_axis_tlast(strip_compact_tlast),
        .hls_clk(hls_clk),
        .hls_rst(hls_rst),
        .m_plaintext_dout(bridge_ciphertext_dout),
        .m_plaintext_empty_n(bridge_ciphertext_empty_n),
        .m_plaintext_read(bridge_ciphertext_read),
        .m_length_dout(bridge_length_dout),
        .m_length_empty_n(bridge_length_empty_n),
        .m_length_read(bridge_length_read),
        .m_end_dout(bridge_end_dout),
        .m_end_empty_n(bridge_end_empty_n),
        .m_end_read(bridge_end_read),
        .frame_start(),
        .frame_end()
    );

    macsec_aes_decrypt u_decrypt (
        .hls_clk(hls_clk),
        .hls_rst(hls_rst),
        .aes_key(aes_key),
        .ssci(ssci),
        .rx_pn(tag_fifo_dout[159:128]),
        .key_valid(1'b1),
        .busy(dec_busy),
        .s_ciphertext_dout(bridge_ciphertext_dout),
        .s_ciphertext_empty_n(bridge_ciphertext_empty_n),
        .s_ciphertext_read(bridge_ciphertext_read),
        .s_tag_dout(tag_fifo_dout[127:0]),
        .s_tag_empty_n(!tag_fifo_empty),
        .s_tag_read(decrypt_tag_read),
        .s_length_dout(bridge_length_dout),
        .s_length_empty_n(bridge_length_empty_n),
        .s_length_read(bridge_length_read),
        .s_end_dout(bridge_end_dout),
        .s_end_empty_n(bridge_end_empty_n),
        .s_end_read(bridge_end_read),
        .m_plaintext_din(ip_plaintext_din),
        .m_plaintext_full_n(!plain_fifo_full),
        .m_plaintext_write(ip_plaintext_write),
        .m_computed_tag_din(ip_computed_tag_din),
        .m_computed_tag_full_n(!ctag_fifo_full),
        .m_computed_tag_write(ip_computed_tag_write),
        .m_length_din(ip_length_din),
        .m_length_full_n(!plen_fifo_full),
        .m_length_write(ip_length_write),
        .m_end_din(ip_end_din),
        .m_end_full_n(!pend_fifo_full),
        .m_end_write(ip_end_write)
    );

    ap_fifo_to_axis_bridge u_out_bridge (
        .hls_clk(hls_clk),
        .hls_rst(hls_rst),
        .s_ciphertext_dout(plain_fifo_dout),
        .s_ciphertext_empty_n(!plain_fifo_empty),
        .s_ciphertext_read(out_bridge_plain_read),
        .s_tag_dout(ctag_fifo_dout),
        .s_tag_empty_n(!ctag_fifo_empty),
        .s_tag_read(out_bridge_ctag_read),
        .s_length_dout(plen_fifo_dout),
        .s_length_empty_n(!plen_fifo_empty),
        .s_length_read(out_bridge_plen_read),
        .s_end_dout(pend_fifo_dout),
        .s_end_empty_n(!pend_fifo_empty),
        .s_end_read(out_bridge_pend_read),
        .mac_clk(mac_clk),
        .mac_rst(mac_rst),
        .m_axis_tdata(dec_payload_tdata),
        .m_axis_tkeep(dec_payload_tkeep),
        .m_axis_tvalid(dec_payload_tvalid),
        .m_axis_tready(dec_payload_tready),
        .m_axis_tlast(dec_payload_tlast),
        .icv(dec_ctag_sideband),
        .icv_valid(dec_ctag_sideband_valid),
        .icv_ready(1'b1)
    );

    assign dec_payload_tready = (crypto_enable && out_state_reg == OUT_DEC) ? m_axis_tready : 1'b0;

    assign out_tdata_int =
        (out_state_reg == OUT_IDLE)   ? header_fifo_head[63:0] :
        (out_state_reg == OUT_HEADER) ? {{(`MACSEC_MAC_DATA_WIDTH-HEADER_BEAT1_BYTES*8){1'b0}}, out_header_reg[HEADER_BYTES*8-1:MAC_DATA_BYTES*8]} :
                                        dec_payload_tdata;

    assign out_tkeep_int =
        (out_state_reg == OUT_IDLE)   ? keep_mask_from_count(HEADER_BEAT0_BYTES) :
        (out_state_reg == OUT_HEADER) ? keep_mask_from_count(HEADER_BEAT1_BYTES) :
                                        dec_payload_tkeep;

    assign out_tvalid_int =
        (out_state_reg == OUT_IDLE)   ? (!header_fifo_empty && !ethertype_fifo_empty) :
        (out_state_reg == OUT_HEADER) ? 1'b1 :
                                        dec_payload_tvalid;

    assign out_tlast_int =
        (out_state_reg == OUT_DEC) ? dec_payload_tlast : 1'b0;
    assign out_tuser_int = {USER_WIDTH{1'b0}};

    axis_keep_compactor_rx #(
        .DATA_WIDTH(`MACSEC_MAC_DATA_WIDTH),
        .KEEP_WIDTH(MAC_DATA_BYTES),
        .USER_WIDTH(USER_WIDTH),
        .BUFFER_BYTES(64)
    )
    u_out_compactor (
        .clk(mac_clk),
        .rst(mac_rst),
        .s_axis_tdata(out_tdata_int),
        .s_axis_tkeep(out_tkeep_int),
        .s_axis_tvalid(out_tvalid_int),
        .s_axis_tready(out_tready_int),
        .s_axis_tlast(out_tlast_int),
        .s_axis_tuser(out_tuser_int),
        .m_axis_tdata(out_compact_tdata),
        .m_axis_tkeep(out_compact_tkeep),
        .m_axis_tvalid(out_compact_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(out_compact_tlast),
        .m_axis_tuser(out_compact_tuser)
    );

    assign m_axis_tdata = crypto_enable ? out_compact_tdata : s_axis_tdata;
    assign m_axis_tkeep = crypto_enable ? out_compact_tkeep : s_axis_tkeep;
    assign m_axis_tvalid = crypto_enable ? out_compact_tvalid : s_axis_tvalid;
    assign m_axis_tlast = crypto_enable ? out_compact_tlast : s_axis_tlast;
    assign m_axis_tuser = crypto_enable ? out_compact_tuser : s_axis_tuser;
    assign s_axis_tready = crypto_enable ? s_axis_ready_int : m_axis_tready;

    assign computed_icv = crypto_enable ? dec_ctag_sideband : {`MACSEC_ICV_WIDTH{1'b0}};
    assign icv_valid = crypto_enable ? dec_ctag_sideband_valid : 1'b0;
    assign busy = crypto_enable ? dec_busy : 1'b0;

endmodule

module axis_keep_compactor_rx #(
    parameter integer DATA_WIDTH = 64,
    parameter integer KEEP_WIDTH = DATA_WIDTH/8,
    parameter integer USER_WIDTH = 1,
    parameter integer BUFFER_BYTES = 64
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire [DATA_WIDTH-1:0]    s_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]    s_axis_tkeep,
    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire                     s_axis_tlast,
    input  wire [USER_WIDTH-1:0]    s_axis_tuser,
    output reg  [DATA_WIDTH-1:0]    m_axis_tdata,
    output wire [KEEP_WIDTH-1:0]    m_axis_tkeep,
    output wire                     m_axis_tvalid,
    input  wire                     m_axis_tready,
    output wire                     m_axis_tlast,
    output wire [USER_WIDTH-1:0]    m_axis_tuser
);

    localparam integer COUNT_W = $clog2(BUFFER_BYTES+1);

    reg [BUFFER_BYTES*8-1:0] buf_reg = {BUFFER_BYTES*8{1'b0}};
    reg [COUNT_W-1:0]        count_reg = {COUNT_W{1'b0}};
    reg                      last_pending_reg = 1'b0;
    reg [USER_WIDTH-1:0]     last_user_reg = {USER_WIDTH{1'b0}};

    reg [BUFFER_BYTES*8-1:0] buf_tmp;
    reg [COUNT_W-1:0]        count_tmp;
    reg                      last_pending_tmp;
    reg [USER_WIDTH-1:0]     last_user_tmp;

    integer i;
    integer out_n;
    integer wr_idx;

    function integer keep_count;
        input [KEEP_WIDTH-1:0] keep;
        integer n;
        begin
            keep_count = 0;
            for (n = 0; n < KEEP_WIDTH; n = n + 1) begin
                if (keep[n]) begin
                    keep_count = keep_count + 1;
                end
            end
        end
    endfunction

    function [KEEP_WIDTH-1:0] keep_mask_from_count;
        input integer byte_count;
        integer n;
        begin
            keep_mask_from_count = {KEEP_WIDTH{1'b0}};
            for (n = 0; n < KEEP_WIDTH; n = n + 1) begin
                if (n < byte_count) begin
                    keep_mask_from_count[n] = 1'b1;
                end
            end
        end
    endfunction

    wire out_full = (count_reg >= KEEP_WIDTH);
    wire out_partial = last_pending_reg && (count_reg != 0);
    wire out_valid_int = out_full || out_partial;

    wire [COUNT_W-1:0] out_bytes = out_full ? KEEP_WIDTH[COUNT_W-1:0] : count_reg;
    wire [COUNT_W-1:0] in_bytes = keep_count(s_axis_tkeep);

    wire will_pop = out_valid_int && m_axis_tready;
    wire [COUNT_W:0] free_bytes = (BUFFER_BYTES - count_reg) + (will_pop ? out_bytes : 0);

    assign s_axis_tready = !last_pending_reg && (!s_axis_tvalid || (in_bytes <= free_bytes));

    assign m_axis_tvalid = out_valid_int;
    assign m_axis_tkeep = out_valid_int ? keep_mask_from_count(out_bytes) : {KEEP_WIDTH{1'b0}};
    assign m_axis_tlast = out_valid_int && last_pending_reg && (count_reg <= KEEP_WIDTH);
    assign m_axis_tuser = m_axis_tlast ? last_user_reg : {USER_WIDTH{1'b0}};

    always @* begin
        m_axis_tdata = {DATA_WIDTH{1'b0}};
        for (i = 0; i < KEEP_WIDTH; i = i + 1) begin
            m_axis_tdata[i*8 +: 8] = buf_reg[i*8 +: 8];
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            buf_reg <= {BUFFER_BYTES*8{1'b0}};
            count_reg <= {COUNT_W{1'b0}};
            last_pending_reg <= 1'b0;
            last_user_reg <= {USER_WIDTH{1'b0}};
        end else begin
            buf_tmp = buf_reg;
            count_tmp = count_reg;
            last_pending_tmp = last_pending_reg;
            last_user_tmp = last_user_reg;

            if (will_pop) begin
                out_n = out_bytes;
                if (out_n > 0) begin
                    buf_tmp = buf_tmp >> (out_n*8);
                    count_tmp = count_tmp - out_n;
                end

                if (m_axis_tlast) begin
                    last_pending_tmp = 1'b0;
                    last_user_tmp = {USER_WIDTH{1'b0}};
                end
            end

            if (s_axis_tvalid && s_axis_tready) begin
                wr_idx = 0;
                for (i = 0; i < KEEP_WIDTH; i = i + 1) begin
                    if (s_axis_tkeep[i]) begin
                        buf_tmp[(count_tmp+wr_idx)*8 +: 8] = s_axis_tdata[i*8 +: 8];
                        wr_idx = wr_idx + 1;
                    end
                end

                count_tmp = count_tmp + wr_idx;

                if (s_axis_tlast) begin
                    last_pending_tmp = 1'b1;
                    last_user_tmp = s_axis_tuser;
                end
            end

            buf_reg <= buf_tmp;
            count_reg <= count_tmp;
            last_pending_reg <= last_pending_tmp;
            last_user_reg <= last_user_tmp;
        end
    end

endmodule
