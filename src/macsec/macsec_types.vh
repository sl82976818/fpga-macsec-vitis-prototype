// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026 Le Sun
// Author: Le Sun
//
// Part of the FPGA AES-GCM / MACsec research prototype.
//
// ==============================================================
// MACsec Engine Type Definitions
// ==============================================================

`ifndef __MACSEC_TYPES_VH__
`define __MACSEC_TYPES_VH__

// ==============================================================
// Clock Parameters
// ==============================================================
// MAC (XGMII) clock frequency
`define MACSEC_MAC_CLK_FREQ_MHZ      156.25
// HLS AES-GCM IP clock frequency
`define MACSEC_HLS_CLK_FREQ_MHZ     200.0

// ==============================================================
// Data Width Parameters
// ==============================================================
// MAC AXI-Stream data width (64-bit)
`define MACSEC_MAC_DATA_WIDTH       64
`define MACSEC_MAC_KEEP_WIDTH       (`MACSEC_MAC_DATA_WIDTH/8)
// AES-GCM HLS IP data width (128-bit)
`define MACSEC_HLS_DATA_WIDTH       128
// AES-128 key width
`define MACSEC_AES_KEY_WIDTH       128
// GCM IV width (96 bits)
`define MACSEC_IV_WIDTH            96
// ICV/Tag width (128 bits)
`define MACSEC_ICV_WIDTH          128
// AES block size (16 bytes)
`define MACSEC_BLOCK_SIZE_BYTES    16

// ==============================================================
// SecTAG Format (IEEE 802.1AE with SSCI)
// ==============================================================
// SecTAG total length: 6 bytes
`define SEC_TAG_LENGTH_BYTES       6
// TCI/AN: 2 bytes (TCI=1bit, AN=1bit, SL=2bits, reserved=12bits)
`define SEC_TAG_TCI_AN_BYTES       2
// PN: 4 bytes (Packet Number, big-endian)
`define SEC_TAG_PN_BYTES           4
// Full SecTAG (6 bytes, will be zero-padded to 16 for AAD)
`define SEC_TAG_LENGTH             48  // bits

// ICV length: 16 bytes
`define ICV_LENGTH_BYTES           16

// ==============================================================
// Frame Parameters
// ==============================================================
// Minimum Ethernet frame size
`define MACSEC_MIN_FRAME_SIZE      64
// Maximum Ethernet frame size (without VLAN)
`define MACSEC_MAX_FRAME_SIZE      1518
// Ethernet header size (DA + SA + EtherType)
`define ETH_HEADER_SIZE            14
// MACsec EtherType on wire
`define MACSEC_ETHERTYPE           16'h88E5

// ==============================================================
// FIFO Depths
// ==============================================================
// HLS IP processing latency is ~200 cycles, so CDC FIFO should be deep
// async_fifo depth must be power of 2
`define MACSEC_CDC_FIFO_DEPTH     256
`define MACSEC_BEAT_FIFO_DEPTH     32

// ==============================================================
// HLS IP Instance Name
// ==============================================================
// Encrypted HLS IP top module name
`define MACSEC_ENC_IP_MODULE       hls_aes128gcm_enc
// Decrypted HLS IP top module name
`define MACSEC_DEC_IP_MODULE       hls_aes128gcm_dec

// ==============================================================
// Register Offsets (for control interface)
// ==============================================================
`define MACSEC_REG_CTRL            4'h0  // Control register
`define MACSEC_REG_STATUS         4'h4  // Status register
`define MACSEC_REG_KEY0           4'h8  // AES Key [127:96]
`define MACSEC_REG_KEY1           4'hC  // AES Key [95:64]
`define MACSEC_REG_KEY2           4'h10 // AES Key [63:32]
`define MACSEC_REG_KEY3           4'h14 // AES Key [31:0]
`define MACSEC_REG_SSCI           4'h18 // Short SCI
`define MACSEC_REG_TX_PN          4'h1C // TX Packet Number
`define MACSEC_REG_RX_PN          4'h20 // RX Packet Number
`define MACSEC_REG_TX_CNT         4'h24 // TX frame count
`define MACSEC_REG_RX_CNT         4'h28 // RX frame count
`define MACSEC_REG_AUTH_FAIL_CNT  4'h2C // Authentication failure count

// ==============================================================
// Control Register Bits
// ==============================================================
`define MACSEC_CTRL_ENABLE        0  // MACsec enable
`define MACSEC_CTRL_TX_EN         1  // TX enable
`define MACSEC_CTRL_RX_EN         2  // RX enable
`define MACSEC_CTRL_KEY_WR        3  // Key write strobe

// ==============================================================
// Status Register Bits
// ==============================================================
`define MACSEC_STATUS_TX_READY    0  // TX path ready
`define MACSEC_STATUS_RX_READY    1  // RX path ready
`define MACSEC_STATUS_TX_BUSY     2  // TX busy
`define MACSEC_STATUS_RX_BUSY     3  // RX busy
`define MACSEC_STATUS_PN_OVERFLOW  4  // TX PN rolled over

`endif // __MACSEC_TYPES_VH__
