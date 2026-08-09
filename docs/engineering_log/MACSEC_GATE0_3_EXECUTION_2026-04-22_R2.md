# MACsec Gate0-3 Execution Report (R2)

Date: 2026-04-22

## Scope
Re-ran Gate0..Gate3 after TX underflow fix (inserted store-and-forward FIFO between `u_macsec_tx` and `eth_mac_10g`) and TB instrumentation updates.

## Gate0
Check file:
- `mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v`

Result:
- PASS
- `u_macsec_tx.enable(1'b1)` at line ~819
- `u_macsec_rx.enable(1'b1)` at line ~882

## Gate1
Commands:
- `timeout 1800 ./.venv_cocotb17/bin/python -m pytest -q corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/macsec_tx_wrapper/test_macsec_tx_header.py`
- `timeout 1800 ./.venv_cocotb17/bin/python -m pytest -q corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/macsec_loopback/test_macsec_loopback.py`

Result:
- PASS
- 2 passed
- 2 passed

## Gate2
Command:
- `MACSEC_REPO_ROOT=<workspace>/mqnic_gcm_codex-2 timeout 3600 ./.venv_cocotb17/bin/python -m pytest -q corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_ip.py`

Result:
- FAIL (full regression still not closed)
- Previous deterministic early failure (`single_pkt_host` underflow/truncated wire frame) is fixed.
- New failure point moved to long-run stage: `small_pkts_63` host receive timeout.
- Failure snapshot:
  - `tx_in=134, tx_out=133, rx_in=133, rx_out=133`
  - indicates one TX frame not completed/observed by timeout in that phase.

Notes:
- Smoke path now passes (`MACSEC_SMOKE_ONLY=1`): first packet + checksum path both work.
- Full Gate2 run is now much deeper than before (enters queue/rss/small-pkts stages).

## Gate3
Command:
- Vivado quick acceptance batch Tcl:
  - `open_project <workspace>/mqnic_gcm_codex-2/mqnic_gcm_codex.xpr`
  - `update_compile_order -fileset sources_1`
  - `close_project`

Result:
- PASS

## Current Summary
- Gate0: PASS
- Gate1: PASS
- Gate2: FAIL (late-stage timeout in full regression)
- Gate3: PASS
