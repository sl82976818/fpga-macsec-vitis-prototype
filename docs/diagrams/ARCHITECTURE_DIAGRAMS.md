# Architecture Diagrams

Text renderings of the datapath. The canonical (larger) versions live in
`docs/ARCHITECTURE.md`.

## Current datapath (single-frame store-and-forward, serialized)

```
host -- PCIe/DMA --> mqnic_core --AXIS64@156.25MHz--> macsec_tx_wrapper
                                                     (capture full frame)
                                                         |
                                            +------------+------------+
                                            |   tag_append (wait tag) |
                                            +------------+------------+
                                                         |
                                            axis_to_ap_fifo_bridge (64->128, CDC)
                                                         |
                                            AES-GCM HLS IP (Vitis Security Lib)
                                            II=1 CTR/GHASH; per-frame updateKey/H/GF128
                                                         |
                                            ap_fifo_to_axis_bridge (128->64, CDC)
                                                         |
                                            +------------+------------+
                                            |   eth_mac_10g  -> SFP (XGMII)
                                            +------------+------------+

RX (mirror, reversed):  SFP -> eth_mac_10g -> macsec_rx_wrapper (payload FIFO)
                        -> tag_strip (extract PN+TAG, no auth gate)
                        -> axis_to_ap -> HLS decrypt -> ap_to_axis -> release
```

## Target datapath (roadmap, NOT implemented)

```
SA config (round keys / H / GHASH precompute / generation)
        |
central PN allocator
        |
frame slots [0..N-1]
        |
capture -> crypto -> auth/commit -> release      (overlapped)
```
