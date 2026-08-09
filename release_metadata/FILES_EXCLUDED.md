# Files Excluded

Files from the archived production project that are **not** part of this
release, with the reason for each category. The policy is: **publish source
and rebuild scripts, not tool-generated artifacts.**

## Generated / vendor content (excluded by default)

| Category | Paths | Reason |
| --- | --- | --- |
| HLS-generated IP packages | `ip/aes128gcm_enc/`, `ip/aes128gcm_dec/` (109 files) | Vitis HLS generated RTL/VHDL; regenerable from `hls/src/project/`; redistribution of AMD tool output not confirmed |
| Vivado IP config | `mqnic_gcm_codex.srcs/sources_1/ip/*/*.xci` (6 files) | AMD generated IP config; regenerable in Vivado |
| Vivado generated output | `mqnic_gcm_codex.gen/` (250), `.cache/` (30), `.runs/` (190), `.hw/` (2), `.ip_user_files/` (56), `.Xil/` (1) | build artifacts |
| Synthesis/impl checkpoint | `mqnic_gcm_codex.srcs/utils_1/imports/synth_1/fpga.dcp`, `result_postroute_physopt_pass.dcp` | proprietary DCP |
| Bitstreams | `fix0423.bit`, `fix0428.bit`, `result_postroute_physopt_pass.bit` | generated; contains configuration bits, not source |
| HLS RTL copies for sim | `tb_local/fpga_core/hls_models/enc|dec/` (59 files) | generated HLS RTL (regenerable from HLS IP export) |

## Build / simulation artifacts

| Category | Paths | Reason |
| --- | --- | --- |
| Simulation build | `tb_local/fpga_core/sim_build/` (153) | cocotb/iverilog build outputs, XML result corpus |
| Python env | `.venv_cocotb17/` (2375) | virtualenv, not source |
| Caches | `.pytest_cache/`, `__pycache__/`, `tb_local/fpga_core/.pytest_cache/` | test caches |
| Aux test project | `lib_test_project/` (4), `tmp_logs/` (4) | ad-hoc test scaffolding |
| Vivado logs | `vivado*.log`, `vivado*.jou`, `vivado_pid*.str`, `*.backup.log/.jou` | session logs |
| Timing reports | `result_timing_*.rpt`, `sweep_*.rpt`, `iter_7_CongestedCLBsAndNets.txt`, `tight_setup_hold_pins.txt` | report outputs (their conclusions are captured in the audits) |
| Test-run logs | `macsec_gate2_full_*.log`, `macsec_gate2_full_dbg_*.log` | runner logs |

## Historical diff scratch files (superseded)

| Paths | Reason |
| --- | --- |
| `diff_*.patch`, `diff_*_qr.txt` at project root | interim diffs containing absolute `<home>` paths; superseded by clean patches in `patches/corundum/` |

## Not included from the experiment directory

Compiled iverilog binaries (`run`, `run2`, `run3`, `tb4`–`tb7`, `e2run`) and
the waveform `tb5.vcd` from `<experiment-dir>` were not copied into
`tb/security_regressions/`.

## Corundum / Vitis full trees

The complete Corundum repository and the complete Vitis Libraries tree are
**not** vendored. Only the minimal auditable subsets documented in
`docs/PROVENANCE.md` are bundled; full trees are obtained from upstream
(`THIRD_PARTY_NOTICES.md`).

## Files whose provenance was not confirmed

Any file not covered by the manifest's positive classification was excluded
by default. See `docs/PUBLISH_REVIEW_REQUIRED.md` (§ Unknown-provenance
files) for the policy. Nothing is published "because the project needs it".
