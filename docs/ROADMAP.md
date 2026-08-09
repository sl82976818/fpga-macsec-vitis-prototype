# Roadmap

The roadmap below is a **plan, not a claim of completion**. Nothing past
`v0.2-audited` exists in this release.

```
v0.1  legacy functional ~2.7G prototype      (historical, archived)
v0.2  audited research release                (this release candidate)
v0.3  security baseline
v0.4  crypto refactor (cached-SA)
v0.5  datapath pipeline (frame slots)
v1.0  candidate (10G + security closure)
```

## v0.1 — legacy functional ~2.7G prototype (historical)

Archived functional datapath with ~2.7/2.75 Gbps label. See
`docs/PROJECT_HISTORY.md`.

## v0.2 — audited research release (current)

This release candidate: full provenance, performance and security audits,
documented blockers, patches for modified upstream files, reproducible
security experiments. **Done.**

## v0.3 — security baseline

Security first. Minimum scope before any 10G work:

- **independent integration oracle** (external MACsec frames compared against
  an independent model);
- **RX auth-before-release hard gate** (0-beat plaintext release on tag
  mismatch);
- **fail-closed** behavior for crypto/key/configuration failures;
- **unique nonce contract** (separate TX/RX direction keys and/or unique SSCI;
  documented, enforced);
- **persistent / non-rollback PN** (PN must not roll back on reset; wrap
  fail-close);
- **replay window** (lowest acceptable PN, duplicate/old/out-of-order);
- **SA/key lifecycle** (SA table, active/retired, atomic key switch,
  zeroization);
- **generation/context ID** bound to completion events.

## v0.4 — crypto refactor (cached-SA)

- cache round keys (`updateKey` once per SA);
- cache `H`;
- cache GHASH precomputation (`GF128_prepare` once per SA);
- atomic SA banks to avoid key/H/Y mismatch;
- per-frame crypto setup tax: 186 → ~24 cycles.

## v0.5 — datapath pipeline

- multiple frame slots (2+ frames in flight);
- capture / crypto / release overlap;
- ordered commit;
- zero plaintext on auth failure (enforced at release);

## v1.0 — candidate (only if ALL hold)

```text
10G sustained (at measured line rate, incl. headers/IFG)
timing met (WNS >= 0, routed)
independent oracle (integration level)
security closure (v0.3 items verified)
replay protection verified
nonce uniqueness verified (incl. reset/fault injection)
post-synthesis verification (gate-level)
board verification (clean, with preserved artifacts)
```

## Required before v1.0

The audits identify these prerequisites explicitly
(`docs/audits/VITIS_MACSEC_SECURITY_CLOSURE_AUDIT_20260806_210353.md` §13):

1. RX auth gate (`icv_check_enable=1` + actual `received_icv` compare).
2. TX/RX split keys (or unique SSCI); PN not rolled back by reset; wrap
   fail-close.
3. Replay window.
4. SA lifecycle + zeroization + generation.
5. Completion/event binding `{SA, AN, PN, generation}`.
6. Independent oracle + negative matrix + backpressure/reset/post-synth.
7. Fix routed timing (WNS ≤ 0) before gate-level security work.
