# Reproducibility

This document states what can and cannot be reproduced from this release, and
how.

## Reproducible now

| Item | How | Notes |
| --- | --- | --- |
| HLS AES-GCM math tests (300 vectors vs OpenSSL) | Vivado HLS 2022.1 csim on `hls/src/project/aes128{enc,dec}` (`run_hls.tcl`) | Requires `<VITIS_SECURITY_LIB_ROOT>` to point at Vitis Libraries 2022.1; goldens in `gld.dat` |
| Performance cycle model | Re-run from the published tables/JSON in `docs/audits/` | The audit's model inputs are documented; the model script was not preserved |
| **E1** auth-before-release experiment | `tb/security_regressions/tb_tag_strip.v` (and variants) with iverilog + `src/macsec/macsec_tag_strip.v` | Needs a sim model for `xpm_fifo_sync`; a behavioral model is provided in `tb/cocotb/xpm_fifo_sync_sim.v`. Production RTL unchanged |
| **E2** reset/PN-rollback experiment | `tb/security_regressions/tb_e2.v` + `e2_stub.v` with iverilog + `src/macsec/macsec_aes_encrypt.v` | Stub replaces only the HLS IP; wrapper state machine is the production one |

See `tb/security_regressions/README.md` for exact commands.

## Not directly reproducible from this release

| Item | Reason |
| --- | --- |
| Historical board 2.7G iperf | Board-level iperf artifact not recovered from the archived project; no board in this release |
| Full deterministic integration regression | The historical cocotb regression was flaky (44 PASS / 23 FAIL, same-day PASS+FAIL) and the sim `sim_build` artifacts are excluded; regenerating requires the full Vivado project + cocotb stack |
| Post-route security behavior | No gate-level simulation exists; routed timing is not met |
| 10G | Not implemented (roadmap) |

## What was kept as evidence

The `docs/audits/` directory contains the original read-only audit reports
(publication-sanitized copies; technical conclusions unchanged). The
`docs/engineering_log/` directory contains the original development log and
debug records (sanitized paths only).

## Provenance of the E1/E2 experiments

E1/E2 were written for the audits in a temporary directory
(`<experiment-dir>`), with the **production RTL read-only** (byte-identical
DUTs). The experiment sources were reviewed for suitability and copied into
`tb/security_regressions/`; compiled binaries, waveforms, and logs were not
copied. Attribution: Le Sun, 2026 (BSD-2-Clause headers added).
