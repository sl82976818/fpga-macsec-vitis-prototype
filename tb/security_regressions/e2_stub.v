// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
// E2: reset-PN rollback proof.
// DUT = production macsec_aes_encrypt.v (unaltered) + a minimalist behavioral
//       stub of hls_aes128gcm_enc that latches a frame, then pulses ap_done,
//       so the wrapper's continuous-stream tx_pn+=1 path is exercised.
// Demonstrates: after at least one frame (tx_pn advanced to 2), asserting
//               hls_rst sets tx_pn back to PN_INIT(=1) with same key -> nonce reuse risk.
`timescale 1ns / 1ps

module hls_aes128gcm_enc (
  input  clk_ap_clk_wire, // not needed; use standard names
  input  wire ap_clk,
  input  wire ap_rst,
  input  wire ap_start,
  output reg  ap_done,
  output wire ap_idle,
  output wire ap_ready,
  input  wire [127:0] plaintext_dout,
  input  wire plaintext_empty_n,
  output reg plaintext_read,
  input  wire [127:0] cipherkey_dout,
  input  wire cipherkey_empty_n,
  output wire cipherkey_read,
  input  wire [95:0] IV_dout,
  input  wire IV_empty_n,
  output wire IV_read,
  input  wire [127:0] AAD_dout,
  input  wire AAD_empty_n,
  output wire AAD_read,
  input  wire [63:0] AAD_length_dout,
  input  wire AAD_length_empty_n,
  output wire AAD_length_read,
  input  wire [63:0] plaintext_length_dout,
  input  wire plaintext_length_empty_n,
  output wire plaintext_length_read,
  input  wire end_length_dout,
  input  wire end_length_empty_n,
  output reg end_length_read,
  output reg [127:0] ciphertext_din,
  input  wire ciphertext_full_n,
  output reg ciphertext_write,
  output reg [63:0] ciphertext_length_din,
  input  wire ciphertext_length_full_n,
  output reg ciphertext_length_write,
  output reg [127:0] tag_din,
  input  wire tag_full_n,
  output reg tag_write,
  output reg end_tag_din,
  input  wire end_tag_full_n,
  output reg end_tag_write
);
  // Behavior: when ap_start pulses, run for a few cycles then assert ap_done.
  reg [3:0] cnt=0;
  reg running=0, start_seen=0;
  assign ap_idle = !running;
  assign ap_ready = !running;

  always @(posedge ap_clk) begin
    if (ap_rst) begin running<=0; cnt<=0; ap_done<=0; end
    else begin
      ap_done<=0;
      if (ap_start) begin running<=1; cnt<=0; end
      if (running) begin
        cnt<=cnt+1;
        if (cnt==4) begin
          running<=0; ap_done<=1;
        end
      end
    end
  end
endmodule