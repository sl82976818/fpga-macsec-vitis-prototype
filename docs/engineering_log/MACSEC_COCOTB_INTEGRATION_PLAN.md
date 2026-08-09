# MACsec Cocotb Integration Plan

## Goal
Integrate HLS MACsec encrypt/decrypt into the original cocotb flow and keep full behavioral compatibility with the existing project regressions.

## Current Status
- `macsec_tag_append.v` and `macsec_tag_strip.v` roundtrip functional test is passing.
- Full MACsec cocotb run can pass only when LFC pause-frame subtest is force-skipped.
- `COUNT_125US` simulation acceleration is already applied in cocotb to avoid very slow link/watchdog timing.

## Execution Strategy
1. Stabilize a single main regression entry
- Keep `test_fpga_core_macsec_ip.py` as the active integration runner, but remove temporary forced LFC skip.
- Keep `COUNT_125US` acceleration enabled.
- Keep local tag codec test as quick gate for tag append/strip logic.

2. Re-enable original LFC behavior and debug in-place
- Re-enable LFC/PFC features in integration regression.
- Add precise timeout diagnostics in the LFC section (frame counters and context) to identify the exact stall point.
- Confirm whether control/pause frames are incorrectly transformed or dropped across MACsec wrappers.

3. Fix compatibility at RTL boundary
- Ensure MAC control frames are handled compatibly with the original design expectation.
- Prefer minimal, explicit datapath handling in wrappers (no broad behavioral changes in core NIC logic).

4. Converge to original cocotb compatibility
- Run the complete regression sequence used by the original test flow without skip flags.
- Verify that baseline traffic tests, RSS, checksum, and LFC pause sequence all pass with MACsec enabled.

## Validation Gates
- Gate A: `tb_macsec_tag_codec` must pass.
- Gate B: Full `test_fpga_core_macsec_ip.py` must pass with no forced LFC skip.
- Gate C: Original cocotb-compatible sequence (including LFC pause test) must pass with MACsec integration enabled.

## Progress (2026-04-21)
- Done: Plan saved in repo.
- Done: Removed forced LFC/PFC disable and removed forced `DISABLE_LFC_TEST=1` from MACsec integration regression.
- Done: Added targeted LFC timeout diagnostics in cocotb (`LFC recv timeout`, MACsec frame counters, queue state).
- Done: Re-ran full regression with LFC enabled and reproduced failure deterministically:
  - failure point: LFC pause RX phase, first packet timeout
  - marker: `rx_in = tx_in + 1` while `rx_out = tx_out`, consistent with pause frame entering MACsec RX path and not emerging as payload
- In progress: Implement MAC control frame compatibility handling at MACsec wrapper boundary.

## Progress Update (2026-04-21, later)
- Done: Fixed core↔MAC LFC/PFC integration chain in `fpga_core.v` and aligned MACsec wrapper handshake behavior.
- Done: Removed experimental RX bypass/input-FIFO workaround path from `macsec_rx_wrapper.v`, kept only minimal validated fixes.
- Done: Established and verified the **only valid regression command** for this integration:
  - `timeout 1800 ./.venv_cocotb17/bin/python -m pytest -q corundum-master/fpga/mqnic/Nexus_K3P_Q/fpga_25g/tb/fpga_core/test_fpga_core_macsec_ip.py`
- Done: 3 consecutive stability runs passed with no skip flags:
  - run1: `1 passed in 363.09s (0:06:03)`
  - run2: `1 passed in 351.57s (0:05:51)`
  - run3: `1 passed in 362.38s (0:06:02)`
- Policy: Runs that fail before real simulation due to sandbox socket permissions (`Scapy` / `Operation not permitted`) are **invalid for functional judgment** and must not be used as regression conclusions.

## Non-Goals
- No edits to generated Vivado run/cache artifacts.
- No broad refactor of unrelated RTL blocks.
