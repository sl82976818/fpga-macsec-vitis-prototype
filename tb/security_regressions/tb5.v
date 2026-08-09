// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
`timescale 1ns / 1ps
module tb;
  localparam DW=64, KW=8, AUTH_BYTES=24, MIN_FRAME_BYTES=24, MAX_BEATS=64;
  reg clk=0; always #5 clk=~clk;
  reg rst=1;
  reg  [DW-1:0] sin_data=0;
  reg  [KW-1:0] sin_keep=0;
  reg           sin_valid=0;
  reg           sin_tlast=0;
  reg           tag_ready=1, pn_ready=1, eth_ready=1, out_ready=1;
  wire [127:0] tag_o; wire tag_valid_o; wire [31:0] pn_o; wire pn_valid_o;
  wire [15:0]  eth_o; wire eth_valid_o;
  wire [DW-1:0] out_data; wire [KW-1:0] out_keep; wire out_valid; wire out_last;
  wire in_ready;

  macsec_tag_strip #(.DATA_WIDTH(DW), .KEEP_WIDTH(KW), .AUTH_BYTES(AUTH_BYTES),
    .MIN_FRAME_BYTES(MIN_FRAME_BYTES), .MAX_BEATS(MAX_BEATS)) u_strip (
    .clk(clk), .rst(rst),
    .s_axis_tdata(sin_data), .s_axis_tkeep(sin_keep), .s_axis_tvalid(sin_valid),
    .s_axis_tready(in_ready), .s_axis_tlast(sin_tlast),
    .m_tag(tag_o), .m_tag_valid(tag_valid), .m_tag_ready(tag_ready),
    .m_pn(pn_o), .m_pn_valid(pn_valid), .m_pn_ready(pn_ready),
    .m_ethertype(eth_o), .m_ethertype_valid(eth_valid), .m_ethertype_ready(eth_ready),
    .m_axis_tdata(out_data), .m_axis_tkeep(out_keep), .m_axis_tvalid(out_valid),
    .m_axis_tready(out_ready), .m_axis_tlast(out_last));

  integer cyc=0;
  always @(posedge clk) begin
    cyc=cyc+1;
    $display("CYC%0d t=%0t st=%0d fbc=%0d plr=%0d in_v=%0d in_r=%0d out_v=%0d out_d=%h out_last=%0d tag=%h pn=%0d",
      cyc,$time,u_strip.state_reg,u_strip.frame_byte_count_reg,u_strip.payload_remaining_reg,
      sin_valid,in_ready,out_valid,out_data,out_last,tag_o,pn_o);
  end

  initial begin
    rst=1; repeat(3) @(posedge clk); rst=0; repeat(3) @(posedge clk);
    $display("=== CORRUPTED tag frame: 40B = 16 payload + 24 tag; last 16B tag = 0xDEAD..DEAD ===");
    sin_valid=1; sin_keep=8'hFF; sin_data=64'h1122334455667788; sin_tlast=0; @(posedge clk);
    sin_valid=1; sin_keep=8'hFF; sin_data=64'h99AABBCCDDEEFF00; sin_tlast=0; @(posedge clk);
    sin_valid=1; sin_keep=8'hFF; sin_data=64'h6172636879747073; sin_tlast=0; @(posedge clk);
    sin_valid=1; sin_keep=8'hFF; sin_data=64'hDEADBEEFDEADBEEF; sin_tlast=0; @(posedge clk);
    sin_valid=1; sin_keep=8'hFF; sin_data=64'hDEADBEEFDEADBEEF; sin_tlast=1; @(posedge clk);
    sin_valid=0; sin_tlast=0;
    repeat(40) @(posedge clk);
    $display("=== DONE: out_v=1 beats = RELEASED plaintext despite CORRUPTED tag ===");
    $finish;
  end
endmodule
