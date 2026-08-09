# License Audit

## Statement

This release candidate uses a **multi-license** scheme:

- **Original Le Sun code** (confirmed by the provenance audit): **BSD-2-Clause**.
  This covers `src/macsec/`, the project scripts, the engineering log/audit
  records, and the E1/E2 testbenches.
- **Corundum** (upstream and modified): **BSD-2-Clause-Views** (`SPDX
  BSD-2-Clause-Views`); modified files retain the Regents' copyright and add a
  "Modified by Le Sun, 2026" note.
- **AMD/Xilinx Vitis Libraries**: **Apache-2.0** (vendored example sources
  unmodified; headers retained).
- **Alex Forencich** board modules (`debounce_switch.v`, some `.tcl`): MIT
  per file headers.
- **AMD/Xilinx tool-generated content**: **not redistributed**.

`LICENSE` states: *"Unless otherwise noted, original files authored for this
project by Le Sun are licensed under BSD-2-Clause. Third-party and derivative
files retain their respective upstream licenses."*

## License texts provided

| File | License | Source |
| --- | --- | --- |
| `LICENSES/BSD-2-Clause.txt` | BSD-2-Clause | standard SPDX text |
| `LICENSES/Apache-2.0.txt` | Apache-2.0 | extracted from Vitis Libraries `security/LICENSE.txt` (Apache portion) |
| `LICENSES/upstream/Corundum-LICENSE.txt` | BSD-2-Clause-Views | fetched from the Corundum upstream repository (exact text preserved) |
| `LICENSES/upstream/Vitis_Libraries-LICENSE.txt` | Apache-2.0 (+ BSD component note) | verbatim copy of Vitis Libraries 2022.1 `security/LICENSE.txt` |

## Per-file verification performed

1. `grep` for SPDX headers across the release tree to confirm each source file
   carries an SPDX expression matching its classification.
2. Upstream AMD/Vitis files: confirmed the Xilinx Apache-2.0 header is present
   and unmodified (byte-identical to upstream).
3. Corundum files: confirmed `SPDX-License-Identifier: BSD-2-Clause-Views`
   headers are intact in the copies.
4. Le Sun original files: `SPDX-License-Identifier: BSD-2-Clause` +
   `Copyright (c) 2026 Le Sun` added (and verified by
   `release_metadata/ATTRIBUTION_AUDIT.md`).

## Caveats / review items

- The **default BSD-2-Clause for Le Sun original work is an assertion by the
  release preparation process**, not a legal grant. The author must confirm
  ownership/employability rights (see `docs/PUBLISH_REVIEW_REQUIRED.md`,
  item P3).
- The Corundum bundled subset's **upstream baseline commit is unknown**
  (`UPSTREAM_BASELINE_UNKNOWN`); the `BSD-2-Clause-Views` text is correct for
  the Corundum project regardless of the specific commit, but the *patch
  baseline* needs recovery before public release.
- `hls/src/project/*/settings.tcl` is project-local config; license for it is
  asserted as BSD-2-Clause (Le Sun project file) — confirm before publish.
- No NOTICE files were invented for upstream projects; the root `NOTICE` only
  states factual attribution (Corundum, Vitis Libraries).
