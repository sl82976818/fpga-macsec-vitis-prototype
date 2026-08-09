# patches/

Diffs that document the modifications made to third-party sources for this
prototype. Apply them to the relevant upstream baseline to reproduce the
modified files.

## corundum/

| Patch | Applies to | Baseline |
| --- | --- | --- |
| `fpga_core_macsec.patch` | `fpga/mqnic/Nexus_K3P_S/fpga_25g/rtl/fpga_core.v` | pre-MACsec Corundum-derived project tree (see note) |
| `fpga_k35_macsec.patch` | `fpga/mqnic/Nexus_K3P_S/fpga_25g/rtl/fpga_k35.v` | same |
| `fpga_k35_xdc_macsec.patch` | `fpga/mqnic/Nexus_K3P_S/fpga_25g/fpga_k35.xdc` | same |

> **Baseline note**: these patches were derived as diffs against the
> pre-MACsec `mqnic_pciex8` project tree, which is itself Corundum-derived at
> an unknown commit (`UPSTREAM_BASELINE_UNKNOWN`, see `docs/BUILD.md`). The
> path labels inside the patches use Corundum-relative paths. Before
> publishing, re-derive these patches against the actual Corundum baseline
> (see `docs/PUBLISH_REVIEW_REQUIRED.md` item P1).

## vitis/

No Vitis Libraries source files were modified by this project; the vendored
HLS example sources are byte-identical to upstream. The only project-local
file is `hls/src/project/*/settings.tcl`, whose hardcoded paths were replaced
with `<VITIS_SECURITY_LIB_ROOT>` for publication. No patch is required; see
`hls/README.md`.
