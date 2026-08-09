# scripts/

Project helper scripts (historical engineering artifacts). Original Le Sun
work, BSD-2-Clause.

| File | Purpose |
| --- | --- |
| `test.sh` | Historical cocotb regression runner (env vars + pytest invocation) |
| `reproduce_timing_physopt.tcl` | Vivado batch script to re-run post-route physopt timing reproduction |
| `sweep_postroute_physopt.tcl` | Vivado strategy sweep for post-route physopt |

These scripts reference the archived project's structure and are provided for
auditability. They are not a clean build flow — see `docs/BUILD.md`.
