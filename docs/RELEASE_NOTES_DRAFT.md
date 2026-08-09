# Release Notes (Draft)

Suggested text for the public announcement. **Draft only** — the author must
review before publication.

## Title

FPGA AES-GCM / Experimental MACsec Research Prototype — an open performance
and security post-mortem on Corundum + Vitis Security Library

## Suggested repository description

> FPGA AES-GCM / experimental MACsec research prototype on Corundum using AMD
> Vitis Security Library, with an open performance and security post-mortem.

## Suggested topics

```
fpga
verilog
systemverilog
vitis-hls
aes-gcm
macsec
corundum
10gbe
network-security
hardware-security
pcie
ethernet
```

Do **not** use: `production-macsec`, `8021ae-compliant`, `10g-macsec`
(unless/until the facts change).

## Suggested body

- What: an inline AES-128-GCM protected Ethernet datapath built on the
  open Corundum NIC framework with the AMD/Xilinx Vitis Security Library,
  plus the full engineering post-mortem.
- Historical baseline: ~2.7/2.75 Gbps label; cycle model reproduces ~2.60
  Gbps for 1518-byte frames; the crypto core is modeled 10G-capable with
  cached-SA, but the wrapper is single-frame store-and-forward — 10G is a
  roadmap, not a claim.
- Security: this revision is NOT production-secure MACsec. Two blockers were
  behaviorally reproduced: auth-before-release failure and reset-induced
  nonce-reuse risk. Replay protection and SA lifecycle are missing.
- What is included: provenance manifest, attribution, patches for modified
  Corundum files, audits, reproducible E1/E2 security experiments.
- What is not included: AMD-generated IP, bitstreams, caches, tool logs.
- Status: research/educational; do not deploy; do not cite as 802.1AE.
