// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
`timescale 1ns / 1ps
`default_nettype none

/*
 * Lightweight behavioral model for xpm_fifo_async.
 *
 * This model covers the port/parameter subset used by the MACsec wrappers.
 * It supports async write/read clocks and FWFT read mode.
 */
module xpm_fifo_async #
(
    parameter integer CDC_SYNC_STAGES = 2,
    parameter integer FIFO_WRITE_DEPTH = 16,
    parameter integer READ_DATA_WIDTH = 8,
    parameter [8*4-1:0] READ_MODE = "fwft",
    parameter [8*4-1:0] USE_ADV_FEATURES = "0000",
    parameter integer WRITE_DATA_WIDTH = 8,
    parameter integer PROG_FULL_THRESH = 10,
    parameter integer RD_DATA_COUNT_WIDTH = 1,
    parameter integer SIM_ASSERT_CHK = 0,
    parameter integer PROG_EMPTY_THRESH = 10,
    parameter integer FULL_RESET_VALUE = 0,
    parameter integer WR_DATA_COUNT_WIDTH = 1
)
(
    input  wire                              sleep,
    input  wire                              rst,
    input  wire                              wr_clk,
    input  wire                              wr_en,
    input  wire [WRITE_DATA_WIDTH-1:0]       din,
    output wire                              full,
    output wire                              prog_full,
    output wire [WR_DATA_COUNT_WIDTH-1:0]    wr_data_count,
    output reg                               overflow,
    output wire                              wr_rst_busy,
    output wire                              almost_full,
    output reg                               wr_ack,
    input  wire                              rd_clk,
    input  wire                              rd_en,
    output wire [READ_DATA_WIDTH-1:0]        dout,
    output wire                              empty,
    output wire                              prog_empty,
    output wire [RD_DATA_COUNT_WIDTH-1:0]    rd_data_count,
    output reg                               underflow,
    output wire                              rd_rst_busy,
    output wire                              almost_empty,
    output reg                               data_valid,
    input  wire                              injectsbiterr,
    input  wire                              injectdbiterr,
    output wire                              sbiterr,
    output wire                              dbiterr
);

localparam integer ADDR_WIDTH = (FIFO_WRITE_DEPTH <= 2) ? 1 : $clog2(FIFO_WRITE_DEPTH);

reg [WRITE_DATA_WIDTH-1:0] mem [0:FIFO_WRITE_DEPTH-1];

reg [ADDR_WIDTH:0] wr_ptr_bin_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_gray_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_bin_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_gray_reg = {ADDR_WIDTH+1{1'b0}};

reg [ADDR_WIDTH:0] rd_ptr_gray_sync1_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_gray_sync2_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_gray_sync1_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] wr_ptr_gray_sync2_reg = {ADDR_WIDTH+1{1'b0}};

reg [READ_DATA_WIDTH-1:0] dout_reg = {READ_DATA_WIDTH{1'b0}};

function [ADDR_WIDTH:0] bin2gray;
    input [ADDR_WIDTH:0] bin;
    begin
        bin2gray = (bin >> 1) ^ bin;
    end
endfunction

function [ADDR_WIDTH:0] gray2bin;
    input [ADDR_WIDTH:0] gray;
    integer i;
    begin
        gray2bin[ADDR_WIDTH] = gray[ADDR_WIDTH];
        for (i = ADDR_WIDTH-1; i >= 0; i = i-1) begin
            gray2bin[i] = gray2bin[i+1] ^ gray[i];
        end
    end
endfunction

wire [ADDR_WIDTH:0] rd_ptr_bin_sync = gray2bin(rd_ptr_gray_sync2_reg);
wire [ADDR_WIDTH:0] wr_ptr_bin_sync = gray2bin(wr_ptr_gray_sync2_reg);

wire [ADDR_WIDTH:0] wr_count = wr_ptr_bin_reg - rd_ptr_bin_sync;
wire [ADDR_WIDTH:0] rd_count = wr_ptr_bin_sync - rd_ptr_bin_reg;

wire [ADDR_WIDTH:0] wr_ptr_bin_next = wr_ptr_bin_reg + 1'b1;
wire [ADDR_WIDTH:0] wr_ptr_gray_next = bin2gray(wr_ptr_bin_next);

wire full_int = (wr_ptr_gray_next == {~rd_ptr_gray_sync2_reg[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_sync2_reg[ADDR_WIDTH-2:0]});
wire empty_int = (wr_ptr_gray_sync2_reg == rd_ptr_gray_reg);

wire wr_fire = wr_en && !sleep && !full_int;
wire rd_fire = rd_en && !sleep && !empty_int;

wire [READ_DATA_WIDTH-1:0] dout_fwft = mem[rd_ptr_bin_reg[ADDR_WIDTH-1:0]][READ_DATA_WIDTH-1:0];

assign dout = (READ_MODE == "fwft") ? dout_fwft : dout_reg;

assign full = full_int;
assign empty = empty_int;

assign prog_full = (wr_count >= PROG_FULL_THRESH);
assign prog_empty = (rd_count <= PROG_EMPTY_THRESH);
assign almost_full = (wr_count >= FIFO_WRITE_DEPTH-1);
assign almost_empty = (rd_count <= 1);

assign wr_data_count = wr_count[WR_DATA_COUNT_WIDTH-1:0];
assign rd_data_count = rd_count[RD_DATA_COUNT_WIDTH-1:0];

assign wr_rst_busy = rst;
assign rd_rst_busy = rst;

assign sbiterr = 1'b0;
assign dbiterr = 1'b0;

always @(posedge wr_clk or posedge rst) begin
    if (rst) begin
        wr_ptr_bin_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
        rd_ptr_gray_sync1_reg <= {ADDR_WIDTH+1{1'b0}};
        rd_ptr_gray_sync2_reg <= {ADDR_WIDTH+1{1'b0}};
        overflow <= 1'b0;
        wr_ack <= 1'b0;
    end else begin
        rd_ptr_gray_sync1_reg <= rd_ptr_gray_reg;
        rd_ptr_gray_sync2_reg <= rd_ptr_gray_sync1_reg;

        overflow <= wr_en && !sleep && full_int;
        wr_ack <= wr_fire;

        if (wr_fire) begin
            mem[wr_ptr_bin_reg[ADDR_WIDTH-1:0]] <= din;
            wr_ptr_bin_reg <= wr_ptr_bin_reg + 1'b1;
            wr_ptr_gray_reg <= bin2gray(wr_ptr_bin_reg + 1'b1);
        end
    end
end

always @(posedge rd_clk or posedge rst) begin
    if (rst) begin
        rd_ptr_bin_reg <= {ADDR_WIDTH+1{1'b0}};
        rd_ptr_gray_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_gray_sync1_reg <= {ADDR_WIDTH+1{1'b0}};
        wr_ptr_gray_sync2_reg <= {ADDR_WIDTH+1{1'b0}};
        underflow <= 1'b0;
        data_valid <= 1'b0;
        dout_reg <= {READ_DATA_WIDTH{1'b0}};
    end else begin
        wr_ptr_gray_sync1_reg <= wr_ptr_gray_reg;
        wr_ptr_gray_sync2_reg <= wr_ptr_gray_sync1_reg;

        underflow <= rd_en && !sleep && empty_int;
        data_valid <= rd_fire;

        if (READ_MODE != "fwft" && rd_fire) begin
            dout_reg <= mem[rd_ptr_bin_reg[ADDR_WIDTH-1:0]][READ_DATA_WIDTH-1:0];
        end

        if (rd_fire) begin
            rd_ptr_bin_reg <= rd_ptr_bin_reg + 1'b1;
            rd_ptr_gray_reg <= bin2gray(rd_ptr_bin_reg + 1'b1);
        end
    end
end

endmodule

`default_nettype wire
