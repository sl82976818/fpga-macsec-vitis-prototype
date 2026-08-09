# Performance

All figures below are derived from the read-only cycle-level performance audit
(`docs/audits/VITS_MACSEC_10G_RECOVERY_AUDIT_20260806_205045.md` and its JSON
model). **No new measurements were made for this release candidate.** Figures
are explicitly labeled with their evidence class: `measured`,
`historical-label`, `modeled`, or `projected`.

## Definitions

```
block throughput   : what a single crypto block can sustain (cycles/block)
frame throughput   : what the whole frame path sustains (incl. per-frame setup)
Ethernet line rate : what the wire carries (incl. headers, IFG, preamble)
```

`block throughput != frame throughput != Ethernet line rate`. The GCM core is
fast per block; the frame path pays per-frame overhead; the wire adds framing
overhead.

## Clock domain

The audit evaluates the crypto/MAC domain at **156.25 MHz**
(`sfp0_tx_clk_int`). Note: `MACSEC_HLS_CLK_FREQ_MHZ` in `macsec_types.vh` says
200 MHz, but the routed implementation actually clocks the HLS domain from the
SFP TX clock (156.25 MHz) — the audit uses the implemented clock.

## Model: current architecture @ 156.25 MHz

`total = capture + crypto + release` (single-frame store-and-forward).

| Frame size (B) | Current (original) line Gbps | Cached-SA model line Gbps | Crypto-core-only (cached) line Gbps |
| --- | --- | --- | --- |
| 64 | 0.31 | 0.74 | n/a (setup-dominated) |
| 512 | 1.55 | 2.53 | n/a |
| 1518 | **2.60** | 3.34 | ~16 |
| 9000 | 3.67 | 3.87 | ~16+ |

Evidence class:

- `2.60` (1518B, current): **modeled** — reproduces the historical label.
- `0.31 / 1.55 / 3.67` (current column): **modeled**.
- `2.7/2.75G` historical label: **historical-label** — archived project
  naming/zip labels; no recovered board iperf artifact.
- Cached-SA column: **projected** (requires the v0.4 refactor, not implemented).
- Crypto-core-only ~16 Gbps: **projected** (modeled core with cached-SA;
  no standalone implementation exists).

## Per-frame crypto setup tax

Every frame pays a serial, non-pipelined crypto setup:

| Item | Cycles/frame |
| --- | --- |
| `updateKey()` (AES-128 key expansion) | ~13 |
| `H = AES_K(0)` | ~20 (2× AES) |
| `GF128_prepare()` (Y[0..127]) | ~129 |
| AAD + tail | ~4 |
| **Original total** | **~186** (~1.19 µs) |
| **Cached-SA total** (H/key/GF128 precomputed at SA config) | **~24** |

## Why 10G is not reachable today

1. **Per-frame setup tax** dominates small frames (186→24 cycles fixes most).
2. **Single-frame store-and-forward** serializes capture→crypto→release; the
   tag for frame N is only available after frame N is fully processed, so
   frame N+1 cannot overlap. This alone caps the datapath below 10G even with
   cached-SA (~3.3–3.9 Gbps modeled for 1518B).

Target architecture for the roadmap:

```
current : capture + crypto + release          (serialized)
target  : max(capture, crypto, release)       (pipelined, 2+ frame slots)
```

## Asymptotic limitation of the current wrapper

Even with the crypto setup fully cached, the current wrapper's
single-frame-in-flight behavior means throughput is bounded by the *sum* of
capture and release phases plus the minimum crypto time. The road to 10G
requires both cached-SA **and** frame-slot pipelining (see `docs/ROADMAP.md`).

## Honest claims

- The 2.7/2.75G label is **consistent** with the modeled 2.60 Gbps for
  1518-byte frames — it was not a fluke measurement, and it does not mean the
  crypto core is 2.7G-limited.
- `10G achieved`, `line-rate`, and `board verified 2.7G` are **not** claimed
  anywhere in this release.
