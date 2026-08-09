# Known Limitations

A consolidated list of the technical limitations of the archived revision.
These are **acceptable to publish** because they are disclosed; they do not
block publication (blockers are legal/provenance issues, not technical
deficits — see `docs/PUBLISH_REVIEW_REQUIRED.md`).

## Functional / performance

- Datapath is **not 10G**. Historical baseline ~2.7/2.75 Gbps (label);
  modeled ~2.60 Gbps for 1518-byte frames; 10G is a roadmap target.
- Single-frame-in-flight store-and-forward wrapper serializes
  capture→crypto→release.
- Per-frame crypto setup tax ~186 cycles (original) / ~24 cycles (cached-SA
  model).
- Routed timing is **not met** (WNS ≈ −0.206 ns) in the archived run.
- Custom frame tail format (`payload + PN + TAG`), not an interoperable
  standard format.

## Security (see `docs/SECURITY_STATUS.md`)

- Auth-before-release violation (blocker, behaviorally confirmed E1).
- Reset-induced PN rollback → nonce-reuse risk (blocker, behaviorally
  confirmed E2).
- Replay protection not implemented.
- SA/key lifecycle, key zeroization, generation/context binding not
  implemented.
- Single shared TX/RX key; fixed SSCI; no per-node uniqueness scheme.
- Not IEEE 802.1AE compliant (custom IV/AAD).

## Verification (see `docs/VERIFICATION_STATUS.md`)

- Integration-level oracle not independent.
- Historical cocotb regression flaky (44 PASS / 23 FAIL; same-day PASS+FAIL).
- Production parameters not tested.
- Negative auth / replay / reset-matrix / backpressure / post-synthesis tests
  absent.
- No board-level iperf artifact recovered for the 2.7G label.

## Reproducibility (see `docs/BUILD.md`, `docs/REPRODUCIBILITY.md`)

- `CLEAN_REBUILD_NOT_YET_PROVEN` — no proven from-scratch rebuild.
- Corundum baseline commit unknown (`UPSTREAM_BASELINE_UNKNOWN`).
- Generated IP/tool artifacts not redistributed.

## Scope statement

These limitations are intentionally public. They are the reason this
repository is labeled **research prototype** and **not production-ready**.
