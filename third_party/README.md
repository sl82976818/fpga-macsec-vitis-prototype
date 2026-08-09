# third_party/

This directory is intentionally minimal. The release favors **documenting
external dependencies over vendoring entire upstream trees**.

| Dependency | In this release | How to obtain |
| --- | --- | --- |
| Corundum | Minimal auditable subset under `src/fpga/` (see `docs/PROVENANCE.md`) | Full tree: https://github.com/alexforencich/corundum |
| AMD/Xilinx Vitis Libraries | Vendored unmodified example sources under `hls/src/project/`; Security Library headers **not vendored** | Full tree: https://github.com/Xilinx/Vitis_Libraries (2022.1 branch) |

Full license texts are in `LICENSES/`. Attribution and modification status
are in `THIRD_PARTY_NOTICES.md`, `docs/PROVENANCE.md`, and the per-file SPDX
headers.
