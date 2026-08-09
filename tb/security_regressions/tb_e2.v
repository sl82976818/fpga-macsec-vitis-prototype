// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
`timescale 1ns / 1ps
module tb_e2;
  reg hls_clk=0; always #5 hls_clk=~hls_clk;
  reg hls_rst=1;
  reg [127:0] aes_key=128'h00112233445566778899AABBCCDDEEFF;
  reg [31:0]  ssci=32'h12345678;
  reg key_valid=1;
  wire [31:0] tx_pn;
  wire busy;

  reg [127:0] pt=128'h0123456789ABCDEFFEDCBA9876543210;
  reg pt_empty=1, len_empty=1, end_empty=1, ct_full=1, tag_full=1, l_full=1, e_full=1;
  reg [63:0]  len=64'd16;

  macsec_aes_encrypt #(.PN_INIT(32'd1)) u (
    .hls_clk(hls_clk), .hls_rst(hls_rst),
    .aes_key(aes_key), .ssci(ssci), .key_valid(key_valid), .tx_pn(tx_pn), .busy(busy),
    .s_plaintext_dout(pt), .s_plaintext_empty_n(pt_empty), .s_plaintext_read(),
    .s_length_dout(len), .s_length_empty_n(len_empty), .s_length_read(),
    .s_end_dout(1'b0), .s_end_empty_n(end_empty), .s_end_read(),
    .m_ciphertext_din(), .m_ciphertext_full_n(ct_full), .m_ciphertext_write(),
    .m_tag_din(), .m_tag_full_n(tag_full), .m_tag_write(),
    .m_length_din(), .m_length_full_n(l_full), .m_length_write(),
    .m_end_din(), .m_end_full_n(e_full), .m_end_write()
  );

  integer cyc=0;
  always @(posedge hls_clk) begin
    cyc=cyc+1;
    if (cyc>=8) $display("E2 t=%0t cyc=%0d rst=%0d key=%h tx_pn=%0d busy=%0d", $time, cyc, hls_rst, u.aes_key[31:0], tx_pn, busy);
  end

  initial begin
    repeat(3) @(posedge hls_clk); hls_rst=0; repeat(2) @(posedge hls_clk);
    // let frame1 complete (stub pulses ap_done at cnt==4)
    repeat(40) @(posedge hls_clk);
    $display("E2 after frame1: tx_pn=%0d (expect 2)", tx_pn);
    // now assert reset -> PN should roll back to 1 (PN_INIT)
    hls_rst=1;
    repeat(3) @(posedge hls_clk);
    $display("E2 after reset: tx_pn=%0d (PN_INIT=1 => NONCE REUSE possible)", tx_pn);
    hls_rst=0;
    repeat(5) @(posedge hls_clk);
    // run frame2 and show it reuses PN=1 IV
    repeat(40) @(posedge hls_clk);
    $display("E2 frame2 uses IV with tx_pn=%0d while frame1 used tx_pn=1 -> SAME (key,PN) => same nonce", u.iv_reg[31:0]);
    $finish;
  end
endmodule