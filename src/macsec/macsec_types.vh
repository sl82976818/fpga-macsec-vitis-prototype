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


`define MACSEC_MAC_CLK_FREQ_MHZ      156.25

`define MACSEC_HLS_CLK_FREQ_MHZ     200.0


`define MACSEC_MAC_DATA_WIDTH       64
`define MACSEC_MAC_KEEP_WIDTH       (`MACSEC_MAC_DATA_WIDTH/8)

`define MACSEC_HLS_DATA_WIDTH       128

`define MACSEC_AES_KEY_WIDTH       128

`define MACSEC_IV_WIDTH            96

`define MACSEC_ICV_WIDTH          128

`define MACSEC_BLOCK_SIZE_BYTES    16


`define SEC_TAG_LENGTH_BYTES       6

`define SEC_TAG_TCI_AN_BYTES       2

`define SEC_TAG_PN_BYTES           4

`define SEC_TAG_LENGTH             48


`define ICV_LENGTH_BYTES           16


`define MACSEC_MIN_FRAME_SIZE      64

`define MACSEC_MAX_FRAME_SIZE      1518

`define ETH_HEADER_SIZE            14

`define MACSEC_ETHERTYPE           16'h88E5


`define MACSEC_CDC_FIFO_DEPTH     256
`define MACSEC_BEAT_FIFO_DEPTH     32


`define MACSEC_ENC_IP_MODULE       hls_aes128gcm_enc

`define MACSEC_DEC_IP_MODULE       hls_aes128gcm_dec


`define MACSEC_REG_CTRL            4'h0
`define MACSEC_REG_STATUS         4'h4
`define MACSEC_REG_KEY0           4'h8
`define MACSEC_REG_KEY1           4'hC
`define MACSEC_REG_KEY2           4'h10
`define MACSEC_REG_KEY3           4'h14
`define MACSEC_REG_SSCI           4'h18
`define MACSEC_REG_TX_PN          4'h1C
`define MACSEC_REG_RX_PN          4'h20
`define MACSEC_REG_TX_CNT         4'h24
`define MACSEC_REG_RX_CNT         4'h28
`define MACSEC_REG_AUTH_FAIL_CNT  4'h2C


`define MACSEC_CTRL_ENABLE        0
`define MACSEC_CTRL_TX_EN         1
`define MACSEC_CTRL_RX_EN         2
`define MACSEC_CTRL_KEY_WR        3


`define MACSEC_STATUS_TX_READY    0
`define MACSEC_STATUS_RX_READY    1
`define MACSEC_STATUS_TX_BUSY     2
`define MACSEC_STATUS_RX_BUSY     3
`define MACSEC_STATUS_PN_OVERFLOW  4

`endif
