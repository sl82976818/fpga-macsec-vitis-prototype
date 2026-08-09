// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
// E1b: sample every clock; log every cycle during OUTPUT/DRAIN phases.
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

  macsec_tag_strip #(
    .DATA_WIDTH(DW), .KEEP_WIDTH(KW), .AUTH_BYTES(AUTH_BYTES),
    .MIN_FRAME_BYTES(MIN_FRAME_BYTES), .MAX_BEATS(MAX_BEATS)
  ) u_strip (
    .clk(clk), .rst(rst),
    .s_axis_tdata(sin_data), .s_axis_tkeep(sin_keep), .s_axis_tvalid(sin_valid),
    .s_axis_tready(in_ready), .s_axis_tlast(sin_tlast),
    .m_tag(tag_o), .m_tag_valid(tag_valid), .m_tag_ready(tag_ready),
    .m_pn(pn_o), .m_pn_valid(pn_valid), .m_pn_ready(pn_ready),
    .m_ethertype(eth_o), .m_ethertype_valid(eth_valid),
    .m_ethertype_ready(eth_ready),
    .m_axis_tdata(out_data), .m_axis_tkeep(out_keep), .m_axis_tvalid(out_valid),
    .m_axis_tready(out_ready), .m_axis_tlast(out_last)
  );

  integer n=0;
  always @(posedge clk) begin
    n = n + 1;
    if (u_strip.state_reg != 3'd0 || out_valid) begin
      $display("CYC %0d t=%0t st=%0d in_v=%0d in_r=%0d out_v=%0d out_r=%0d out_keep=%h out_last=%0d tag_v=%0d pn_v=%0d eth_v=%0d",
        n, $time, u_strip.state_reg, sin_valid, in_ready, out_valid, out_ready, out_keep, out_last, tag_valid, pn_valid, eth_valid);
    end
  end

  initial begin
    rst=1; repeat(3) @(posedge clk); rst=0; repeat(3) @(posedge clk);

    // CORRUPTED tag frame: payload 8B + 24B tail = 32B total
    // beat0: payload
    sin_valid=1; sin_keep=8'hFF; sin_data=64'h1122334455667788; sin_tlast=0; @(posedge clk);
    // beat1-3: tail 24 bytes (PN + corrupt tag 16B + eth/pad)
    sin_data=64'hFFEEDDCCBBAA9988; @(posedge clk);
    sin_data=64'h7766554433221100; @(posedge clk);
    sin_data=64'h8877665544332211; sin_tlast=1; @(posedge clk);
    sin_valid=0; sin_tlast=0;

    repeat(300) @(posedge clk);
    $display("FINAL: max cycles=%0d out_bytes_count not tracked; see CYC log above", n);
    $finish;
  end
endmodule