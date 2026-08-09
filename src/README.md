# src/

Source RTL, split by provenance.

| Directory | Contents | Provenance | License |
| --- | --- | --- | --- |
| `macsec/` | MACsec integration RTL authored by Le Sun: TX/RX wrappers, tag append/strip, AES-GCM wrapper (encrypt/decrypt), AXI-Stream&harr;AP_FIFO bridges, type definitions | Original Le Sun | BSD-2-Clause (header on each file) |
| `fpga/` | Corundum NIC RTL subset used by the prototype | Corundum (BSD-2-Clause-Views); `fpga_core.v`/`fpga_k35.v` modified by Le Sun | BSD-2-Clause-Views (headers retained) |

## macsec/ files

| File | Role |
| --- | --- |
| `macsec_types.vh` | shared widths/params (MAC 64-bit, HLS 128-bit, clock defs) |
| `macsec_aes_encrypt.v` | drives HLS encrypt IP; TX PN counter (see security note) |
| `macsec_aes_decrypt.v` | drives HLS decrypt IP; RX PN from frame tag |
| `macsec_tx_wrapper.v` | TX path: capture → crypto → release control |
| `macsec_rx_wrapper.v` | RX path: payload FIFO, tag strip, decrypt, release |
| `macsec_tag_append.v` | appends `PN + TAG` tail, waits for computed tag |
| `macsec_tag_strip.v` | strips tail, extracts PN/tag/ethertype |
| `axis_to_ap_fifo_bridge.v` | 64-bit AXIS → 128-bit AP_FIFO + CDC |
| `ap_fifo_to_axis_bridge.v` | 128-bit AP_FIFO → 64-bit AXIS + CDC |

Security-relevant caveats are documented in `docs/SECURITY_STATUS.md`;
performance-relevant caveats in `docs/PERFORMANCE.md`.

## fpga/ files

Mirrors the subset of the Corundum `fpga/` tree used by the archived project.
Modified files carry an explicit "Modified by Le Sun, 2026" block; the exact
diffs are in `patches/corundum/`.
