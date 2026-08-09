# Third Party Notices

This release bundles or references the following third-party projects. The
information below is derived from the local source headers and upstream
metadata present at release-preparation time (2026-08-09). Where the local
copy could not be matched to a pristine upstream baseline, the entry is marked
for manual review.

## Corundum FPGA NIC

| Field | Value |
| --- | --- |
| Project | Corundum (FPGA NIC framework) |
| Copyright owner | Copyright (c) 2019-2023 The Regents of the University of California; older files Copyright (c) 2019-2023 Alex Forencich |
| License | BSD 2-Clause with "views" attribution clause (`BSD-2-Clause-Views`) |
| Included or external | Included as minimal auditable subset under `src/fpga/` (upstream RTL, common, lib/{axi,axis,eth,pcie}); upstream LICENSE text in `LICENSES/upstream/Corundum-LICENSE.txt` |
| Local path | `src/fpga/`, `constraints/`, `tb/cocotb/mqnic.py` |
| Modified? | `src/fpga/fpga_core.v`, `src/fpga/fpga_k35.v`, `constraints/fpga_k35.xdc`, `tb/cocotb/test_fpga_core_macsec_sfp.py` carry explicit "Modified by Le Sun, 2026" notes; all other bundled Corundum files are unmodified copies |
| Modification attribution | `patches/corundum/*.patch` |
| Upstream baseline | The bundled tree is a copy of the Corundum-derived `fpga_25g` sub-tree used by the archived project. The exact upstream commit is **not available locally** (broken/absent git metadata) -> marked `UPSTREAM_BASELINE_UNKNOWN`; see `docs/PUBLISH_REVIEW_REQUIRED.md` |

## AMD/Xilinx Vitis Libraries

| Field | Value |
| --- | --- |
| Project | AMD/Xilinx Vitis Libraries — `security` library, AES-GCM HLS examples |
| Copyright owner | Copyright 2019 Xilinx, Inc. |
| License | Apache License 2.0 (with a BSD component for `ext/xcl2` code, per upstream LICENSE) |
| Included or external | **External dependency** for the Vitis Security Library headers (`gcm.hpp`, `gmac.hpp`, `aes.hpp`) referenced by `hls/src/project/`; **included** as verbatim unmodified example sources in `hls/src/project/` (test.cpp/test.hpp/main.cpp/Makefile/run_hls.tcl/description.json/gld.dat) |
| Local path | `hls/src/project/` |
| Modified? | The vendored example sources are byte-identical to the upstream `Vitis_Libraries-2022.1` `security/L1/tests/gcm/aes128{enc,dec}` files (verified by diff). `settings.tcl` is a project-local configuration whose hardcoded paths were replaced with `<VITIS_SECURITY_LIB_ROOT>` for publication |
| Modification attribution | n/a (unmodified upstream files retain Xilinx copyright) |
| Upstream baseline | `Vitis_Libraries` 2022.1 branch; see `docs/BUILD.md` |

## AMD/Xilinx Vivado / Vitis HLS generated content

AMD/Xilinx tool-generated IP (`.xci`), generated RTL, `.dcp`, `.bit`, simulation
netlists, and all build directories are **not redistributed** in this release.
See `release_metadata/FILES_EXCLUDED.md` and `docs/BUILD.md`.

## Other

| Project | Notes |
| --- | --- |
| cocotb / cocotbext-* / scapy (Python testbench dependencies) | Referenced by `tb/cocotb/`; installed from PyPI, not bundled. Their licenses apply at build time. |

If any license conflict or missing notice is found, treat it as a publication
review item (`docs/PUBLISH_REVIEW_REQUIRED.md`) and do not assume correctness.
