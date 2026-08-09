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
 * Lightweight behavioral model for xpm_fifo_sync.
 * Covers the port/parameter subset used by macsec_tag_append and macsec_tag_strip.
 * Supports synchronous reset and FWFT read mode with LATENCY=0.
 */
module xpm_fifo_sync #
(
    parameter integer CDC_SYNC_STAGES = 2,
    parameter [8*4-1:0] DOUT_RESET_VALUE = "0",
    parameter [8*4-1:0] ECC_MODE = "no_ecc",
    parameter [8*4-1:0] FIFO_MEMORY_TYPE = "block",
    parameter integer FIFO_READ_LATENCY = 1,
    parameter integer FIFO_WRITE_DEPTH = 16,
    parameter [8*4-1:0] FULL_RESET_VALUE = "0",
    parameter integer PROG_EMPTY_THRESH = 10,
    parameter integer PROG_FULL_THRESH = 10,
    parameter integer RD_DATA_COUNT_WIDTH = 1,
    parameter integer READ_DATA_WIDTH = 8,
    parameter [8*4-1:0] READ_MODE = "std",
    parameter integer SIM_ASSERT_CHK = 0,
    parameter integer USE_ADV_FEATURES = "0000",
    parameter integer WAKEUP_TIME = 0,
    parameter integer WRITE_DATA_WIDTH = 8,
    parameter integer WR_DATA_COUNT_WIDTH = 1
)
(
    input  wire                              sleep,
    input  wire                              rst,
    input  wire                              wr_clk,
    input  wire                              wr_en,
    input  wire [WRITE_DATA_WIDTH-1:0]      din,
    output wire                              full,
    output wire                              prog_full,
    output wire [WR_DATA_COUNT_WIDTH-1:0]    wr_data_count,
    output reg                               overflow,
    output wire                              wr_rst_busy,
    output wire                              almost_full,
    output reg                               wr_ack,
    input  wire                              rd_en,
    output wire [READ_DATA_WIDTH-1:0]        dout,
    output wire                              empty,
    output wire                              prog_empty,
    output wire [RD_DATA_COUNT_WIDTH-1:0]    rd_data_count,
    output reg                               underflow,
    output wire                              rd_rst_busy,
    output wire                              almost_empty,
    output wire                              data_valid,
    input  wire                              injectsbiterr,
    input  wire                              injectdbiterr,
    output wire                              sbiterr,
    output wire                              dbiterr
);

localparam integer ADDR_WIDTH = (FIFO_WRITE_DEPTH <= 2) ? 1 : $clog2(FIFO_WRITE_DEPTH);

reg [WRITE_DATA_WIDTH-1:0] mem [0:FIFO_WRITE_DEPTH-1];

reg [ADDR_WIDTH:0] wr_ptr_bin_reg = {ADDR_WIDTH+1{1'b0}};
reg [ADDR_WIDTH:0] rd_ptr_bin_reg = {ADDR_WIDTH+1{1'b0}};

reg [READ_DATA_WIDTH-1:0] dout_reg = {READ_DATA_WIDTH{1'b0}};

wire [ADDR_WIDTH:0] wr_count = wr_ptr_bin_reg - rd_ptr_bin_reg;
wire [ADDR_WIDTH:0] rd_count = wr_ptr_bin_reg - rd_ptr_bin_reg;

wire full_int = wr_ptr_bin_reg[ADDR_WIDTH] != rd_ptr_bin_reg[ADDR_WIDTH] &&
                wr_ptr_bin_reg[ADDR_WIDTH-1:0] == rd_ptr_bin_reg[ADDR_WIDTH-1:0];
wire empty_int = wr_ptr_bin_reg == rd_ptr_bin_reg;

wire wr_fire = wr_en && !sleep && !full_int;
wire rd_fire = rd_en && !sleep && !empty_int;

wire [READ_DATA_WIDTH-1:0] dout_fwft;
assign dout_fwft = mem[rd_ptr_bin_reg[ADDR_WIDTH-1:0]][READ_DATA_WIDTH-1:0];

generate
if (READ_MODE == "fwft" && FIFO_READ_LATENCY == 0) begin : gen_fwft
    assign dout = empty_int ? {READ_DATA_WIDTH{1'b0}} : dout_fwft;
    assign data_valid = !empty_int;
end else begin : gen_std
    assign dout = dout_reg;
    assign data_valid = rd_fire;
end
endgenerate

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

always @(posedge wr_clk) begin
    if (rst) begin
        wr_ptr_bin_reg <= {ADDR_WIDTH+1{1'b0}};
        overflow <= 1'b0;
        wr_ack <= 1'b0;
    end else begin
        overflow <= wr_en && !sleep && full_int;
        wr_ack <= wr_fire;

        if (wr_fire) begin
            mem[wr_ptr_bin_reg[ADDR_WIDTH-1:0]] <= din;
            wr_ptr_bin_reg <= wr_ptr_bin_reg + 1'b1;
        end
    end
end

always @(posedge wr_clk) begin
    if (rst) begin
        rd_ptr_bin_reg <= {ADDR_WIDTH+1{1'b0}};
        underflow <= 1'b0;
        dout_reg <= {READ_DATA_WIDTH{1'b0}};
    end else begin
        underflow <= rd_en && !sleep && empty_int;

        if (rd_fire && !(READ_MODE == "fwft" && FIFO_READ_LATENCY == 0)) begin
            dout_reg <= mem[rd_ptr_bin_reg[ADDR_WIDTH-1:0]][READ_DATA_WIDTH-1:0];
        end

        if (rd_fire) begin
            rd_ptr_bin_reg <= rd_ptr_bin_reg + 1'b1;
        end
    end
end

endmodule

`default_nettype wire
