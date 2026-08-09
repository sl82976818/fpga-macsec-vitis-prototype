# Authors

## Le Sun

Original project work included in this release, where identified by the source
provenance audit (`release_metadata/SOURCE_MANIFEST.csv`), includes:

- FPGA MACsec integration architecture
- project-specific RTL wrappers and protocol adaptation
  (`src/macsec/*` — MACsec TX/RX wrappers, tag append/strip, AES-GCM wrapper
  integration, AXI-Stream &harr; AP_FIFO bridges)
- Vitis AES-GCM HLS integration (project configuration and build flow)
- verification infrastructure and experiments (cocotb integration testbench,
  HLS build/test scripts, E1/E2 independent security experiments)
- performance post-mortem analysis (cycle model)
- security audit integration and recovery roadmap

The upstream and third-party components (Corundum, AMD/Xilinx Vitis Libraries)
are listed as dependencies/upstream works and are **not** claimed as Le Sun's
original work. See `THIRD_PARTY_NOTICES.md` and `docs/PROVENANCE.md`.

## Upstream projects

- **Corundum** — FPGA NIC framework (BSD-2-Clause-Views)
  https://github.com/alexforencich/corundum
- **AMD/Xilinx Vitis Libraries** — security library, AES-GCM HLS examples
  (Apache-2.0)
  https://github.com/Xilinx/Vitis_Libraries

Both are external dependencies/upstream works bundled here only in the
minimal, audit-traceable form described in `docs/PROVENANCE.md`.
