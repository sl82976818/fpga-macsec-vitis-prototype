# Secret / Privacy / Confidentiality Scan

Scan performed on the release candidate tree during preparation
(2026-08-09). Scan of the **production tree was not performed and is not
needed** — only the release candidate is published.

## Method

Pattern scan for: API keys/tokens, private key blocks, certificates,
passwords, email addresses, IP addresses, `/home/<user>` paths, hostnames,
and common credential markers. Files larger than 2 MB (e.g. license texts)
were skipped. `release_metadata/SHA256SUMS` was excluded.

## Findings

### Resolved during preparation

| File | Finding | Resolution |
| --- | --- | --- |
| `docs/engineering_log/wireshark_malformed_pag.txt` | lab peer IP `10.0.0.5`, NetBIOS hostname `PETA-SYSTEM-PRO` | replaced with `<lab-peer-ip>` / `<peer-hostname>` (technical content preserved) |
| `scripts/reproduce_timing_physopt.tcl`, `scripts/sweep_postroute_physopt.tcl` | hardcoded `<home>` project paths | replaced with `<archived-project-root>` |
| `release_metadata/SOURCE_MANIFEST.{csv,json}` | `original_path` fields contained the `<home>` prefix | normalized to `<home>` (traceability preserved) |
| `hls/src/project/*/settings.tcl` | hardcoded `<home>/Downloads/...` | replaced with `<VITIS_SECURITY_LIB_ROOT>` |
| `docs/audits/*`, `docs/engineering_log/*` | absolute workspace paths | normalized during the sanitized-copy pass |

### Benign / false positives (no action)

| File | Match | Classification |
| --- | --- | --- |
| `tb/cocotb/test_fpga_core_macsec_sfp.py` | `192.168.1.100`, `10.10.0.1` | synthetic test addresses used as packet payloads in the loopback testbench; not infrastructure |
| `tb/tb_fpga_core_integration.v`, `CODEX_CHANGELOG.md`, `simulation_coverage_audit` | "PASS:" strings | matched `pass:` regex; false positive |
| `src/fpga/lib/pcie/dma_if_pcie_rd.v` | `6.2.3.2` | version-like text, not an IP address |
| Any `0x00112233445566778899AABBCCDDEEFF` key reference | AES test key | **Public test key — not a production secret.** Explicitly labeled as a test key in the README and audits |

### Known public test key

The AES key `0x00112233445566778899AABBCCDDEEFF` appears in the source and
audits. It is a **public demo/test key**, not a production secret, and is
documented as such (see `docs/SECURITY_STATUS.md`). It must **not** be
reused as a real key.

## Residual risk

The scan is regex-based. A fresh scan **must be re-run** just before
publication (the release tree will change), and the author should review the
diff between the release candidate and the intended public tree. See
`docs/PUBLISH_REVIEW_REQUIRED.md`.

## Action status

`PUBLISH_REVIEW_REQUIRED` for: any future addition of files with unknown
credentials, and for the final pre-publication re-scan.
