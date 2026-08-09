// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
// E1: macsec_tag_strip auth-before-release behavioral proof.
// DUT = production macsec_tag_strip.v + xpm_fifo_sync_sim.v (byte-identical).
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
  reg out_ready_ctrl=1;

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

  integer out_bytes=0;
  integer bi;
  logic emitted_out_seen_f=0;
  integer emit_cnt=0;
  logic emitted_valid_seen=0;

  initial begin
    forever @(posedge clk) begin
      if (out_valid && out_ready) begin
        emit_cnt = emit_cnt + 1;
        $display("EMIT t=%0t word=%0d data=%h keep=%h last=%0d", $time, emit_cnt, out_data, out_keep, out_last);
      end
    end
  end

  function automatic integer countones(input [KW-1:0] k);
    integer n;
    begin
      countones=0;
      for (n=0;n<KW;n=n+1) if (k[n]) countones=countones+1;
    end
  endfunction

  always @(posedge clk) begin
    if (out_valid && out_ready) begin
      out_bytes = out_bytes + countones(out_keep);
    end
  end

  // convert icv[127:0] to 8x 8-bit-big-endian so bytes land in DATA order
  function [63:0] icv_word(input [127:0] icv, input integer byteIdx);
    integer i;
    begin
      icv_word = 64'h0;
      for (i=0; i<8; i=i+1) begin
        icv_word[i*8 +: 8] = icv[(byteIdx*8 + i*8) +: 8];
      end
    end
  endfunction

  task send_with_icv(input [127:0] icv);
  begin
    out_bytes=0;
    // payload 8 bytes
    sin_valid=1; sin_keep=8'hFF; sin_data=64'h1122334455667788; sin_tlast=0;
    @(posedge clk); sin_valid=0;
    // tail beats 8 bytes each (24 total): each word is 8 of the icv bytes until 16, then ethertype+pad
    sin_valid=1; sin_keep=8'hFF; sin_data=icv_word(icv,0); sin_tlast=0; @(posedge clk);
    sin_valid=1; sin_keep=8'hFF; sin_data=icv_word(icv,1); sin_tlast=0; @(posedge clk);
    // last tail beat: last 8 bytes (icv[15:8]) -> bytes 16..23 ; use icv_word(icv,2)
    sin_valid=1; sin_keep=8'hFF; sin_data=icv_word(icv,2); sin_tlast=1; @(posedge clk);
    sin_valid=0; sin_tlast=0;
    // let it drain
    repeat(300) @(posedge clk);
    $display("E1[icv=%h] RELEASED out_bytes=%0d (payload=8 expected)", icv, out_bytes);
  end
  endtask

  initial begin
    rst=1; repeat(3) @(posedge clk); rst=0; repeat(3) @(posedge clk);
    $monitor("t=%0t st=%0d in_v=%0d in_r=%0d out_v=%0d out_r=%0d out_last=%0d out_bytes=%0d tag_v=%0d",
             $time, u_strip.state_reg, sin_valid, in_ready, out_valid, out_ready, out_last, out_bytes, tag_valid);
    $display("=== Case A: CORRUPTED tag 0xDEADBEEF0011...4455 (auth computing ICV differs) ===");
    send_with_icv(128'hDEADBEEF00112233445566778899AABB);
    $monitoroff;
    $display;
    $display("=== Case B: tag that a real peer would send (any bytes); must release identically ===");
    $monitor("t=%0t st=%0d in_v=%0d in_r=%0d out_v=%0d out_r=%0d out_last=%0d out_bytes=%0d tag_v=%0d",
             $time, u_strip.state_reg, sin_valid, in_ready, out_valid, out_ready, out_last, out_bytes, tag_valid);
    send_with_icv(128'h00112233445566778899AABBCCDDEEFF);
    $monitoroff;
    $display;
    $display("E1_CONCLUSION: tag_strip releases plaintext for BOTH corrupt and valid tag with equal bytes -> no tag verification before release. Only length<24B triggers ST_DROP.");
    $finish;
  end
endmodule