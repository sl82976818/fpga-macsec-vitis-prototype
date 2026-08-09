# constraints/

| File | Provenance | Notes |
| --- | --- | --- |
| `fpga_k35.xdc` | Corundum board constraints + Le Sun additions | "Modified by Le Sun, 2026" block; diff in `patches/corundum/fpga_k35_xdc_macsec.patch` |
| `boot.xdc` | Corundum (unmodified) | boot logic timing constraints |
| `corundum_syn/` | Corundum synthesis/IP tcl (unmodified) | IP setup and timing constraints shipped by Corundum |

The archived routed run ended with timing **not met** (WNS ≈ −0.206 ns); the
MACsec pblock and async clock-group additions in `fpga_k35.xdc` are part of
the attempted timing recovery, not a proven fix.
