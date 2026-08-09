// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
`timescale 1ns / 1ps

`include "macsec_types.vh"

module macsec_tag_strip #
(
    parameter integer DATA_WIDTH = `MACSEC_MAC_DATA_WIDTH,
    parameter integer KEEP_WIDTH = `MACSEC_MAC_KEEP_WIDTH,
    parameter integer MAX_BEATS  = 512,
    parameter integer AUTH_BYTES = 24,
    parameter integer MIN_FRAME_BYTES = 0
)
(
    input  wire                    clk,
    input  wire                    rst,

    input  wire [DATA_WIDTH-1:0]   s_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]   s_axis_tkeep,
    input  wire                    s_axis_tvalid,
    output wire                    s_axis_tready,
    input  wire                    s_axis_tlast,

    output reg  [127:0]            m_tag,
    output reg                     m_tag_valid,
    input  wire                    m_tag_ready,
    output reg  [31:0]             m_pn,
    output reg                     m_pn_valid,
    input  wire                    m_pn_ready,
    output reg  [15:0]             m_ethertype,
    output reg                     m_ethertype_valid,
    input  wire                    m_ethertype_ready,

    output reg  [DATA_WIDTH-1:0]   m_axis_tdata,
    output reg  [KEEP_WIDTH-1:0]   m_axis_tkeep,
    output reg                     m_axis_tvalid,
    input  wire                    m_axis_tready,
    output reg                     m_axis_tlast
);

    initial begin
        if (DATA_WIDTH != KEEP_WIDTH*8) begin
            $error("macsec_tag_strip: DATA_WIDTH must equal KEEP_WIDTH*8");
        end
        if (AUTH_BYTES < 24) begin
            $error("macsec_tag_strip: AUTH_BYTES must be >= 24");
        end
    end

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

    localparam integer FIFO_WORD_WIDTH  = DATA_WIDTH + KEEP_WIDTH + 1;
    localparam integer FIFO_COUNT_WIDTH = (MAX_BEATS > 1) ? clog2(MAX_BEATS+1) : 1;
    localparam [2:0]
        ST_CAPTURE = 3'd0,
        ST_OUTPUT  = 3'd1,
        ST_DRAIN   = 3'd2,
        ST_DROP    = 3'd3,
        ST_WAITTAG = 3'd4;
    localparam DEBUG_LOG = 1'b0;

    reg [2:0] state_reg = ST_CAPTURE;

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
        ((state_reg == ST_OUTPUT) && !fifo_empty && (!m_axis_tvalid || out_hs)) ||
        ((state_reg == ST_DRAIN) && !fifo_empty) ||
        ((state_reg == ST_DROP) && !fifo_empty);

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

    reg [15:0] frame_byte_count_reg  = 16'd0;
    reg [15:0] payload_remaining_reg = 16'd0;

    reg [AUTH_BYTES*8-1:0] tail_buf_reg   = {(AUTH_BYTES*8){1'b0}};
    reg [15:0]             tail_count_reg = 16'd0;

    reg [15:0] out_fifo_word_bytes_reg = 16'd0;
    reg        out_fifo_last_reg       = 1'b0;

    reg [15:0] frame_byte_count_tmp;
    reg [15:0] fifo_word_byte_count_tmp;
    reg [15:0] bytes_to_send_tmp;
    reg [AUTH_BYTES*8-1:0] tail_buf_tmp;
    reg [15:0]             tail_count_tmp;
    reg [7:0]              new_tail_byte_tmp;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            state_reg <= ST_CAPTURE;

            frame_byte_count_reg  <= 16'd0;
            payload_remaining_reg <= 16'd0;

            tail_buf_reg   <= {(AUTH_BYTES*8){1'b0}};
            tail_count_reg <= 16'd0;

            out_fifo_word_bytes_reg <= 16'd0;
            out_fifo_last_reg       <= 1'b0;

            m_tag       <= 128'd0;
            m_tag_valid <= 1'b0;
            m_pn        <= 32'd0;
            m_pn_valid  <= 1'b0;
            m_ethertype <= 16'd0;
            m_ethertype_valid <= 1'b0;

            m_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m_axis_tkeep  <= {KEEP_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else begin
            if (m_tag_valid && m_tag_ready) begin
                m_tag_valid <= 1'b0;
            end
            if (m_pn_valid && m_pn_ready) begin
                m_pn_valid <= 1'b0;
            end
            if (m_ethertype_valid && m_ethertype_ready) begin
                m_ethertype_valid <= 1'b0;
            end

            case (state_reg)
                ST_CAPTURE: begin
                    if (in_hs) begin
                        frame_byte_count_tmp = frame_byte_count_reg + keep_count(s_axis_tkeep);
                        frame_byte_count_reg <= frame_byte_count_tmp;

                        tail_buf_tmp   = tail_buf_reg;
                        tail_count_tmp = tail_count_reg;

                        for (i = 0; i < KEEP_WIDTH; i = i + 1) begin
                            if (s_axis_tkeep[i]) begin
                                new_tail_byte_tmp = s_axis_tdata[i*8 +: 8];

                                if (tail_count_tmp < AUTH_BYTES) begin
                                    tail_buf_tmp[tail_count_tmp*8 +: 8] = new_tail_byte_tmp;
                                    tail_count_tmp = tail_count_tmp + 16'd1;
                                end else begin
                                    tail_buf_tmp =
                                        (tail_buf_tmp >> 8) |
                                        (({{(AUTH_BYTES*8-8){1'b0}}, new_tail_byte_tmp}) << ((AUTH_BYTES-1)*8));
                                end
                            end
                        end

                        tail_buf_reg   <= tail_buf_tmp;
                        tail_count_reg <= tail_count_tmp;

                        if (s_axis_tlast) begin
                            m_axis_tvalid <= 1'b0;
                            m_axis_tlast  <= 1'b0;

                            if (frame_byte_count_tmp < MIN_FRAME_BYTES) begin
                                if (DEBUG_LOG) begin
                                    $display("[%t] %m STRIP_DROP bytes=%0d", $time, frame_byte_count_tmp);
                                end
                                state_reg <= ST_DROP;
                            end else begin
                                if (DEBUG_LOG) begin
                                    $display("[%t] %m STRIP_FRAME_END bytes=%0d pn_extract=%0d pn_hex=%h tag=%h",
                                        $time, frame_byte_count_tmp, tail_buf_tmp[31:0], tail_buf_tmp[31:0],
                                        {tail_buf_tmp[8*8 +: 64], tail_buf_tmp[16*8 +: 64]});
                                end
                                payload_remaining_reg <= frame_byte_count_tmp - AUTH_BYTES;
                                m_pn        <= tail_buf_tmp[31:0];
                                m_tag       <= {tail_buf_tmp[8*8 +: 64], tail_buf_tmp[16*8 +: 64]};
                                m_ethertype <= {tail_buf_tmp[39:32], tail_buf_tmp[47:40]};
                                m_pn_valid  <= 1'b1;
                                m_tag_valid <= 1'b1;
                                m_ethertype_valid <= 1'b1;
                                state_reg   <= ST_OUTPUT;
                            end
                        end
                    end
                end

                ST_OUTPUT: begin
                    if (!m_axis_tvalid || out_hs) begin

                        if (out_hs) begin
                            if (payload_remaining_reg <= out_fifo_word_bytes_reg) begin
                                payload_remaining_reg <= 16'd0;
                                if (out_fifo_last_reg) begin
                                    state_reg <= ST_WAITTAG;
                                end else begin
                                    state_reg <= ST_DRAIN;
                                end
                                m_axis_tvalid <= 1'b0;
                                m_axis_tlast  <= 1'b0;
                            end else begin
                                payload_remaining_reg <= payload_remaining_reg - out_fifo_word_bytes_reg;
                            end
                        end


                        if (state_reg == ST_OUTPUT && (!out_hs || (payload_remaining_reg > out_fifo_word_bytes_reg)) && !fifo_empty) begin
                            fifo_word_byte_count_tmp = keep_count(fifo_dout_keep);

                            if (out_hs) begin
                                if ((payload_remaining_reg - out_fifo_word_bytes_reg) < fifo_word_byte_count_tmp) begin
                                    bytes_to_send_tmp = payload_remaining_reg - out_fifo_word_bytes_reg;
                                end else begin
                                    bytes_to_send_tmp = fifo_word_byte_count_tmp;
                                end
                            end else begin
                                if (payload_remaining_reg < fifo_word_byte_count_tmp) begin
                                    bytes_to_send_tmp = payload_remaining_reg;
                                end else begin
                                    bytes_to_send_tmp = fifo_word_byte_count_tmp;
                                end
                            end

                            out_fifo_word_bytes_reg <= fifo_word_byte_count_tmp;
                            out_fifo_last_reg       <= fifo_dout_last;

                            if (bytes_to_send_tmp != 0) begin
                                m_axis_tdata  <= fifo_dout_data;
                                m_axis_tkeep  <= keep_mask_from_count(bytes_to_send_tmp);
                                if (out_hs) begin
                                    m_axis_tlast  <= ((payload_remaining_reg - out_fifo_word_bytes_reg) <= fifo_word_byte_count_tmp);
                                end else begin
                                    m_axis_tlast  <= (payload_remaining_reg <= fifo_word_byte_count_tmp);
                                end
                                m_axis_tvalid <= 1'b1;
                            end else begin
                                m_axis_tvalid <= 1'b0;
                                m_axis_tlast  <= 1'b0;
                                if (fifo_dout_last) begin
                                    state_reg <= ST_WAITTAG;
                                end else begin
                                    state_reg <= ST_DRAIN;
                                end
                            end
                        end else if (!m_axis_tvalid) begin
                            m_axis_tlast <= 1'b0;
                            m_axis_tvalid <= 1'b0;
                        end
                    end
                end

                ST_DRAIN: begin
                    if (!fifo_empty && fifo_dout_last) begin
                        state_reg <= ST_WAITTAG;
                    end
                end

                ST_DROP: begin
                    if (!fifo_empty && fifo_dout_last) begin
                        frame_byte_count_reg  <= 16'd0;
                        payload_remaining_reg <= 16'd0;
                        tail_buf_reg          <= {(AUTH_BYTES*8){1'b0}};
                        tail_count_reg        <= 16'd0;
                        state_reg             <= ST_CAPTURE;
                    end else if (fifo_empty) begin
                        frame_byte_count_reg  <= 16'd0;
                        payload_remaining_reg <= 16'd0;
                        tail_buf_reg          <= {(AUTH_BYTES*8){1'b0}};
                        tail_count_reg        <= 16'd0;
                        state_reg             <= ST_CAPTURE;
                    end
                end

                ST_WAITTAG: begin
                    if (!m_tag_valid && !m_pn_valid && !m_ethertype_valid) begin
                        frame_byte_count_reg   <= 16'd0;
                        payload_remaining_reg  <= 16'd0;
                        tail_buf_reg           <= {(AUTH_BYTES*8){1'b0}};
                        tail_count_reg         <= 16'd0;
                        out_fifo_word_bytes_reg <= 16'd0;
                        out_fifo_last_reg       <= 1'b0;
                        state_reg              <= ST_CAPTURE;
                    end
                end

                default: begin
                    state_reg <= ST_CAPTURE;
                end
            endcase
        end
    end

endmodule
