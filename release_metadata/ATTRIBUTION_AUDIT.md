# Attribution Audit

Automated verification that the release copies carry the correct attribution
per the classification in `SOURCE_MANIFEST.csv`. Run: 2026-08-09.

## Rules checked

| Rule | Files | Result |
| --- | --- | --- |
| ORIGINAL_LE_SUN / TEST_ORIGINAL source files carry `SPDX-License-Identifier: BSD-2-Clause` **and** `Copyright (c) 2026 Le Sun` | `src/macsec/*`, `tb/security_regressions/*`, `tb/cocotb/xpm_*_sim.v`, `tb/cocotb/hls_*_model.v`, `tb/tb_fpga_core_integration.v`, `scripts/*` | **PASS** |
| CORUNDUM_MODIFIED files retain upstream copyright **and** add "Modified by Le Sun, 2026"; no standalone "Author: Le Sun" overriding upstream | `src/fpga/fpga_core.v`, `src/fpga/fpga_k35.v`, `constraints/fpga_k35.xdc`, `tb/cocotb/test_fpga_core_macsec_sfp.py` | **PASS** |
| AMD_VITIS_MODIFIED files retain upstream Apache-2.0 header **and** add modification note | `hls/src/project/*/settings.tcl` | **PASS** (after rework) |
| UPSTREAM files (Corundum/Vitis) must **not** contain "Copyright (c) 2026 Le Sun" or an "Author: Le Sun" override | all `src/fpga/common/*`, `src/fpga/lib/*`, `src/fpga/sync_signal.v`, `board_K35/*`, `constraints/boot.xdc`, `tb/cocotb/mqnic.py`, `hls/src/project/aes128{enc,dec}/*` | **PASS** |

## Detail

- **171 files** checked: 0 attribution failures.
- Corundum files keep `SPDX-License-Identifier: BSD-2-Clause-Views` headers
  intact; modification notes were inserted *after* the upstream header block
  without altering it.
- Vitis example sources retain the `Copyright 2019 Xilinx, Inc.` Apache-2.0
  headers untouched.
- `debounce_switch.v` retains the Alex Forencich MIT header.
- No upstream file gained an "Author: Le Sun" attribution; no original file
  lacks the BSD-2-Clause/Le Sun header.

## Caveats

- Automated header checks confirm *presence* of the expected markers, not the
  legal sufficiency of the attribution. Legal/ownership review remains
  mandatory (`docs/PUBLISH_REVIEW_REQUIRED.md`).
- `src/fpga/board_K35/defines.v` is an empty board defines file; no header was
  added (nothing to attribute).
