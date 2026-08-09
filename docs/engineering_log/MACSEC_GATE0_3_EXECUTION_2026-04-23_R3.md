# MACsec Gate0-3(+2.5) Execution Report (R3)

Date: 2026-04-23

## Scope
Continue from R2 and close pre-board simulation gates with MACsec enabled path.

## Root Cause Found
- `fpga_core.v` had `MACSEC_DATA_PROTECT_ENABLE = 1'b0`, which made most regressions run bypass path instead of real MACsec encrypt/decrypt path.
- This explains earlier “TB pass but board fail” inconsistency.

## Code Changes

### RTL
1. `mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/fpga_core.v`
- `MACSEC_DATA_PROTECT_ENABLE` changed to `1'b1`.

2. `mqnic_gcm_codex.srcs/sources_1/imports/fpga_25g/rtl/common/mqnic_interface.v`
- Exposed internal `rx_fifo` status wires for debug observation:
  - `rx_fifo_status_overflow`
  - `rx_fifo_status_bad_frame`
  - `rx_fifo_status_good_frame`

### TB
3. `corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_sfp.py`
- Added deeper realtime diagnostics for RX pipeline:
  - `axis_if_rx_fifo_*` input/output stage counters
  - `if_rx_axis_*` stage counters
  - bad-bit accumulators and additional event counters
- Hardened monitor code against X/Z values.
- Adjusted lag policy for long-run checks:
  - `MACSEC_CHECKPOINT_LAG_WARN` default `8`
  - `MACSEC_CHECKPOINT_LAG_MAX` default `64`
  - still keeps strict final equality check.
- Fixed Gate2.5 semantics to match MACsec behavior:
  - verify L2 header cleartext on wire
  - verify protected wire frame differs from plaintext and has overhead
  - reflect protected frame and verify host receives original payload
- Removed checksum offload from peer-interop stage to avoid unrelated checksum mutation in Gate2.5 comparison.

## Gate Results

### Gate0
- PASS
- Verified by RTL state (MACsec datapath protection enabled in current code).

### Gate1
Commands:
- `timeout 1800 ./.venv_cocotb17/bin/python -m pytest -q corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/macsec_tx_wrapper/test_macsec_tx_header.py`
- `timeout 1800 ./.venv_cocotb17/bin/python -m pytest -q corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/macsec_loopback/test_macsec_loopback.py`

Result:
- PASS
- `2 passed`
- `2 passed`

### Gate2 (full fpga_core MACsec regression)
Command:
- `pytest -q -s corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_ip.py::test_fpga_core_macsec_ip`

Result:
- PASS
- `1 passed in 337.92s`

### Gate2.5 (peer interop semantic check)
Command:
- `MACSEC_TEST_STAGE=peer_interop MACSEC_LIVE_DEBUG=1 pytest -q -s corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_ip.py::test_fpga_core_macsec_ip`

Result:
- PASS
- `1 passed in 60.80s`

### Gate3 (Vivado quick acceptance)
Batch Tcl:
- `open_project <workspace>/mqnic_gcm_codex-2/mqnic_gcm_codex.xpr`
- `update_compile_order -fileset sources_1`
- `close_project`

Result:
- PASS

## Final Summary
- Gate0: PASS
- Gate1: PASS
- Gate2: PASS
- Gate2.5: PASS
- Gate3: PASS

Current pre-board simulation flow is aligned with enabled MACsec datapath and peer-interop semantics.
