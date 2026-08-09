# hls/

HLS portion of the prototype.

## Layout

```
hls/src/project/aes128enc/   Vitis AES-GCM encrypt HLS example (upstream, unmodified)
hls/src/project/aes128dec/   Vitis AES-GCM decrypt HLS example (upstream, unmodified)
hls/scripts/                 build scripts (settings.tcl, see below)
```

## Provenance

- `test.cpp`, `test.hpp`, `main.cpp`, `Makefile`, `run_hls.tcl`,
  `description.json`, `gld.dat` are **AMD/Xilinx Vitis Libraries 2022.1**
  example sources (`security/L1/tests/gcm/aes128{enc,dec}`), vendored
  **byte-identical** (verified by diff). They retain the Xilinx Apache-2.0
  copyright headers. **Do not attribute these to Le Sun.**
- `settings.tcl` is a project-local configuration; the hardcoded local paths
  were replaced with `<VITIS_SECURITY_LIB_ROOT>` for publication.
- The Vitis Security Library headers used at synthesis time
  (`xf_security/{gcm,gmac,aes}.hpp`) are **not vendored** — add the Vitis
  Libraries 2022.1 `security` tree and set `<VITIS_SECURITY_LIB_ROOT>`.

## Building

```
vitis_hls -f hls/src/project/aes128enc/run_hls.tcl
vitis_hls -f hls/src/project/aes128dec/run_hls.tcl
```

Requires Vitis HLS 2022.1, part `xcku040-ffva1156-2-e`. The generated IP's
exported RTL is **not** included in this release (see
`release_metadata/FILES_EXCLUDED.md` and `docs/BUILD.md`).
