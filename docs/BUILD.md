# Build

> **Status: `CLEAN_REBUILD_NOT_YET_PROVEN`**
>
> The archived project was built interactively in Vivado/Vitis and its
> generated IP (`ip/`, `.gen/`, `.cache/`, `.runs/`, bitstreams, checkpoints)
> is **not redistributed** in this release. A from-scratch clean rebuild has
> not yet been demonstrated. This page documents the known inputs and the
> intended flow so a rebuild can be attempted and then closed as a roadmap
> item.

## Toolchain

- Vivado **2022.1**
- Vivado HLS **2022.1**
- Target part: **xcku040-ffva1156-2-e** (Xilinx Kintex UltraScale, KU040)
- Simulators used historically: Vivado xsim (project mode), Icarus Verilog
  (iverilog) for the security regression experiments, cocotb 1.7.2 + cocotbext
  (Python) for the integration testbench.

## External dependencies (not vendored)

| Dependency | Purpose | Baseline |
| --- | --- | --- |
| Corundum | NIC framework (PCIe/DMA/MAC/board support) | see `UPSTREAM_BASELINE_UNKNOWN` note below |
| AMD/Xilinx Vitis Libraries | Security library headers `xf_security/{gcm,gmac,aes}.hpp` used by HLS synthesis | `Vitis_Libraries` 2022.1 branch |
| cocotb / cocotbext-* / scapy | integration testbench | PyPI, latest per `requirements` in `tb/cocotb/` |

The `security/` copy from the prototype referenced `security/L1/include/
xf_security/`; the required headers come from the Vitis Libraries `security`
submodule. Set `<VITIS_SECURITY_LIB_ROOT>` accordingly (see
`hls/src/project/aes128*/settings.tcl`).

## Source layout in this release

```
src/macsec/            Le Sun MACsec RTL (wrappers, tag append/strip, bridges)
src/fpga/              Corundum RTL subset (fpga_core.v, fpga_k35.v, common, lib/*)
constraints/           fpga_k35.xdc, boot.xdc, Corundum synthesis tcl
hls/src/project/       Vitis AES-GCM HLS example sources (aes128enc/dec)
patches/corundum/      diffs that turn the baseline Corundum into this tree
tb/                    cocotb integration test + E1/E2 security regressions
scripts/               historical build/debug helper scripts
```

## Intended build flow

1. **HLS cores** — build `aes128enc` and `aes128dec` with Vivado HLS 2022.1:
   `vitis_hls -f hls/src/project/<d>/run_hls.tcl`. This regenerates the
   `test()` IP (top `test`, AP_FIFO 128-bit interface) whose exported RTL
   historically lived under `ip/aes128gcm_enc|dec/`.
2. **IP setup** — regenerate the board IP (PCIe, GT transceivers, clock
   wizard) in Vivado using the Corundum-shipped `*.tcl` IP scripts under
   `constraints/corundum_syn/` (and Corundum's `fpga/.../syn/vivado` IP
   scripts for the full project). The archived project used these IPs:
   `clk_wiz_0`, `eth_xcvr_gth_channel`, `eth_xcvr_gth_full`,
   `pcie3_ultrascale_0`, `hls_aes128gcm_enc`, `hls_aes128gcm_dec`.
3. **RTL project** — create a Vivado project with top `fpga`
   (`src/fpga/fpga_k35.v` → `fpga_core.v`), the Corundum common/lib sources,
   the `src/macsec/*` RTL, and `constraints/*`.
4. **Apply patches** — `git apply patches/corundum/*.patch` against the
   baseline Corundum tree (see baseline note).
5. **Synthesis/implementation** — run synth/impl; target the same timing
   constraints as the archived project. Note: the archived routed run ended at
   **WNS ≈ −0.206 ns (not met)**; a clean rebuild must first recover timing.

## Baseline note (important)

The bundled Corundum subset under `src/fpga/` matches the archived project's
`fpga_25g` tree. The exact upstream Corundum commit it was copied from is
**not available locally** (the project is not a git repo and the
`corundum-master` symlink is broken). Therefore the Corundum baseline is
marked **`UPSTREAM_BASELINE_UNKNOWN`**. The patches in `patches/corundum/`
are diffs against the pre-MACsec `mqnic_pciex8` project tree, which is itself
Corundum-derived at an unknown commit. Before publishing, recover the actual
Corundum baseline and re-derive the patches (see `docs/PUBLISH_REVIEW_REQUIRED.md`).

## Missing pieces for a clean rebuild (roadmap items)

- Corundum baseline commit identification.
- Deterministic IP regeneration (Vivado flow, non-interactive).
- Full project Tcl for non-interactive synthesis/implementation.
- Routed timing met (WNS ≥ 0).
- Integrated build automation (HLS + IP + RTL + impl).
