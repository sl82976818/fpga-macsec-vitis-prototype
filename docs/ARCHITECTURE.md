# Architecture

This document describes **two architectures**:

1. **CURRENT ARCHITECTURE** — what the archived/audited revision actually
   implements (single-frame store-and-forward, serialized).
2. **TARGET ARCHITECTURE** — the roadmap design (**NOT IMPLEMENTED**, shown
   only to make the roadmap concrete).

Do not mistake the target for something that exists.

## Block diagram (current)

```text
                        +-------------------------------------------------------------+
                        |                     FPGA (xcku040)                            |
                        |                                                              |
  PCIe host             |   +----------------+      +---------------+                  |
  +-------+             |   |  PCIe / DMA    |      | mqnic_core    |                  |
  |  DMA  | <-------->  |   |  XDMA/PCIe IP  | <--> | (Corundum)    |                  |
  +-------+             |   +----------------+      +-------+-------+                  |
                        |                                  |  AXIS 64b                 |
                        |                                  v                           |
                        |                        +-----------------+                  |
                        |                        |  eth_mac_10g    |  (10G MAC)        |
                        |                        +-------+---------+                  |
                        |                                |  XGMII / 156.25MHz           |
                        |                                v                             |
                        |                     +---------------------+                  |
                        |                     |   TX MACsec wrapper |                  |
                        |                     |  (macsec_tx_wrapper)|  capture ->       |
                        |                     |  single frame FIFO  |  crypto -> release|
                        |                     +----------+----------+                  |
                        |                                | 64b AXIS                   |
                        |                                v                             |
                        |                     +---------------------+                  |
                        |                     | macsec_tag_append   |  append PN+tag   |
                        |                     |  ST_CAPTURE/WAITTAG  |  wait 24B tag    |
                        |                     +----------+----------+                  |
                        |                                |                             |
                        |    +---------------------------+                             |
                        |    |  64 -> 128 bridge (axis_to_ap_fifo_bridge, CDC)          |
                        |    v                                                          |
                        |   +---------------------+     +--------------------------+    |
                        |   |  AES-GCM HLS IP     |     | (Vitis Security Lib GCM,  |    |
                        |   |  (aes128gcm_enc)     |     |  II=1 CTR/GHASH,          |    |
                        |   |  128b AP_FIFO       |     |  per-frame key/H/prep)    |    |
                        |   +---------------------+     +--------------------------+    |
                        |    |                                                            |
                        |    +------------------------------------------------------------+
                        |                     (same shape mirrored for RX, reversed)      |
                        |                     RX: tag_strip -> axis_to_ap -> HLS dec     |
                        |                     -> ap_to_axis -> rx_wrapper release        |
                        +---------------------------------------------------------------+
```

### TX path (current)

1. `mqnic_core` emits 64-bit AXI-Stream Ethernet frames.
2. `macsec_tx_wrapper` captures the full frame into a frame FIFO
   (single-frame-in-flight; `crypto_enable` is hard-wired 1).
3. Payload beats are widened 64→128 and clock-domain-crossed
   (`axis_to_ap_fifo_bridge`) into the HLS encrypt IP.
4. `macsec_aes_encrypt` drives the AP interface, assembles IV
   `{SSCI, tx_pn, 0x5C5C5C5C}` and AAD `{80'h0, 16'h0001, SSCI}`.
5. `macsec_tag_append` waits for the computed tag (ST_WAITTAG, ~24 bytes),
   then emits `payload + PN + TAG` (custom tail format).
6. Result goes back to the MAC. **Capture and release are serialized per
   frame.**

### RX path (current)

1. Incoming frame → `macsec_rx_wrapper` payload FIFO (whole frame buffered).
2. `macsec_tag_strip` extracts `{PN, TAG}` from the tail; emits payload.
3. `axis_to_ap_fifo_bridge` 64→128 CDC → HLS decrypt IP.
4. Decrypted plaintext → `ap_fifo_to_axis_bridge` 128→64 → released on
   `m_axis` **immediately, without comparing the computed ICV to the received
   tag** (auth-before-release gap).

## Data-plane facts

- **MAC data width**: 64-bit, 156.25 MHz (XGMII).
- **HLS data width**: 128-bit AP_FIFO; HLS IP generated for
  `xcku040-ffva1156-2-e`, Vitis HLS 2022.1.
- **IV/AAD (custom, not 802.1AE)**: see `docs/SECURITY_STATUS.md`.
- **Frame tail format (custom)**: `payload + PN(64b slot, low 32 used) + TAG(128b)`.

## Target architecture (NOT IMPLEMENTED)

```text
        SA configuration
             |
             +-- round keys (cached)
             +-- H (cached)
             +-- GHASH precomputation (cached)
             +-- generation/context ID
             |
             v
   central PN allocator
             |
             v
   +-----------------------------+
   |  frame slot 0 | slot 1 | .. |
   +-----------------------------+
             |
   capture -> crypto -> auth/commit -> release
```

- Cached-SA removes the per-frame setup tax (186 → ~24 cycles).
- Multiple frame slots let capture of frame N+1 overlap crypto/release of
  frame N → `max(capture, crypto, release)` instead of a serialized sum.
- Auth-before-release with zero-beat plaintext on failure is mandatory.
- PN is persistent/non-rollback with wrap fail-close.
