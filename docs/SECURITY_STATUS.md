# Security Status

**Security status: NOT PRODUCTION READY**

This revision must not be represented as a standards-compliant or
production-secure MACsec implementation.

## Property table

| Security property | Status | Evidence |
| --- | --- | --- |
| AES-GCM algorithm core | Verified at HLS level | OpenSSL oracle (300 vectors), RTL cosim |
| Nonce uniqueness | **BLOCKER** | reset PN rollback (E2 behavioral), shared TX/RX key, non-unique SSCI |
| Auth before release | **BLOCKER** | behavioral E1: corrupt tag still releases plaintext |
| Replay protection | NOT IMPLEMENTED | RTL audit |
| SA lifecycle | NOT IMPLEMENTED | RTL audit |
| Key zeroization | GAP | plaintext key regs, constant key localparam |
| Frame context identity | GAP | no generation/SA/PN completion binding |
| Fail closed | GAP | only length<24B frames dropped; auth failures not dropped |
| Standard 802.1AE compliance | NOT IMPLEMENTED | custom IV/AAD/framing |

## Blockers (confirmed)

### B1 — Nonce uniqueness (BLOCKER)

- TX and RX share the same `MACSEC_AES_KEY`
  (`0x00112233445566778899AABBCCDDEEFF`) in `fpga_core.v`.
- **Reset rolls `tx_pn` back to `PN_INIT=1`** with the same key
  (`macsec_aes_encrypt.v`), confirmed behaviorally by experiment E2.
  Restart with the same key reuses the same `(key, IV)` nonce structure.
- SSCI base is fixed (`0x12345678` + port); no per-node uniqueness scheme.
- No PN wrap fail-close, no persistent PN.

### B2 — Authentication before release (BLOCKER)

- `macsec_rx_wrapper` outputs decrypted plaintext in `OUT_DEC` regardless of
  tag validity; top level sets `icv_check_enable=0`, `received_icv=0`.
- `macsec_tag_strip` only drops frames shorter than `MIN_FRAME_BYTES` (24);
  there is **no tag comparison branch** in the FSM.
- Confirmed behaviorally by experiment E1: a frame with a corrupted ICV tag
  is stripped and released as plaintext.

### B3 — Replay protection (NOT IMPLEMENTED)

- No lowest-acceptable-PN, no replay window, no duplicate/old/out-of-order
  handling, no wrap handling.

## Gaps

- **SA/key lifecycle** — no SA table, no active/retired/generation, no atomic
  key switch, no key zeroization.
- **Frame context identity** — completion events do not carry
  `{SA, AN, PN, generation}`.
- **Observability** — counters only; no per-event
  `{direction, frame_seq, SA, AN, PN, generation, error}` fingerprint.
- **Fail-closed** — crypto bypass is possible via the `enable` port; key/HLS
  failure paths do not fail closed.
- **Standard compliance** — the IV is `{SSCI(32), PN(32), 0x5C5C5C5C}`, AAD is
  `{80'h0, 16'h0001, SSCI(32)}`; this is a custom mock-MACsec format, not IEEE
  802.1AE.

## Evidence

Independent behavioral experiments E1 and E2 are reproduced under
`tb/security_regressions/` (Verilog, iverilog) and documented in
`docs/VERIFICATION_STATUS.md` and the audits in `docs/audits/`.

## What this means

This repository's current revision:

- **must not** be deployed as a production MACsec endpoint;
- **must not** be cited as an IEEE 802.1AE reference implementation;
- is a valid *research prototype* for studying FPGA AES-GCM integration,
  datapath performance, and the difference between a working loopback and a
  secure design.
