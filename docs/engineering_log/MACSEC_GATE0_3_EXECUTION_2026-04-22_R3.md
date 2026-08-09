# MACsec Gate0-3 Execution Report (R3)

Date: 2026-04-22

## Scope
Continue from R2/R3 fixes, complete pre-board equivalent simulation and quick project integrity checks.

## Gate1
Commands:
- `MACSEC_REPO_ROOT=<workspace>/mqnic_gcm_codex-2 timeout 1800 ./.venv_cocotb17/bin/python -m pytest -q corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/macsec_tx_wrapper/test_macsec_tx_header.py -s`
- `MACSEC_REPO_ROOT=<workspace>/mqnic_gcm_codex-2 timeout 1800 ./.venv_cocotb17/bin/python -m pytest -q corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/macsec_loopback/test_macsec_loopback.py -s`

Result:
- PASS
- `test_macsec_tx_header.py`: `2 passed in 0.88s`
- `test_macsec_loopback.py`: `2 passed in 1.88s`

## Gate2
Command:
- `MACSEC_REPO_ROOT=<workspace>/mqnic_gcm_codex-2 REPO_ROOT=<workspace>/mqnic_gcm_codex-2 MACSEC_LIVE_DEBUG=1 MACSEC_TB_LOG_LEVEL=INFO MACSEC_COCOTB_LOG_LEVEL=INFO MACSEC_CHECKPOINT_LAG_MAX=256 timeout 10800 corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/run_macsec_gate2_preboard.sh`

Result:
- PASS
- Step 1/3 smoke: `1 passed in 52.35s`
- Step 2/3 small_pkts+rss: `1 passed in 168.72s`
- Step 3/3 full certification: `1 passed in 326.31s`
- Script final line: `[Gate2] PASS`

## Gate3
Command:
- Vivado quick check (batch Tcl):
  - `open_project mqnic_gcm_codex.xpr`
  - `update_compile_order -fileset sources_1`
  - `close_project`

Result:
- PASS

## Current Summary
- Gate1: PASS
- Gate2: PASS
- Gate3: PASS

## Logs
- `/tmp/gate1_tx_header.log`
- `/tmp/gate1_loopback.log`
- `/tmp/gate2_preboard_rerun.log`
- `/tmp/gate3_quick_check.log`
