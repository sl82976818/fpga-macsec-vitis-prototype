# Security Regressions (E1 / E2)

Independent, read-only behavioral experiments that confirmed the two security
blockers. All DUTs are the **production RTL** in `src/macsec/` (byte-identical
to the archived project); only testbench code is new. Written by Le Sun,
2026 (BSD-2-Clause).

## E1 — Authentication before release (BLOCKER)

- **DUT**: `src/macsec/macsec_tag_strip.v` (+ XPM FIFO behavioral model
  `tb/cocotb/xpm_fifo_sync_sim.v`).
- **Result**: a frame whose trailing 16-byte ICV is corrupted is still
  stripped of tag/PN and **released as plaintext** (FSM never enters
  `ST_DROP`; the only drop path is `frame_byte_count < MIN_FRAME_BYTES`).
- **Files**: `tb_tag_strip.v` (main, A/B comparison), `tb2.v`–`tb7.v`
  (variants), `exp1_E1_tagstrip.cc` (result artifact as comments).
- **Conclusion**: `AUTHENTICATION_BEFORE_RELEASE_VIOLATION`.

## E2 — Reset rolls PN back (nonce reuse risk, BLOCKER)

- **DUT**: `src/macsec/macsec_aes_encrypt.v` (production wrapper) with a
  minimal behavioral stub of the HLS IP (`e2_stub.v`, pulses `ap_done`).
- **Result**: after frame 1 advances `tx_pn` to 6, asserting `hls_rst` sets
  `tx_pn=1` (`PN_INIT`); frame 2 restarts from `tx_pn=1` with the same key.
  The `(key, IV)` nonce structure `{SSCI, PN, 0x5C5C5C5C}` can therefore
  repeat across resets.
- **Files**: `tb_e2.v` (main), `e2_stub.v`.
- **Conclusion**: `NONCE_REUSE_STRUCTURAL_RISK`, behaviorally confirmed.

## Running

```
# E1
iverilog -g2012 -o /tmp/e1 tb_tag_strip.v \
  ../../src/macsec/macsec_tag_strip.v \
  ../../tb/cocotb/xpm_fifo_sync_sim.v \
  && vvp /tmp/e1

# E2
iverilog -g2012 -o /tmp/e2 tb_e2.v e2_stub.v \
  ../../src/macsec/macsec_aes_encrypt.v \
  && vvp /tmp/e2
```

(The exact wrapper port widths are resolved via `src/macsec/macsec_types.vh`.)

## What was not copied

Compiled binaries (`run`, `run2`, `run3`, `tb4`–`tb7`, `e2run`) and the
waveform `tb5.vcd` from the original experiment directory were **not**
included. See `docs/REPRODUCIBILITY.md` and
`release_metadata/FILES_EXCLUDED.md`.
