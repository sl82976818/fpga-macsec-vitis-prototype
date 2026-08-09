// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
`timescale 1ns / 1ps

`include "macsec_types.vh"

module macsec_tx_wrapper #
(
    parameter integer MAC_DATA_BYTES  = `MACSEC_MAC_KEEP_WIDTH,
    parameter integer BLOCK_SIZE_BYTES = `MACSEC_BLOCK_SIZE_BYTES,
    parameter integer USER_WIDTH = 17,
    parameter [31:0]  PN_INIT = 32'd1,
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
    output wire [31:0]                        tx_pn,
    output wire                               busy,
    input  wire                               enable
);


    localparam integer HEADER_BYTES = 14;
    localparam integer HEADER_BEAT0_BYTES = (HEADER_BYTES >= MAC_DATA_BYTES) ? MAC_DATA_BYTES : HEADER_BYTES;
    localparam integer HEADER_BEAT1_BYTES = (HEADER_BYTES > MAC_DATA_BYTES) ? (HEADER_BYTES - MAC_DATA_BYTES) : 0;
    localparam integer HEADER_FIFO_DEPTH = 32;
    localparam integer HEADER_FIFO_PTR_WIDTH = 5;
    localparam [15:0] MACSEC_WIRE_ETHERTYPE = 16'h88E5;
    localparam [1:0]
        OUT_IDLE   = 2'd0,
        OUT_HEADER = 2'd1,
        OUT_ENC    = 2'd2;

    wire [`MACSEC_HLS_DATA_WIDTH-1:0] bridge_plaintext_dout;
    wire bridge_plaintext_empty_n;
    wire bridge_plaintext_read;
    wire [63:0] bridge_length_dout;
    wire bridge_length_empty_n;
    wire bridge_length_read;
    wire bridge_end_dout;
    wire bridge_end_empty_n;
    wire bridge_end_read;

    wire [`MACSEC_HLS_DATA_WIDTH-1:0] ip_ciphertext_din;
    wire ip_ciphertext_write;
    wire [`MACSEC_HLS_DATA_WIDTH-1:0] ip_tag_din;
    wire ip_tag_write;
    wire [63:0] ip_length_din;
    wire ip_length_write;
    wire ip_end_din;
    wire ip_end_write;

    reg  [127:0] cipher_hold_reg = 128'd0;
    reg          cipher_hold_valid_reg = 1'b0;
    reg  [127:0] tag_hold_reg = 128'd0;
    reg          tag_hold_valid_reg = 1'b0;
    reg  [63:0]  len_hold_reg = 64'd0;
    reg  [63:0]  len_hold_reg2 = 64'd0;
    reg  [1:0]   len_hold_count_reg = 2'd0;
    reg          end_hold_reg = 1'b0;
    reg          end_hold_valid_reg = 1'b0;

    wire bridge_out_cipher_read;
    wire bridge_out_tag_read;
    wire bridge_out_len_read;
    wire bridge_out_end_read;
    wire [`MACSEC_HLS_DATA_WIDTH-1:0] cipher_fifo_dout;
    wire cipher_fifo_full;
    wire cipher_fifo_empty;
    wire cipher_fifo_wr_en;
    wire cipher_fifo_rd_en;
    wire [`MACSEC_HLS_DATA_WIDTH-1:0] tag_fifo_dout_hls;
    wire tag_fifo_full_hls;
    wire tag_fifo_empty_hls;
    wire tag_fifo_wr_en_hls;
    wire tag_fifo_rd_en_hls;
    wire [63:0] len_fifo_dout_hls;
    wire len_fifo_full_hls;
    wire len_fifo_empty_hls;
    wire len_fifo_wr_en_hls;
    wire len_fifo_rd_en_hls;
    wire end_fifo_dout_hls;
    wire end_fifo_full_hls;
    wire end_fifo_empty_hls;
    wire end_fifo_wr_en_hls;
    wire end_fifo_rd_en_hls;

    wire [`MACSEC_MAC_DATA_WIDTH-1:0] enc_payload_tdata;
    wire [MAC_DATA_BYTES-1:0]         enc_payload_tkeep;
    wire                              enc_payload_tvalid;
    wire                              enc_payload_tready;
    wire                              enc_payload_tlast;
    wire [127:0]                      enc_tag_sideband;
    wire                              enc_tag_sideband_valid;
    wire                              enc_tag_sideband_ready;

    wire [`MACSEC_MAC_DATA_WIDTH-1:0] enc_frame_tdata;
    wire [MAC_DATA_BYTES-1:0]         enc_frame_tkeep;
    wire                              enc_frame_tvalid;
    wire                              enc_frame_tready;
    wire                              enc_frame_tlast;

    wire enc_busy;
    wire in_bridge_ready;
    reg  [31:0] pn_sideband_reg = PN_INIT;

    reg [HEADER_BYTES*8-1:0] in_header_reg = {HEADER_BYTES*8{1'b0}};
    reg [4:0]                in_header_count_reg = 5'd0;
    reg [HEADER_BYTES*8-1:0] split_header_next_reg;
    reg [4:0]                split_header_count_next_reg;
    reg [`MACSEC_MAC_DATA_WIDTH-1:0] split_payload_data_reg;
    reg [MAC_DATA_BYTES-1:0]          split_payload_keep_reg;

    (* ram_style = "registers" *) reg [HEADER_BYTES*8-1:0] header_fifo_mem [0:HEADER_FIFO_DEPTH-1];
    reg [HEADER_FIFO_PTR_WIDTH-1:0] header_fifo_wr_ptr_reg = {HEADER_FIFO_PTR_WIDTH{1'b0}};
    reg [HEADER_FIFO_PTR_WIDTH-1:0] header_fifo_rd_ptr_reg = {HEADER_FIFO_PTR_WIDTH{1'b0}};
    reg [HEADER_FIFO_PTR_WIDTH:0]   header_fifo_count_reg = {HEADER_FIFO_PTR_WIDTH+1{1'b0}};
    reg [HEADER_BYTES*8-1:0]        out_header_reg = {HEADER_BYTES*8{1'b0}};
    reg [1:0]                       out_state_reg = OUT_IDLE;
    (* ram_style = "registers" *) reg [15:0] ethertype_fifo_mem [0:HEADER_FIFO_DEPTH-1];
    reg [HEADER_FIFO_PTR_WIDTH-1:0] ethertype_fifo_wr_ptr_reg = {HEADER_FIFO_PTR_WIDTH{1'b0}};
    reg [HEADER_FIFO_PTR_WIDTH-1:0] ethertype_fifo_rd_ptr_reg = {HEADER_FIFO_PTR_WIDTH{1'b0}};
    reg [HEADER_FIFO_PTR_WIDTH:0]   ethertype_fifo_count_reg = {HEADER_FIFO_PTR_WIDTH+1{1'b0}};


    reg                             header_pop_d1_reg = 1'b0;
    reg                             ethertype_pop_d1_reg = 1'b0;

    localparam integer TUSER_FIFO_DEPTH = 32;
    localparam integer TUSER_FIFO_PTR_WIDTH = 5;

    (* ram_style = "registers" *) reg [USER_WIDTH-1:0] tuser_fifo_mem [0:TUSER_FIFO_DEPTH-1];
    reg [TUSER_FIFO_PTR_WIDTH-1:0] tuser_fifo_wr_ptr_reg = {TUSER_FIFO_PTR_WIDTH{1'b0}};
    reg [TUSER_FIFO_PTR_WIDTH-1:0] tuser_fifo_rd_ptr_reg = {TUSER_FIFO_PTR_WIDTH{1'b0}};
    reg [TUSER_FIFO_PTR_WIDTH:0]   tuser_fifo_count_reg = {TUSER_FIFO_PTR_WIDTH+1{1'b0}};

    reg [USER_WIDTH-1:0] in_frame_tuser_reg = {USER_WIDTH{1'b0}};
    reg                  in_frame_active_reg = 1'b0;
    reg [USER_WIDTH-1:0] out_frame_tuser_reg = {USER_WIDTH{1'b0}};
    reg                  out_frame_active_reg = 1'b0;

    reg [USER_WIDTH-1:0] tuser_push_data_reg;
    reg                  tuser_push_reg;
    reg                  tuser_pop_reg;

    wire in_axis_hs;
    wire out_axis_hs;
    wire tuser_fifo_empty;
    wire tuser_fifo_full;
    wire [USER_WIDTH-1:0] tuser_fifo_head;
    wire [USER_WIDTH-1:0] out_tuser_int;

    wire header_fifo_empty;
    wire header_fifo_full;
    wire [HEADER_BYTES*8-1:0] header_fifo_head;
    wire ethertype_fifo_empty;
    wire ethertype_fifo_full;
    wire [15:0] ethertype_fifo_head;

    wire split_payload_present;
    wire input_needs_payload_ready;
    wire split_pre_push_needed;
    wire s_axis_ready_int;
    wire s_axis_frame_end_hs;
    wire out_start_hs;
    wire enc_tag_valid_int;
    wire tag_meta_hs;
    wire [`MACSEC_MAC_DATA_WIDTH-1:0] split_compact_tdata;
    wire [MAC_DATA_BYTES-1:0]         split_compact_tkeep;
    wire                              split_compact_tvalid;
    wire                              split_compact_tready;
    wire                              split_compact_tlast;
    wire [`MACSEC_MAC_DATA_WIDTH-1:0] split_pre_tdata;
    wire [MAC_DATA_BYTES-1:0]         split_pre_tkeep;
    wire                              split_pre_tvalid;
    wire                              split_pre_tready;
    wire                              split_pre_tlast;
    wire [`MACSEC_MAC_DATA_WIDTH-1:0] split_fifo_tdata;
    wire [MAC_DATA_BYTES-1:0]         split_fifo_tkeep;
    wire                              split_fifo_tvalid;
    wire                              split_fifo_tready;
    wire                              split_fifo_tlast;
    wire                              split_pre_in_valid;
    wire                              split_pre_in_last_hs;

    wire [`MACSEC_MAC_DATA_WIDTH-1:0] out_tdata_int;
    wire [MAC_DATA_BYTES-1:0]         out_tkeep_int;
    wire                              out_tvalid_int;
    wire                              out_tlast_int;
    wire                              out_tready_int;
    wire [`MACSEC_MAC_DATA_WIDTH-1:0] out_compact_tdata;
    wire [MAC_DATA_BYTES-1:0]         out_compact_tkeep;
    wire                              out_compact_tvalid;
    wire                              out_compact_tlast;
    wire [USER_WIDTH-1:0]             out_compact_tuser;

    integer i;
    integer hdr_count_tmp;
    integer payload_idx_tmp;

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

    wire crypto_enable;
    assign crypto_enable = enable && PROTECT_ENABLE;

    assign tuser_fifo_empty = (tuser_fifo_count_reg == 0);
    assign tuser_fifo_full  = (tuser_fifo_count_reg == TUSER_FIFO_DEPTH);
    assign tuser_fifo_head  = tuser_fifo_mem[tuser_fifo_rd_ptr_reg];

    assign header_fifo_empty = (header_fifo_count_reg == 0);
    assign header_fifo_full  = (header_fifo_count_reg == HEADER_FIFO_DEPTH);
    assign header_fifo_head  = header_fifo_mem[header_fifo_rd_ptr_reg];
    assign ethertype_fifo_empty = (ethertype_fifo_count_reg == 0);
    assign ethertype_fifo_full  = (ethertype_fifo_count_reg == HEADER_FIFO_DEPTH);
    assign ethertype_fifo_head  = ethertype_fifo_mem[ethertype_fifo_rd_ptr_reg];

    assign split_payload_present = |split_payload_keep_reg;
    assign split_pre_push_needed = split_payload_present;
    assign input_needs_payload_ready = split_pre_push_needed;
    assign split_pre_in_valid = s_axis_tvalid && enable && split_pre_push_needed;
    assign split_pre_in_last_hs = split_pre_in_valid && split_pre_tready && s_axis_tlast;

    assign s_axis_ready_int = !tuser_fifo_full && !header_fifo_full && !ethertype_fifo_full &&
        (!input_needs_payload_ready || split_pre_tready);

    assign in_axis_hs = s_axis_tvalid && s_axis_tready && crypto_enable;
    assign s_axis_frame_end_hs = in_axis_hs && s_axis_tlast && split_payload_present;
    assign out_axis_hs = out_tvalid_int && out_tready_int;
    assign out_start_hs = crypto_enable && (out_state_reg == OUT_IDLE) && out_axis_hs;
    assign enc_tag_valid_int = enc_tag_sideband_valid && !ethertype_fifo_empty;
    assign tag_meta_hs = enc_tag_valid_int && enc_tag_sideband_ready;

    assign out_tuser_int = out_frame_active_reg ? out_frame_tuser_reg :
        (tuser_fifo_empty ? {USER_WIDTH{1'b0}} : tuser_fifo_head);

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

    always @(posedge hls_clk) begin
        if (hls_rst) begin
            cipher_hold_valid_reg <= 1'b0;
            tag_hold_valid_reg <= 1'b0;
            len_hold_reg2 <= 64'd0;
            len_hold_count_reg <= 2'd0;
            end_hold_valid_reg <= 1'b0;
            end_hold_reg <= 1'b0;
        end else begin

            if (ip_ciphertext_write && bridge_out_cipher_read && cipher_hold_valid_reg) begin
                cipher_hold_reg <= ip_ciphertext_din;
                cipher_hold_valid_reg <= 1'b1;
            end else if (ip_ciphertext_write && !cipher_hold_valid_reg) begin
                cipher_hold_reg <= ip_ciphertext_din;
                cipher_hold_valid_reg <= 1'b1;
            end else if (bridge_out_cipher_read && cipher_hold_valid_reg) begin
                cipher_hold_valid_reg <= 1'b0;
            end


            if (ip_tag_write && bridge_out_tag_read && tag_hold_valid_reg) begin
                tag_hold_reg <= ip_tag_din;
                tag_hold_valid_reg <= 1'b1;
            end else if (ip_tag_write && !tag_hold_valid_reg) begin
                tag_hold_reg <= ip_tag_din;
                tag_hold_valid_reg <= 1'b1;
            end else if (bridge_out_tag_read && tag_hold_valid_reg) begin
                tag_hold_valid_reg <= 1'b0;
            end


            if (ip_length_write && (len_hold_count_reg != 2'd2) && !(bridge_out_len_read && (len_hold_count_reg != 2'd0))) begin
                if (len_hold_count_reg == 2'd0) begin
                    len_hold_reg <= ip_length_din;
                end else begin
                    len_hold_reg2 <= ip_length_din;
                end
                len_hold_count_reg <= len_hold_count_reg + 2'd1;
            end else if (!ip_length_write && bridge_out_len_read && (len_hold_count_reg != 2'd0)) begin
                if (len_hold_count_reg == 2'd2) begin
                    len_hold_reg <= len_hold_reg2;
                end
                len_hold_count_reg <= len_hold_count_reg - 2'd1;
            end else if (ip_length_write && bridge_out_len_read && (len_hold_count_reg != 2'd0)) begin
                if (len_hold_count_reg == 2'd1) begin
                    len_hold_reg <= ip_length_din;
                end else begin
                    len_hold_reg <= len_hold_reg2;
                    len_hold_reg2 <= ip_length_din;
                end
            end


            if (ip_end_write && bridge_out_end_read && end_hold_valid_reg) begin
                end_hold_reg <= ip_end_din;
                end_hold_valid_reg <= 1'b1;
            end else if (ip_end_write && !end_hold_valid_reg) begin
                end_hold_reg <= ip_end_din;
                end_hold_valid_reg <= 1'b1;
            end else if (bridge_out_end_read && end_hold_valid_reg) begin
                end_hold_valid_reg <= 1'b0;
            end
        end
    end

    always @(posedge mac_clk) begin
        if (mac_rst) begin
            pn_sideband_reg <= PN_INIT;
        end else if (tag_meta_hs) begin
            pn_sideband_reg <= pn_sideband_reg + 32'd1;
        end
    end

    always @(posedge mac_clk) begin
        if (mac_rst) begin
            in_header_reg <= {HEADER_BYTES*8{1'b0}};
            in_header_count_reg <= 5'd0;
        end else if (crypto_enable && s_axis_tvalid && s_axis_tready) begin
            if (s_axis_tlast) begin
                in_header_reg <= {HEADER_BYTES*8{1'b0}};
                in_header_count_reg <= 5'd0;
            end else begin
                in_header_reg <= split_header_next_reg;
                in_header_count_reg <= split_header_count_next_reg;
            end
        end
    end

    always @(posedge mac_clk) begin
        if (mac_rst) begin
            header_pop_d1_reg <= 1'b0;
            ethertype_pop_d1_reg <= 1'b0;
        end else begin
            header_pop_d1_reg <= out_start_hs;
            ethertype_pop_d1_reg <= tag_meta_hs;
        end
    end

    always @(posedge mac_clk) begin
        if (mac_rst) begin
            header_fifo_wr_ptr_reg <= {HEADER_FIFO_PTR_WIDTH{1'b0}};
            header_fifo_rd_ptr_reg <= {HEADER_FIFO_PTR_WIDTH{1'b0}};
            header_fifo_count_reg <= {HEADER_FIFO_PTR_WIDTH+1{1'b0}};
        end else begin
            if (s_axis_frame_end_hs && !header_pop_d1_reg && !header_fifo_full) begin
                header_fifo_mem[header_fifo_wr_ptr_reg] <= {
                    MACSEC_WIRE_ETHERTYPE[7:0],
                    MACSEC_WIRE_ETHERTYPE[15:8],
                    split_header_next_reg[12*8-1:0]
                };
                header_fifo_wr_ptr_reg <= header_fifo_wr_ptr_reg + 1'b1;
                header_fifo_count_reg <= header_fifo_count_reg + 1'b1;
            end else if (!s_axis_frame_end_hs && header_pop_d1_reg && !header_fifo_empty) begin
                header_fifo_rd_ptr_reg <= header_fifo_rd_ptr_reg + 1'b1;
                header_fifo_count_reg <= header_fifo_count_reg - 1'b1;
            end else if (s_axis_frame_end_hs && header_pop_d1_reg && !header_fifo_full && !header_fifo_empty) begin
                header_fifo_mem[header_fifo_wr_ptr_reg] <= {
                    MACSEC_WIRE_ETHERTYPE[7:0],
                    MACSEC_WIRE_ETHERTYPE[15:8],
                    split_header_next_reg[12*8-1:0]
                };
                header_fifo_wr_ptr_reg <= header_fifo_wr_ptr_reg + 1'b1;
                header_fifo_rd_ptr_reg <= header_fifo_rd_ptr_reg + 1'b1;
            end
        end
    end

    always @(posedge mac_clk) begin
        if (mac_rst) begin
            ethertype_fifo_wr_ptr_reg <= {HEADER_FIFO_PTR_WIDTH{1'b0}};
            ethertype_fifo_rd_ptr_reg <= {HEADER_FIFO_PTR_WIDTH{1'b0}};
            ethertype_fifo_count_reg <= {HEADER_FIFO_PTR_WIDTH+1{1'b0}};
        end else begin
            if (s_axis_frame_end_hs && !ethertype_pop_d1_reg && !ethertype_fifo_full) begin
                ethertype_fifo_mem[ethertype_fifo_wr_ptr_reg] <= {
                    split_header_next_reg[12*8 +: 8], split_header_next_reg[13*8 +: 8]
                };
                ethertype_fifo_wr_ptr_reg <= ethertype_fifo_wr_ptr_reg + 1'b1;
                ethertype_fifo_count_reg <= ethertype_fifo_count_reg + 1'b1;
            end else if (!s_axis_frame_end_hs && ethertype_pop_d1_reg && !ethertype_fifo_empty) begin
                ethertype_fifo_rd_ptr_reg <= ethertype_fifo_rd_ptr_reg + 1'b1;
                ethertype_fifo_count_reg <= ethertype_fifo_count_reg - 1'b1;
            end else if (s_axis_frame_end_hs && ethertype_pop_d1_reg && !ethertype_fifo_full && !ethertype_fifo_empty) begin
                ethertype_fifo_mem[ethertype_fifo_wr_ptr_reg] <= {
                    split_header_next_reg[12*8 +: 8], split_header_next_reg[13*8 +: 8]
                };
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
                        out_header_reg <= header_fifo_head;
                        out_state_reg <= OUT_HEADER;
                    end
                end
                OUT_HEADER: begin
                    if (out_axis_hs) begin
                        out_state_reg <= OUT_ENC;
                    end
                end
                OUT_ENC: begin
                    if (out_axis_hs && enc_frame_tlast) begin
                        out_state_reg <= OUT_IDLE;
                    end
                end
                default: out_state_reg <= OUT_IDLE;
            endcase
        end else begin
            out_state_reg <= OUT_IDLE;
        end
    end

    always @(posedge mac_clk) begin
        if (mac_rst) begin
            tuser_fifo_wr_ptr_reg <= {TUSER_FIFO_PTR_WIDTH{1'b0}};
            tuser_fifo_rd_ptr_reg <= {TUSER_FIFO_PTR_WIDTH{1'b0}};
            tuser_fifo_count_reg <= {TUSER_FIFO_PTR_WIDTH+1{1'b0}};
            in_frame_tuser_reg <= {USER_WIDTH{1'b0}};
            in_frame_active_reg <= 1'b0;
            out_frame_tuser_reg <= {USER_WIDTH{1'b0}};
            out_frame_active_reg <= 1'b0;
        end else begin
            tuser_push_reg = 1'b0;
            tuser_pop_reg = 1'b0;
            tuser_push_data_reg = {USER_WIDTH{1'b0}};

            if (in_axis_hs) begin
                if (!in_frame_active_reg) begin
                    in_frame_tuser_reg <= s_axis_tuser;
                    in_frame_active_reg <= !s_axis_tlast;

                    if (s_axis_tlast) begin
                        tuser_push_reg = 1'b1;
                        tuser_push_data_reg = s_axis_tuser;
                    end
                end else if (s_axis_tlast) begin
                    in_frame_active_reg <= 1'b0;
                    tuser_push_reg = 1'b1;
                    tuser_push_data_reg = {in_frame_tuser_reg[USER_WIDTH-1:1], s_axis_tuser[0]};
                end
            end

            if (out_axis_hs) begin
                if (!out_frame_active_reg) begin
                    if (!tuser_fifo_empty) begin
                        out_frame_tuser_reg <= tuser_fifo_head;
                        tuser_pop_reg = 1'b1;
                    end else begin
                        out_frame_tuser_reg <= {USER_WIDTH{1'b0}};
                    end
                    out_frame_active_reg <= !out_tlast_int;
                end else if (out_tlast_int) begin
                    out_frame_active_reg <= 1'b0;
                end
            end

            if (tuser_push_reg && !tuser_pop_reg && !tuser_fifo_full) begin
                tuser_fifo_mem[tuser_fifo_wr_ptr_reg] <= tuser_push_data_reg;
                tuser_fifo_wr_ptr_reg <= tuser_fifo_wr_ptr_reg + 1'b1;
                tuser_fifo_count_reg <= tuser_fifo_count_reg + 1'b1;
            end else if (!tuser_push_reg && tuser_pop_reg && !tuser_fifo_empty) begin
                tuser_fifo_rd_ptr_reg <= tuser_fifo_rd_ptr_reg + 1'b1;
                tuser_fifo_count_reg <= tuser_fifo_count_reg - 1'b1;
            end else if (tuser_push_reg && tuser_pop_reg && !tuser_fifo_empty) begin
                tuser_fifo_mem[tuser_fifo_wr_ptr_reg] <= tuser_push_data_reg;
                tuser_fifo_wr_ptr_reg <= tuser_fifo_wr_ptr_reg + 1'b1;
                tuser_fifo_rd_ptr_reg <= tuser_fifo_rd_ptr_reg + 1'b1;
            end
        end
    end


    assign split_pre_tdata = split_payload_data_reg;
    assign split_pre_tkeep = split_payload_keep_reg;
    assign split_pre_tvalid = split_pre_in_valid;
    assign split_pre_tlast = s_axis_tlast;
    assign split_pre_tready = split_fifo_tready;


    axis_fifo #(
        .DEPTH(64),
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
    split_to_compactor_fifo_inst (
        .clk(mac_clk),
        .rst(mac_rst),
        .s_axis_tdata(split_pre_tdata),
        .s_axis_tkeep(split_pre_tkeep),
        .s_axis_tvalid(split_pre_tvalid),
        .s_axis_tready(split_fifo_tready),
        .s_axis_tlast(split_pre_tlast),
        .s_axis_tid(8'd0),
        .s_axis_tdest(8'd0),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(split_fifo_tdata),
        .m_axis_tkeep(split_fifo_tkeep),
        .m_axis_tvalid(split_fifo_tvalid),
        .m_axis_tready(split_compact_tready),
        .m_axis_tlast(split_fifo_tlast),
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

    axis_keep_compactor_tx_simple #(
        .DATA_WIDTH(`MACSEC_MAC_DATA_WIDTH),
        .KEEP_WIDTH(MAC_DATA_BYTES),
        .USER_WIDTH(1),
        .BUFFER_BYTES(64)
    )
    u_in_compactor (
        .clk(mac_clk),
        .rst(mac_rst),
        .s_axis_tdata(split_fifo_tdata),
        .s_axis_tkeep(split_fifo_tkeep),
        .s_axis_tvalid(split_fifo_tvalid),
        .s_axis_tready(split_compact_tready),
        .s_axis_tlast(split_fifo_tlast),
        .s_axis_tuser(1'b0),
        .m_axis_tdata(split_compact_tdata),
        .m_axis_tkeep(split_compact_tkeep),
        .m_axis_tvalid(split_compact_tvalid),
        .m_axis_tready(in_bridge_ready),
        .m_axis_tlast(split_compact_tlast),
        .m_axis_tuser()
    );

    axis_to_ap_fifo_bridge #(
        .SAME_CLK(0)
    )
    u_in_bridge (
        .mac_clk(mac_clk),
        .mac_rst(mac_rst),
        .s_axis_tdata(split_compact_tdata),
        .s_axis_tkeep(split_compact_tkeep),
        .s_axis_tvalid(split_compact_tvalid),
        .s_axis_tready(in_bridge_ready),
        .s_axis_tlast(split_compact_tlast),
        .hls_clk(hls_clk),
        .hls_rst(hls_rst),
        .m_plaintext_dout(bridge_plaintext_dout),
        .m_plaintext_empty_n(bridge_plaintext_empty_n),
        .m_plaintext_read(bridge_plaintext_read),
        .m_length_dout(bridge_length_dout),
        .m_length_empty_n(bridge_length_empty_n),
        .m_length_read(bridge_length_read),
        .m_end_dout(bridge_end_dout),
        .m_end_empty_n(bridge_end_empty_n),
        .m_end_read(bridge_end_read),
        .frame_start(),
        .frame_end()
    );

    assign cipher_fifo_wr_en = ip_ciphertext_write && !cipher_fifo_full;
    assign tag_fifo_wr_en_hls = ip_tag_write && !tag_fifo_full_hls;
    assign len_fifo_wr_en_hls = ip_length_write && !len_fifo_full_hls;
    assign end_fifo_wr_en_hls = ip_end_write && !end_fifo_full_hls;
    assign cipher_fifo_rd_en = bridge_out_cipher_read && !cipher_fifo_empty;
    assign tag_fifo_rd_en_hls = bridge_out_tag_read && !tag_fifo_empty_hls;
    assign len_fifo_rd_en_hls = bridge_out_len_read && !len_fifo_empty_hls;
    assign end_fifo_rd_en_hls = bridge_out_end_read && !end_fifo_empty_hls;

    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(512),
        .READ_DATA_WIDTH(`MACSEC_HLS_DATA_WIDTH),
        .WRITE_DATA_WIDTH(`MACSEC_HLS_DATA_WIDTH),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(496),
        .PROG_EMPTY_THRESH(4),
        .USE_ADV_FEATURES("0000")
    )
    u_cipher_fifo_hls (
        .sleep(1'b0),
        .rst(hls_rst),
        .wr_en(cipher_fifo_wr_en),
        .din(ip_ciphertext_din),
        .full(cipher_fifo_full),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(cipher_fifo_rd_en),
        .dout(cipher_fifo_dout),
        .empty(cipher_fifo_empty),
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
        .FIFO_WRITE_DEPTH(64),
        .READ_DATA_WIDTH(`MACSEC_HLS_DATA_WIDTH),
        .WRITE_DATA_WIDTH(`MACSEC_HLS_DATA_WIDTH),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(60),
        .PROG_EMPTY_THRESH(4),
        .USE_ADV_FEATURES("0000")
    )
    u_tag_fifo_hls (
        .sleep(1'b0),
        .rst(hls_rst),
        .wr_en(tag_fifo_wr_en_hls),
        .din(ip_tag_din),
        .full(tag_fifo_full_hls),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(tag_fifo_rd_en_hls),
        .dout(tag_fifo_dout_hls),
        .empty(tag_fifo_empty_hls),
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
        .FIFO_WRITE_DEPTH(64),
        .READ_DATA_WIDTH(64),
        .WRITE_DATA_WIDTH(64),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(60),
        .PROG_EMPTY_THRESH(4),
        .USE_ADV_FEATURES("0000")
    )
    u_len_fifo_hls (
        .sleep(1'b0),
        .rst(hls_rst),
        .wr_en(len_fifo_wr_en_hls),
        .din(ip_length_din),
        .full(len_fifo_full_hls),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(len_fifo_rd_en_hls),
        .dout(len_fifo_dout_hls),
        .empty(len_fifo_empty_hls),
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
        .FIFO_WRITE_DEPTH(64),
        .READ_DATA_WIDTH(1),
        .WRITE_DATA_WIDTH(1),
        .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(60),
        .PROG_EMPTY_THRESH(4),
        .USE_ADV_FEATURES("0000")
    )
    u_end_fifo_hls (
        .sleep(1'b0),
        .rst(hls_rst),
        .wr_en(end_fifo_wr_en_hls),
        .din(ip_end_din),
        .full(end_fifo_full_hls),
        .prog_full(),
        .wr_data_count(),
        .overflow(),
        .wr_rst_busy(),
        .almost_full(),
        .wr_ack(),
        .rd_en(end_fifo_rd_en_hls),
        .dout(end_fifo_dout_hls),
        .empty(end_fifo_empty_hls),
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

    macsec_aes_encrypt u_encrypt (
        .hls_clk(hls_clk),
        .hls_rst(hls_rst),
        .aes_key(aes_key),
        .ssci(ssci),
        .key_valid(1'b1),
        .tx_pn(tx_pn),
        .busy(enc_busy),
        .s_plaintext_dout(bridge_plaintext_dout),
        .s_plaintext_empty_n(bridge_plaintext_empty_n),
        .s_plaintext_read(bridge_plaintext_read),
        .s_length_dout(bridge_length_dout),
        .s_length_empty_n(bridge_length_empty_n),
        .s_length_read(bridge_length_read),
        .s_end_dout(bridge_end_dout),
        .s_end_empty_n(bridge_end_empty_n),
        .s_end_read(bridge_end_read),
        .m_ciphertext_din(ip_ciphertext_din),
        .m_ciphertext_full_n(!cipher_fifo_full),
        .m_ciphertext_write(ip_ciphertext_write),
        .m_tag_din(ip_tag_din),
        .m_tag_full_n(!tag_fifo_full_hls),
        .m_tag_write(ip_tag_write),
        .m_length_din(ip_length_din),
        .m_length_full_n(!len_fifo_full_hls),
        .m_length_write(ip_length_write),
        .m_end_din(ip_end_din),
        .m_end_full_n(!end_fifo_full_hls),
        .m_end_write(ip_end_write)
    );

    ap_fifo_to_axis_bridge #(
        .SAME_CLK(0)
    )
    u_out_bridge (
        .hls_clk(hls_clk),
        .hls_rst(hls_rst),
        .s_ciphertext_dout(cipher_fifo_dout),
        .s_ciphertext_empty_n(!cipher_fifo_empty),
        .s_ciphertext_read(bridge_out_cipher_read),
        .s_tag_dout(tag_fifo_dout_hls),
        .s_tag_empty_n(!tag_fifo_empty_hls),
        .s_tag_read(bridge_out_tag_read),
        .s_length_dout(len_fifo_dout_hls),
        .s_length_empty_n(!len_fifo_empty_hls),
        .s_length_read(bridge_out_len_read),
        .s_end_dout(end_fifo_dout_hls),
        .s_end_empty_n(!end_fifo_empty_hls),
        .s_end_read(bridge_out_end_read),
        .mac_clk(mac_clk),
        .mac_rst(mac_rst),
        .m_axis_tdata(enc_payload_tdata),
        .m_axis_tkeep(enc_payload_tkeep),
        .m_axis_tvalid(enc_payload_tvalid),
        .m_axis_tready(enc_payload_tready),
        .m_axis_tlast(enc_payload_tlast),
        .icv(enc_tag_sideband),
        .icv_valid(enc_tag_sideband_valid),
        .icv_ready(enc_tag_sideband_ready)
    );

    macsec_tag_append u_tag_append (
        .clk(mac_clk),
        .rst(mac_rst),
        .s_axis_tdata(enc_payload_tdata),
        .s_axis_tkeep(enc_payload_tkeep),
        .s_axis_tvalid(enc_payload_tvalid),
        .s_axis_tready(enc_payload_tready),
        .s_axis_tlast(enc_payload_tlast),
        .s_tag(enc_tag_sideband),
        .s_pn(pn_sideband_reg),
        .s_ethertype(ethertype_fifo_head),
        .s_tag_valid(enc_tag_valid_int),
        .s_tag_ready(enc_tag_sideband_ready),
        .m_axis_tdata(enc_frame_tdata),
        .m_axis_tkeep(enc_frame_tkeep),
        .m_axis_tvalid(enc_frame_tvalid),
        .m_axis_tready(enc_frame_tready),
        .m_axis_tlast(enc_frame_tlast)
    );

    assign enc_frame_tready = (crypto_enable && out_state_reg == OUT_ENC) ? m_axis_tready : 1'b0;

    assign out_tdata_int =
        (out_state_reg == OUT_IDLE)   ? header_fifo_head[63:0] :
        (out_state_reg == OUT_HEADER) ? {{(`MACSEC_MAC_DATA_WIDTH-HEADER_BEAT1_BYTES*8){1'b0}}, out_header_reg[HEADER_BYTES*8-1:MAC_DATA_BYTES*8]} :
                                        enc_frame_tdata;

    assign out_tkeep_int =
        (out_state_reg == OUT_IDLE)   ? keep_mask_from_count(HEADER_BEAT0_BYTES) :
        (out_state_reg == OUT_HEADER) ? keep_mask_from_count(HEADER_BEAT1_BYTES) :
                                        enc_frame_tkeep;


    assign out_tvalid_int =
        (out_state_reg == OUT_IDLE)   ? (!header_fifo_empty && !tuser_fifo_empty && enc_frame_tvalid) :
        (out_state_reg == OUT_HEADER) ? 1'b1 :
                                        enc_frame_tvalid;

    assign out_tlast_int =
        (out_state_reg == OUT_ENC) ? enc_frame_tlast : 1'b0;

    axis_keep_compactor_tx #(
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

    assign s_axis_tready = crypto_enable ? s_axis_ready_int : m_axis_tready;
    assign m_axis_tdata = crypto_enable ? out_compact_tdata : s_axis_tdata;
    assign m_axis_tkeep = crypto_enable ? out_compact_tkeep : s_axis_tkeep;
    assign m_axis_tvalid = crypto_enable ? out_compact_tvalid : s_axis_tvalid;
    assign m_axis_tlast = crypto_enable ? out_compact_tlast : s_axis_tlast;
    assign m_axis_tuser = crypto_enable ? out_compact_tuser : s_axis_tuser;
    assign busy = crypto_enable ? enc_busy : 1'b0;

endmodule

module axis_keep_compactor_tx_simple #(
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
                if (keep[n]) keep_count = keep_count + 1;
            end
        end
    endfunction

    function [KEEP_WIDTH-1:0] keep_mask_from_count;
        input integer byte_count;
        integer n;
        begin
            keep_mask_from_count = {KEEP_WIDTH{1'b0}};
            for (n = 0; n < KEEP_WIDTH; n = n + 1) begin
                if (n < byte_count) keep_mask_from_count[n] = 1'b1;
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

module axis_keep_compactor_tx #(
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
    reg [USER_WIDTH-1:0]     first_user_reg = {USER_WIDTH{1'b0}};
    reg                      first_user_valid_reg = 1'b0;

    reg [BUFFER_BYTES*8-1:0] buf_tmp;
    reg [COUNT_W-1:0]        count_tmp;
    reg                      last_pending_tmp;
    reg [USER_WIDTH-1:0]     last_user_tmp;
    reg [USER_WIDTH-1:0]     first_user_tmp;
    reg                      first_user_valid_tmp;

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

    generate
        if (USER_WIDTH > 1) begin : gen_user_wide


            assign m_axis_tuser = out_valid_int ?
                {first_user_reg[USER_WIDTH-1:1], (m_axis_tlast ? last_user_reg[0] : first_user_reg[0])} :
                {USER_WIDTH{1'b0}};
        end else begin : gen_user_1bit
            assign m_axis_tuser = out_valid_int ?
                (m_axis_tlast ? last_user_reg : first_user_reg) :
                {USER_WIDTH{1'b0}};
        end
    endgenerate

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
            first_user_reg <= {USER_WIDTH{1'b0}};
            first_user_valid_reg <= 1'b0;
        end else begin
            buf_tmp = buf_reg;
            count_tmp = count_reg;
            last_pending_tmp = last_pending_reg;
            last_user_tmp = last_user_reg;
            first_user_tmp = first_user_reg;
            first_user_valid_tmp = first_user_valid_reg;

            if (will_pop) begin
                out_n = out_bytes;
                if (out_n > 0) begin
                    buf_tmp = buf_tmp >> (out_n*8);
                    count_tmp = count_tmp - out_n;
                end

                if (m_axis_tlast) begin
                    last_pending_tmp = 1'b0;
                    last_user_tmp = {USER_WIDTH{1'b0}};
                    first_user_tmp = {USER_WIDTH{1'b0}};
                    first_user_valid_tmp = 1'b0;
                end
            end

            if (s_axis_tvalid && s_axis_tready) begin
                if (!first_user_valid_tmp) begin
                    first_user_tmp = s_axis_tuser;
                    first_user_valid_tmp = 1'b1;
                end

                wr_idx = 0;
                for (i = 0; i < KEEP_WIDTH; i = i + 1) begin
                    if (s_axis_tkeep[i]) begin
                        buf_tmp[(count_tmp+wr_idx)*8 +: 8] = s_axis_tdata[i*8 +: 8];
                        wr_idx = wr_idx + 1;
                    end
                end

                count_tmp = count_tmp + wr_idx;

                if (s_axis_tlast) begin
                    if ((count_tmp + wr_idx) != 0) begin
                        last_pending_tmp = 1'b1;
                        last_user_tmp = s_axis_tuser;
                    end else begin
                        last_pending_tmp = 1'b0;
                        last_user_tmp = {USER_WIDTH{1'b0}};
                        first_user_tmp = {USER_WIDTH{1'b0}};
                        first_user_valid_tmp = 1'b0;
                    end
                end
            end

            buf_reg <= buf_tmp;
            count_reg <= count_tmp;
            last_pending_reg <= last_pending_tmp;
            last_user_reg <= last_user_tmp;
            first_user_reg <= first_user_tmp;
            first_user_valid_reg <= first_user_valid_tmp;
        end
    end

endmodule
