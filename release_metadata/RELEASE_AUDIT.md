# Release Audit

Summary of the release candidate, generated at preparation time
(2026-08-09). Re-run this audit (and regenerate `SHA256SUMS`) before any
actual publication.

## Contents

| Metric | Value |
| --- | --- |
| Total files in release candidate | 251 (250 hashed in `SHA256SUMS` + the manifest docs) |
| Manifest entries (included files, classified) | 234 |
| Original Le Sun files (ORIGINAL_LE_SUN + TEST_ORIGINAL + DOCUMENTATION_ORIGINAL) | 82 |
| Le Sun modified upstream files (CORUNDUM_MODIFIED + AMD_VITIS_MODIFIED) | 6 |
| Unmodified Corundum files | 132 |
| Unmodified AMD/Vitis files | 14 |
| Generated/vendor files excluded | ~934 (+ a 2375-file Python virtualenv; see below) |
| Unknown-provenance files | 0 included (policy: exclude) |
| Publish blockers (MUST FIX) | 7 (P1–P7, see `docs/PUBLISH_REVIEW_REQUIRED.md`) |

Breakdown of excluded content (by category):

| Category | Count |
| --- | --- |
| HLS generated IP (`ip/`, `hls_models/`) | 168 |
| Vivado generated output (`.gen`, `.cache`, `.runs`, `.hw`, `.sim`, `.ip_user_files`, `.Xil`) | 529 |
| Simulation artifacts (`sim_build`, pytest caches, `__pycache__`) | 164 |
| Aux test scaffolding (`lib_test_project`, `tmp_logs`) | 8 |
| Root build artifacts (`.bit`, `.dcp`, `.rpt`, `.xpr`, `.jou`, `.log`, `.str`, diff scratch) | ~59 |
| Python virtualenv (`.venv_cocotb17/`) | 2375 (environment, not source) |

## Checks performed

- **Production files modified**: 0 (baseline hash snapshot before vs after —
  see `docs/../release_metadata` note; the production tree was only read).
- **Git operations performed**: 0.
- **Attribution audit**: 171/171 files correct (see `ATTRIBUTION_AUDIT.md`).
- **Secret/privacy scan**: residual items resolved; public test key documented
  as non-secret (see `SECRET_SCAN.md`).
- **Symlink check**: no symlinks in the release candidate (all copies are
  real files).
- **Absolute path check**: release source copies are free of `<home>` paths
  (normalized); manifest `original_path` fields normalized to `<home>`.
- **Bitstream/cache check**: no `.bit`, `.dcp`, `.Xil`, Vivado cache content
  present in the release tree.

## Verified by the manifest

Every included file has a `release_path`, `original_path`, `classification`,
author/copyright, license, SPDX, modification flag, `include`, `reason`, and
SHA-256 pair in `SOURCE_MANIFEST.csv`/`.json`.

## Final status

**`RELEASE_CANDIDATE_REQUIRES_HUMAN_REVIEW`** — see
`docs/PUBLISH_REVIEW_REQUIRED.md`. Do not change this status until the
MUST-FIX items (P1–P7) are cleared and the re-scan/re-hash is redone.
