# MACsec Gate2 Small-Pkts Convergence Plan (R3)

Date: 2026-04-22

## Objective
Stabilize and localize the late-stage Gate2 failure currently observed at `small_pkts_63` by running a focused `small_pkts` phase with deterministic diagnostics.

## New Test Controls (implemented)
File:
- `corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_sfp.py`

Environment knobs:
- `MACSEC_TEST_STAGE=full|small_pkts`
- `MACSEC_SMALL_PKTS_PRE_STAGE=none|queue_map|rss`
- `MACSEC_SMALL_PKTS_COUNT=<N>`
- `MACSEC_SMALL_PKTS_ROUNDS=<N>`
- `MACSEC_LATE_GRACE_US=<N>`
- `MACSEC_ALLOW_LATE=0|1`

Behavior:
- `small_pkts` mode can skip later unrelated stages (`large_pkts`, `lfc`) and optionally keep preconditioning (`queue_map`/`rss`).
- On host timeout, optional `late grace` window checks whether the packet arrives late (timing issue) vs never arrives (drop).

## Execution Order
1. Fast sanity for new stage controls
- `MACSEC_REPO_ROOT=<workspace>/mqnic_gcm_codex-2 MACSEC_SMOKE_ONLY=1 timeout 1800 ./.venv_cocotb17/bin/python -m pytest -q corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_ip.py`

2. Focused reproduction with original preconditioning
- `MACSEC_REPO_ROOT=<workspace>/mqnic_gcm_codex-2 MACSEC_TEST_STAGE=small_pkts MACSEC_SMALL_PKTS_PRE_STAGE=rss MACSEC_SMALL_PKTS_COUNT=64 MACSEC_SMALL_PKTS_ROUNDS=3 MACSEC_LATE_GRACE_US=2000 timeout 3600 ./.venv_cocotb17/bin/python -m pytest -q corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_ip.py`

3. Differential check for pre-stage sensitivity
- same as step 2, but `MACSEC_SMALL_PKTS_PRE_STAGE=none`

## Decision Rules
- If timeout + `Late host packet` appears: treat as completion latency/jitter issue and tune dequeue/timing path.
- If timeout and no late packet in grace window: treat as true drop and focus on RX completion accounting/order path.
- If `none` pre-stage passes but `rss` pre-stage fails: prioritize queue map/RSS interaction around small packet burst.
