# Verification Status

**Verification is not "everything passes".** This document separates strong
evidence from weak or missing evidence, following the read-only audit
(`docs/audits/VITIS_MACSEC_SIMULATION_COVERAGE_AUDIT_20260806_210353.md`).

## Strong evidence

- **HLS C-sim**: 300 AES-GCM vectors compared against **OpenSSL** goldens —
  this is the only truly independent oracle in the whole verification story.
- **HLS RTL cosim**: passes (Verilog) against the same goldens.
- These verify the **mathematical core** of the AES-GCM IP only.

## Weak / missing evidence

- **Integrated MACsec oracle: missing.** The integration-level testbench only
  checks loopback self-consistency (TX encrypt → RX decrypt, same key, same
  core). It never compares ciphertext/tag/auth decisions against an
  independent model. Classified
  `VITIS_MACSEC_TEST_ORACLE_NOT_INDEPENDENT`.
- **Historical full regression is flaky.** The saved `sim_build` corpus
  (04-24..04-30) shows **44 PASS / 23 FAIL**, with PASS and FAIL coexisting on
  the same day (04-28: 5 FAIL + 4 PASS) for the same DUT and TB.
  `lastfailed=true` persists. The integration regression is
  **non-deterministic** and cannot be trusted as a green gate.
- **Production parameters not tested.** The TB uses
  `IF_COUNT=2, EQN_WIDTH=6, TX_QUEUE_INDEX_WIDTH=13` while the production
  `fpga_k35` defaults are `IF_COUNT=1, EQN_WIDTH=5, TX_QUEUE_INDEX_WIDTH=11`.
- **Negative auth tests: absent.** No corrupted-tag, corrupted-ciphertext,
  wrong-AAD, wrong-IV, wrong-key tests. (And RX does not authenticate anyway.)
- **Replay tests: absent.**
- **Reset matrix: absent.** Only initial reset; no mid-frame, warm,
  crypto-only, wrapper-only reset; reset-PN behavior is a known GAP.
- **Backpressure tests: absent.** No random tvalid/tready, no FIFO boundary
  tests, no long-stall/resume.
- **Post-synthesis verification: absent.** No post-synth / post-route / SDF
  simulation. Routed timing is **not met** (WNS ≈ −0.206 ns), so
  `POST_ROUTE_SECURITY_BEHAVIOR_UNPROVEN`.

## The honest headline

```
HLS AES-GCM verification != complete MACsec verification
```

The core's math is verified against an independent oracle. The wrapper's
IV/AAD assembly, the tag handling, the auth decision, the reset behavior, and
the production configuration are **not** independently verified.

## Coverage matrix

See `docs/audits/VITIS_MACSEC_SIMULATION_COVERAGE_MATRIX_20260806_210353.csv`
for the itemized matrix.

## Independent security experiments (done during the audits)

Two focused, read-only behavioral experiments provide positive evidence for
the two security blockers (source in `tb/security_regressions/`):

- **E1** (`tb_tag_strip.v`, production `macsec_tag_strip.v`): a corrupted-ICV
  frame is released as plaintext — auth-before-release violation confirmed.
- **E2** (`tb_e2.v` + `e2_stub.v`, production `macsec_aes_encrypt.v`): reset
  rolls `tx_pn` back to `PN_INIT=1` with the same key — nonce-reuse risk
  confirmed.

## What would make verification trustworthy

1. Independent integration-level oracle (Python/PyCryptodome/OpenSSL/NIST) on
   externally constructed MACsec frames.
2. Negative auth matrix (tag/cipher/AAD/IV/key errors → drop).
3. Deterministic regression (fix the flakiness before trusting green runs).
4. Production-parameter equivalence.
5. Reset matrix including PN/IV/H invalidation.
6. Backpressure / random handshake tests.
7. Post-synthesis (gate-level) simulation after fixing routed timing.
