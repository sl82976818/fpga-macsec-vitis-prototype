# Changelog

All notable changes are documented as engineering records. See
`docs/engineering_log/CODEX_CHANGELOG.md` for the detailed per-iteration
history of the archived development process.

## [0.2-audited] - 2026-08-09 (release candidate)

Release-candidate packaging of the archived prototype after read-only
performance and security audits:

- Performance audit (`docs/audits/`) reproduced ~2.60 Gbps for 1518-byte
  frames from the actual serialized architecture (matching the historical
  ~2.7/2.75 Gbps label) and localized the bottleneck to the single-frame
  store-and-forward wrapper plus per-frame crypto setup tax.
- Security audit confirmed two behaviorally reproduced blockers:
  auth-before-release violation and reset-induced nonce-reuse risk, plus
  missing replay protection and SA lifecycle.
- Full provenance audit of the source tree with a source manifest, patches for
  modified Corundum files, and explicit separation of original, modified,
  upstream, and generated content.
- No production files were modified; generated tool artifacts are excluded.

## [0.1-functional-2.7g] - 2026-04 (historical, archived)

Functional MACsec-protected datapath prototype on Corundum + Vitis Security
Library AES-128-GCM with an observed ~2.7/2.75 Gbps performance baseline and
an end-to-end frame sweep from 64 to 1520 bytes passing in project simulation.
Archived with the performance wall unresolved at the time.

## Version tagging note

Recommended future tags: `v0.1-functional-2.7g`, `v0.2-audited`,
`v0.3-security-baseline`, `v0.4-cached-sa`, `v0.5-pipelined-10g`,
`v1.0-security-closed`. See `docs/ROADMAP.md`. No git tags are created by the
release-preparation process.
