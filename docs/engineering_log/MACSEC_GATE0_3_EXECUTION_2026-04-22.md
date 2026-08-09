# MACsec Gate0-3 Execution Report

Date: 2026-04-22

## Scope
Executed pre-board workflow Gate0 to Gate3 on current workspace state.

## Gate 0: RTL State Check

Check:
- `mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v:813`
- `mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v:834`

Result:
- PASS
- Both MACsec wrapper enables are `1'b1`.

## Gate 1: MACsec Unit-Level Cocotb

Commands:
- `timeout 1800 ./.venv_cocotb17/bin/python -m pytest -q corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/macsec_tx_wrapper/test_macsec_tx_header.py`
- `timeout 1800 ./.venv_cocotb17/bin/python -m pytest -q corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/macsec_loopback/test_macsec_loopback.py`

Result:
- PASS
- `test_macsec_tx_header.py`: `2 passed`
- `test_macsec_loopback.py`: `2 passed`

## Gate 2: Full fpga_core Cocotb

### Added/updated files
- `corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_ip.py`
  - adapted to this repo paths: `mqnic_gcm_codex.srcs`, `mqnic_gcm_codex.gen`, `imports/rtl`
  - uses `MACSEC_REPO_ROOT`/cwd for repo root resolution (avoid symlink resolve mismatch)
- `corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_sfp.py`
  - added MACsec frame monitors: `tx_in`, `tx_out`, `rx_in`, `rx_out`
  - added DA/SA preservation check on TX wire frame for checksum testcase
  - added end-of-test MACsec counter invariants
  - added SFP signal naming compatibility (`sfp_0`/`sfp0`, `sfp_1`/`sfp1`)
  - made optional sideband signals conditional (`npres`, `los`, `sma_in`, i2c, flash)
- copied XPM models required by MACsec path:
  - `xpm_fifo_async_sim.v`
  - `xpm_fifo_sync_sim.v`

### Command
- `MACSEC_REPO_ROOT=<workspace>/mqnic_gcm_codex-2 timeout 3600 ./.venv_cocotb17/bin/python -m pytest -q corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_ip.py`

### Result
- FAIL (not yet converged)
- Test reaches cocotb runtime, but simulation is extremely slow and does not complete in practical time.
- Latest artifact:
  - `corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/sim_build/test_fpga_core_macsec_ip_109551/25pugqqm_results.xml`
  - testcase `run_test_nic` failed after about `568s` real time at only `1,428,236 ns` sim time.

Interpretation:
- Gate2 still blocked; not board-ready by the Gate2 criterion.

## Gate 3: Vivado Build Check (quick acceptance)

Command:
- batch Tcl quick check:
  - `open_project <workspace>/mqnic_gcm_codex-2/mqnic_gcm_codex.xpr`
  - `update_compile_order -fileset sources_1`
  - `close_project`

Result:
- PASS
- Vivado project opens and source compile order update succeeds.

## Current Gate Summary
- Gate0: PASS
- Gate1: PASS
- Gate2: FAIL (runtime convergence/blocking)
- Gate3: PASS (quick project acceptance check)

## Recommendation
Do not proceed to MACsec-enabled board validation yet. Gate2 needs one more debug round focused on reducing sim runtime and finding where `run_test_nic` stalls in the MACsec-enabled full-core flow.
