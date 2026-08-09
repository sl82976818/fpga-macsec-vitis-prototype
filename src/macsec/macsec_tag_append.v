// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
`timescale 1ns / 1ps

`include "macsec_types.vh"

module macsec_tag_append #
(
    parameter integer DATA_WIDTH = `MACSEC_MAC_DATA_WIDTH,
    parameter integer KEEP_WIDTH = `MACSEC_MAC_KEEP_WIDTH,
    parameter integer MAX_BEATS  = 512,
    parameter integer AUTH_BYTES = 24
)
(
    input  wire                    clk,
    input  wire                    rst,

    input  wire [DATA_WIDTH-1:0]   s_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]   s_axis_tkeep,
    input  wire                    s_axis_tvalid,
    output wire                    s_axis_tready,
    input  wire                    s_axis_tlast,

    input  wire [127:0]            s_tag,
    input  wire [31:0]             s_pn,
    input  wire [15:0]             s_ethertype,
    input  wire                    s_tag_valid,
    output wire                    s_tag_ready,

    output reg  [DATA_WIDTH-1:0]   m_axis_tdata,
    output reg  [KEEP_WIDTH-1:0]   m_axis_tkeep,
    output reg                     m_axis_tvalid,
    input  wire                    m_axis_tready,
    output reg                     m_axis_tlast
);

    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            clog2 = 0;
            while (v > 0) begin
                v = v >> 1;
                clog2 = clog2 + 1;
            end
        end
    endfunction

    function [KEEP_WIDTH-1:0] keep_mask_from_count;
        input integer count;
        integer n;
        begin
            keep_mask_from_count = {KEEP_WIDTH{1'b0}};
            for (n = 0; n < KEEP_WIDTH; n = n + 1) begin
                if (n < count) begin
                    keep_mask_from_count[n] = 1'b1;
                end
            end
        end
    endfunction

    function [15:0] keep_count;
        input [KEEP_WIDTH-1:0] keep;
        integer n;
        begin
            keep_count = 16'd0;
            for (n = 0; n < KEEP_WIDTH; n = n + 1) begin
                if (keep[n]) begin
                    keep_count = keep_count + 16'd1;
                end
            end
        end
    endfunction

    function [7:0] auth_byte;
        input [15:0]  auth_idx;
        input [31:0]  pn;
        input [127:0] tag;
        input [15:0]  ethertype;
        begin
            case (auth_idx)
                16'd0:  auth_byte = pn[7:0];
                16'd1:  auth_byte = pn[15:8];
                16'd2:  auth_byte = pn[23:16];
                16'd3:  auth_byte = pn[31:24];
                16'd4:  auth_byte = ethertype[15:8];
                16'd5:  auth_byte = ethertype[7:0];
                16'd6:  auth_byte = 8'h00;
                16'd7:  auth_byte = 8'h00;
                16'd8:  auth_byte = tag[71:64];
                16'd9:  auth_byte = tag[79:72];
                16'd10: auth_byte = tag[87:80];
                16'd11: auth_byte = tag[95:88];
                16'd12: auth_byte = tag[103:96];
                16'd13: auth_byte = tag[111:104];
                16'd14: auth_byte = tag[119:112];
                16'd15: auth_byte = tag[127:120];
                16'd16: auth_byte = tag[7:0];
                16'd17: auth_byte = tag[15:8];
                16'd18: auth_byte = tag[23:16];
                16'd19: auth_byte = tag[31:24];
                16'd20: auth_byte = tag[39:32];
                16'd21: auth_byte = tag[47:40];
                16'd22: auth_byte = tag[55:48];
                16'd23: auth_byte = tag[63:56];
                default: auth_byte = 8'h00;
            endcase
        end
    endfunction

    localparam integer FIFO_WORD_WIDTH  = DATA_WIDTH + KEEP_WIDTH + 1;
    localparam integer FIFO_COUNT_WIDTH = (MAX_BEATS > 1) ? clog2(MAX_BEATS+1) : 1;

    localparam [1:0]
        ST_CAPTURE        = 2'd0,
        ST_WAITTAG        = 2'd1,
        ST_OUTPUT_PAYLOAD = 2'd2,
        ST_OUTPUT_AUTH    = 2'd3;
    localparam DEBUG_LOG = 1'b0;

    reg [1:0] state_reg = ST_CAPTURE;

    wire [FIFO_WORD_WIDTH-1:0] fifo_dout;
    wire                       fifo_empty;
    wire                       fifo_full;

    wire [DATA_WIDTH-1:0] fifo_dout_data;
    wire [KEEP_WIDTH-1:0] fifo_dout_keep;
    wire                  fifo_dout_last;

    assign fifo_dout_data = fifo_dout[DATA_WIDTH-1:0];
    assign fifo_dout_keep = fifo_dout[DATA_WIDTH+KEEP_WIDTH-1:DATA_WIDTH];
    assign fifo_dout_last = fifo_dout[FIFO_WORD_WIDTH-1];

    wire in_hs;
    wire out_hs;
    wire fifo_wr_en;
    wire fifo_rd_en;

    assign s_axis_tready = (state_reg == ST_CAPTURE) && !fifo_full;
    assign in_hs  = s_axis_tvalid && s_axis_tready;
    assign out_hs = m_axis_tvalid && m_axis_tready;

    assign fifo_wr_en = in_hs;
    assign fifo_rd_en =
        (state_reg == ST_OUTPUT_PAYLOAD) &&
        !fifo_empty &&
        (!m_axis_tvalid || out_hs);

    xpm_fifo_sync #(
        .DOUT_RESET_VALUE ("0"),
        .ECC_MODE         ("no_ecc"),
        .FIFO_MEMORY_TYPE ("block"),
        .FIFO_READ_LATENCY(0),
        .FIFO_WRITE_DEPTH (MAX_BEATS),
        .FULL_RESET_VALUE (0),
        .PROG_EMPTY_THRESH(10),
        .PROG_FULL_THRESH (10),
        .RD_DATA_COUNT_WIDTH(FIFO_COUNT_WIDTH),
        .READ_DATA_WIDTH  (FIFO_WORD_WIDTH),
        .READ_MODE        ("fwft"),
        .SIM_ASSERT_CHK   (0),
        .USE_ADV_FEATURES ("0000"),
        .WAKEUP_TIME      (0),
        .WRITE_DATA_WIDTH (FIFO_WORD_WIDTH),
        .WR_DATA_COUNT_WIDTH(FIFO_COUNT_WIDTH)
    )
    frame_fifo_inst (
        .sleep        (1'b0),
        .rst          (rst),
        .wr_clk       (clk),
        .wr_en        (fifo_wr_en),
        .din          ({s_axis_tlast, s_axis_tkeep, s_axis_tdata}),
        .full         (fifo_full),
        .prog_full    (),
        .wr_data_count(),
        .overflow     (),
        .wr_rst_busy  (),
        .almost_full  (),
        .wr_ack       (),
        .rd_en        (fifo_rd_en),
        .dout         (fifo_dout),
        .empty        (fifo_empty),
        .prog_empty   (),
        .rd_data_count(),
        .underflow    (),
        .rd_rst_busy  (),
        .almost_empty (),
        .data_valid   (),
        .injectsbiterr(1'b0),
        .injectdbiterr(1'b0),
        .sbiterr      (),
        .dbiterr      ()
    );

    reg [15:0] frame_byte_count_reg = 16'd0;

    reg [127:0] pending_tag_reg = 128'd0;
    reg [31:0]  pending_pn_reg  = 32'd0;
    reg [15:0]  pending_ethertype_reg = 16'd0;
    reg         tag_pending_valid_reg = 1'b0;

    reg [127:0] current_tag_reg = 128'd0;
    reg [31:0]  current_pn_reg  = 32'd0;
    reg [15:0]  current_ethertype_reg = 16'd0;

    reg [15:0] auth_index_reg = 16'd0;

    reg        out_fifo_last_reg = 1'b0;
    reg [15:0] out_auth_fill_reg = 16'd0;

    reg [15:0] payload_count_tmp;
    reg [15:0] auth_fill_count_tmp;
    reg [15:0] auth_left_tmp;
    reg [15:0] auth_send_count_tmp;
    reg [15:0] frame_byte_count_tmp;
    reg [DATA_WIDTH-1:0] out_data_tmp;
    reg [DATA_WIDTH-1:0] auth_word_tmp;

    integer j;

    assign s_tag_ready = !tag_pending_valid_reg;

    always @(posedge clk) begin
        if (rst) begin
            state_reg <= ST_CAPTURE;

            frame_byte_count_reg <= 16'd0;

            pending_tag_reg       <= 128'd0;
            pending_pn_reg        <= 32'd0;
            pending_ethertype_reg <= 16'd0;
            tag_pending_valid_reg <= 1'b0;

            current_tag_reg <= 128'd0;
            current_pn_reg  <= 32'd0;
            current_ethertype_reg <= 16'd0;

            auth_index_reg <= 16'd0;

            out_fifo_last_reg <= 1'b0;
            out_auth_fill_reg <= 16'd0;

            m_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m_axis_tkeep  <= {KEEP_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else begin
            if (s_tag_valid && s_tag_ready) begin
                pending_tag_reg       <= s_tag;
                pending_pn_reg        <= s_pn;
                pending_ethertype_reg <= s_ethertype;
                tag_pending_valid_reg <= 1'b1;
            end

            case (state_reg)
                ST_CAPTURE: begin
                    if (in_hs) begin
                        frame_byte_count_tmp = frame_byte_count_reg + keep_count(s_axis_tkeep);
                        frame_byte_count_reg <= frame_byte_count_tmp;

                        if (s_axis_tlast) begin
                            m_axis_tvalid <= 1'b0;
                            m_axis_tlast  <= 1'b0;
                            state_reg <= ST_WAITTAG;
                        end
                    end
                end

                ST_WAITTAG: begin
                    if (tag_pending_valid_reg) begin
                        if (DEBUG_LOG) begin
                            $display("[%t] %m APP_FRAME_START bytes=%0d pn=%0d tag=%h",
                                $time, frame_byte_count_reg, pending_pn_reg, pending_tag_reg);
                        end
                        current_tag_reg       <= pending_tag_reg;
                        current_pn_reg        <= pending_pn_reg;
                        current_ethertype_reg <= pending_ethertype_reg;
                        tag_pending_valid_reg <= 1'b0;
                        auth_index_reg        <= 16'd0;
                        out_fifo_last_reg     <= 1'b0;
                        out_auth_fill_reg     <= 16'd0;
                        m_axis_tvalid         <= 1'b0;
                        m_axis_tlast          <= 1'b0;

                        if (!fifo_empty) begin
                            state_reg <= ST_OUTPUT_PAYLOAD;
                        end else if (AUTH_BYTES != 0) begin
                            state_reg <= ST_OUTPUT_AUTH;
                        end else begin
                            frame_byte_count_reg <= 16'd0;
                            state_reg <= ST_CAPTURE;
                        end
                    end
                end

                ST_OUTPUT_PAYLOAD: begin
                    if (!m_axis_tvalid || out_hs) begin


                        if (out_hs && out_fifo_last_reg) begin
                            if (AUTH_BYTES == 0 || out_auth_fill_reg >= AUTH_BYTES) begin
                                frame_byte_count_reg <= 16'd0;
                                state_reg <= ST_CAPTURE;
                                m_axis_tvalid <= 1'b0;
                                m_axis_tlast  <= 1'b0;
                            end else begin

                                auth_word_tmp = {DATA_WIDTH{1'b0}};
                                auth_left_tmp = AUTH_BYTES - out_auth_fill_reg;
                                if (auth_left_tmp < KEEP_WIDTH) begin
                                    auth_send_count_tmp = auth_left_tmp;
                                end else begin
                                    auth_send_count_tmp = KEEP_WIDTH;
                                end

                                for (j = 0; j < KEEP_WIDTH; j = j + 1) begin
                                    if (j < auth_send_count_tmp) begin
                                        auth_word_tmp[j*8 +: 8] =
                                            auth_byte(out_auth_fill_reg + j[15:0], current_pn_reg, current_tag_reg, current_ethertype_reg);
                                    end
                                end

                                auth_index_reg <= out_auth_fill_reg;
                                state_reg <= ST_OUTPUT_AUTH;
                                m_axis_tdata  <= auth_word_tmp;
                                m_axis_tkeep  <= keep_mask_from_count(auth_send_count_tmp);
                                m_axis_tlast  <= (auth_left_tmp <= KEEP_WIDTH);
                                m_axis_tvalid <= (auth_send_count_tmp != 0);
                            end
                        end else if (!fifo_empty) begin
                            payload_count_tmp = keep_count(fifo_dout_keep);

                            if (!fifo_dout_last) begin
                                out_fifo_last_reg <= 1'b0;
                                out_auth_fill_reg <= 16'd0;

                                if (payload_count_tmp != 0) begin
                                    m_axis_tdata  <= fifo_dout_data;
                                    m_axis_tkeep  <= fifo_dout_keep;
                                    m_axis_tlast  <= 1'b0;
                                    m_axis_tvalid <= 1'b1;
                                end else begin
                                    m_axis_tvalid <= 1'b0;
                                    m_axis_tlast  <= 1'b0;
                                end
                            end else begin
                                out_data_tmp  = fifo_dout_data;

                                if (AUTH_BYTES == 0) begin
                                    auth_fill_count_tmp = 16'd0;
                                end else if ((KEEP_WIDTH - payload_count_tmp) < AUTH_BYTES) begin
                                    auth_fill_count_tmp = KEEP_WIDTH - payload_count_tmp;
                                end else begin
                                    auth_fill_count_tmp = AUTH_BYTES;
                                end


                                for (j = 0; j < KEEP_WIDTH; j = j + 1) begin
                                    if (j < auth_fill_count_tmp) begin
                                        out_data_tmp[(payload_count_tmp + j[15:0])*8 +: 8] =
                                            auth_byte(j[15:0], current_pn_reg, current_tag_reg, current_ethertype_reg);
                                    end
                                end

                                out_fifo_last_reg <= 1'b1;
                                out_auth_fill_reg <= auth_fill_count_tmp;

                                m_axis_tdata  <= out_data_tmp;
                                m_axis_tkeep  <= keep_mask_from_count(payload_count_tmp + auth_fill_count_tmp);
                                m_axis_tlast  <= (AUTH_BYTES <= (KEEP_WIDTH - payload_count_tmp));
                                m_axis_tvalid <= ((payload_count_tmp + auth_fill_count_tmp) != 0);
                            end
                        end else begin
                            m_axis_tvalid <= 1'b0;
                            m_axis_tlast  <= 1'b0;
                        end
                    end
                end

                ST_OUTPUT_AUTH: begin
                    if (!m_axis_tvalid || out_hs) begin
                        if (out_hs) begin
                            auth_left_tmp = AUTH_BYTES - auth_index_reg;
                            if (auth_left_tmp <= KEEP_WIDTH) begin
                                frame_byte_count_reg <= 16'd0;
                                state_reg <= ST_CAPTURE;
                                m_axis_tvalid <= 1'b0;
                                m_axis_tlast  <= 1'b0;
                            end else begin
                                auth_index_reg <= auth_index_reg + KEEP_WIDTH;
                            end
                        end


                        if (state_reg == ST_OUTPUT_AUTH && (!out_hs || (AUTH_BYTES - auth_index_reg > KEEP_WIDTH))) begin
                            auth_word_tmp = {DATA_WIDTH{1'b0}};

                            if (out_hs) begin
                                auth_left_tmp = AUTH_BYTES - (auth_index_reg + KEEP_WIDTH);
                                if (auth_left_tmp < KEEP_WIDTH) begin
                                    auth_send_count_tmp = auth_left_tmp;
                                end else begin
                                    auth_send_count_tmp = KEEP_WIDTH;
                                end

                                for (j = 0; j < KEEP_WIDTH; j = j + 1) begin
                                    if (j < auth_send_count_tmp) begin
                                        auth_word_tmp[j*8 +: 8] =
                                            auth_byte((auth_index_reg + KEEP_WIDTH) + j[15:0], current_pn_reg, current_tag_reg, current_ethertype_reg);
                                    end
                                end

                                m_axis_tdata  <= auth_word_tmp;
                                m_axis_tkeep  <= keep_mask_from_count(auth_send_count_tmp);
                                m_axis_tlast  <= (auth_left_tmp <= KEEP_WIDTH);
                                m_axis_tvalid <= (auth_send_count_tmp != 0);
                            end else begin
                                auth_left_tmp = AUTH_BYTES - auth_index_reg;
                                if (auth_left_tmp < KEEP_WIDTH) begin
                                    auth_send_count_tmp = auth_left_tmp;
                                end else begin
                                    auth_send_count_tmp = KEEP_WIDTH;
                                end

                                for (j = 0; j < KEEP_WIDTH; j = j + 1) begin
                                    if (j < auth_send_count_tmp) begin
                                        auth_word_tmp[j*8 +: 8] =
                                            auth_byte(auth_index_reg + j[15:0], current_pn_reg, current_tag_reg, current_ethertype_reg);
                                    end
                                end

                                m_axis_tdata  <= auth_word_tmp;
                                m_axis_tkeep  <= keep_mask_from_count(auth_send_count_tmp);
                                m_axis_tlast  <= (auth_left_tmp <= KEEP_WIDTH);
                                m_axis_tvalid <= (auth_send_count_tmp != 0);
                            end
                        end
                    end
                end

                default: begin
                    state_reg <= ST_CAPTURE;
                end
            endcase
        end
    end

endmodule
