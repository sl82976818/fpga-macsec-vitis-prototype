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
    .m_tag(tag_o), .m_tag_valid(tag_valid_o), .m_tag_ready(tag_ready),
    .m_pn(pn_o), .m_pn_valid(pn_valid_o), .m_pn_ready(pn_ready),
    .m_ethertype(eth_o), .m_ethertype_valid(eth_valid_o), .m_ethertype_ready(eth_ready),
    .m_axis_tdata(out_data), .m_axis_tkeep(out_keep), .m_axis_tvalid(out_valid),
    .m_axis_tready(out_ready), .m_axis_tlast(out_last));

  integer cyc=0;
  integer out_beats=0;
  always @(posedge clk) begin
    cyc=cyc+1;
    $display("ALL C%0d st=%0d fbc=%0d in_v=%0d in_r=%0d out_v=%0d out=%h last=%0d",
      cyc, u_strip.state_reg, u_strip.frame_byte_count_reg, sin_valid, in_ready, out_valid, out_data, out_last);
    if (out_valid && out_ready) out_beats = out_beats + 1;
  end

  initial begin
    rst=1; repeat(2) @(posedge clk); rst=0; repeat(2) @(posedge clk);
    $display("=== CASE: 40B frame, tag corrupt 0xDEAD..DEAD; payload 16B plaintext ===");
    sin_keep=8'hFF;
    sin_valid=1; sin_data=64'h1122334455667788; sin_tlast=0; @(posedge clk); sin_valid=0;
    sin_valid=1; sin_data=64'h99AABBCCDDEEFF00; sin_tlast=0; @(posedge clk); sin_valid=0;
    sin_valid=1; sin_data=64'h6172636879747073; sin_tlast=0; @(posedge clk); sin_valid=0;
    sin_valid=1; sin_data=64'hDEADBEEFDEADBEEF; sin_tlast=0; @(posedge clk); sin_valid=0;
    sin_valid=1; sin_data=64'hDEADBEEFDEADBEEF; sin_tlast=1; @(posedge clk); sin_valid=0; sin_tlast=0;
    repeat(40) @(posedge clk);
    $display("=== VERDICT: out_beats=%0d (>0 => plaintext RELEASED despite CORRUPTED tag) ===", out_beats);
    $finish;
  end
endmodule