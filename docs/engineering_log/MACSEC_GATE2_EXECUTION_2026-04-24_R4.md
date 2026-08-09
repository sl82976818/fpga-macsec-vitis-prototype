# MACsec Gate2 Execution Report (2026-04-24, R4)

## 1) Root Cause (from real-time repro)

Gate2 full "empty <failure/>" was **not** a random cocotb artifact.
It was a deterministic strict-final assertion mismatch in `run_test_nic`:

- File: `corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_sfp.py`
- Path: `_check_stage("final", strict=require_final_strict)`
- Old strict RX check:
  - `assert rx_in == rx_out + rx_pause_frames`

Real-time `lfc-only` debug proved this is wrong for current counters:

- `rx_out` monitor already counts forwarded pause control frames.
- So adding `rx_pause_frames` again double-counts pause traffic.
- Observed failure signature:
  - `AssertionError: final: strict mismatch rx_in=7 rx_out=7 rx_pause_frames=1`
  - i.e. `7 == 7 + 1` impossible.

## 2) Fix Applied

Updated strict RX invariant to use aligned counter domain:

- File changed:
  - `corundum-master/fpga/mqnic/Nexus_K3P_S/fpga_25g/tb/fpga_core/test_fpga_core_macsec_sfp.py`
- Change:
  - from `rx_in == rx_out + rx_pause_frames`
  - to   `rx_in == rx_out`
- Added short comment explaining why (`rx_out` already includes pause control frames).

## 3) Verification Runs

### 3.1 Focused repro before fix (lfc-only strict)

- Command profile:
  - `MACSEC_RUN_LFC=1` with other stages off, `MACSEC_LFC_PKT_COUNT=4`, `MACSEC_REQUIRE_FINAL_STRICT=1`, `MACSEC_LIVE_DEBUG=1`
- Result: **FAIL** (expected for repro)
- Key evidence:
  - final counters: `tx_in=6 tx_out=6 rx_in=7 rx_out=7`
  - assertion expected `rx_in == rx_out + rx_pause_frames`
  - `rx_pause_frames=1` -> false negative.

### 3.2 Focused validation after fix (lfc-only strict)

- Same profile as 3.1
- Result: **PASS** (`EXIT:0`)

### 3.3 Full Gate2 after fix (R2-equivalent full flow)

- Command profile:
  - `test_fpga_core_macsec_ip.py::test_fpga_core_macsec_ip`
  - `MACSEC_STAGE_PRINT=1`
  - `MACSEC_DEBUG_LOG_FILE=/tmp/gate2_full_dbg_after_fix_final.log`
- Result: **PASS** (`EXIT:0`)
- Stage progression reached and completed:
  - `arp_mix`, `queue_map`, `rss`, `steady_flow`, `small_pkts`, `large_pkts`, `lfc`, `final`
- Final checkpoint from debug log:
  - `final tx_in=294 tx_out=294 rx_in=295 rx_out=295 lag_tx=0 lag_rx=0`

## 4) Artifacts

- Full run debug log:
  - `/tmp/gate2_full_dbg_after_fix_final.log`
- Full run stdout/stderr capture:
  - `/tmp/gate2_full_run_after_fix_final.log`
- Focused lfc debug log (after fix):
  - `/tmp/gate2_lfc_only_dbg_fix.log`
- Focused lfc run capture (after fix):
  - `/tmp/gate2_lfc_only_run_fix.log`

## 5) Conclusion

- Gate2 now completes end-to-end with strict final invariants enabled.
- This closes the previous Gate2 blocker that manifested as empty junit failure.
