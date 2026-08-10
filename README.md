# FPGA AES-GCM / Experimental MACsec Research Prototype

**Corundum + AMD Vitis Security Library**

A research prototype of an inline AES-128-GCM protected Ethernet datapath on a
Corundum-based FPGA NIC, developed on the **AMD/Xilinx KCU105 (Kintex UltraScale
KU040)** and integrating the AMD/Xilinx Vitis Security Library AES-GCM core.
The archived Corundum design baseline used by this project did not provide a
native KCU105 target; the board-level NIC design was ported/adapted to KCU105
as part of this work. This repository is an **audited release candidate** of an
archived engineering project — including the full story of how it became
functional, hit a performance wall, was later decomposed cycle-by-cycle, and
was found to have security architecture gaps.

## Status (one screen)

| Item | Status |
| --- | --- |
| Target board | AMD/Xilinx KCU105 (KU040), project-specific Corundum port |
| Functional datapath | YES |
| AES-GCM mathematical core | VERIFIED (300-vector C-sim vs OpenSSL, RTL cosim) |
| Historical ~2.7G project baseline | YES (archived project label) |
| 10G line-rate implementation | NO |
| Production security closure | NO |
| Full IEEE 802.1AE compliance | NO |
| Research / educational use | YES |

> [!WARNING]
> This repository is a research prototype.
>
> The archived revision contains known security deficiencies and MUST NOT
> be deployed as a production MACsec endpoint.
>
> Known blockers include authentication-before-release failure,
> reset-induced AES-GCM nonce reuse risk, missing replay protection,
> and incomplete SA/key lifecycle management.

## What is this?

An experimental MACsec-style protection datapath implemented on the open
[Corundum](https://github.com/alexforencich/corundum) FPGA NIC framework
(10G MAC / PCIe / DMA), with an AES-128-GCM core synthesized from the
AMD/Xilinx Vitis Security Library via Vitis HLS 2022.1. TX encrypts and appends
an ICV tag; RX strips the tag and decrypts. The project uses a **custom
experimental frame format**, not full IEEE 802.1AE.

## Who wrote what?

- **Le Sun** wrote the project-specific MACsec integration: `src/macsec/`
  wrappers, tag append/strip, HLS integration, verification infrastructure,
  and the audits. He also ported the archived Corundum-based NIC design to the
  AMD/Xilinx KCU105, including the board-level integration and constraints
  needed to bring up the NIC on that platform. These project-specific files
  carry a `Copyright (c) 2026 Le Sun` header where applicable.
- **Corundum** (Berkeley Regents / Alex Forencich, BSD-2-Clause-Views) provides
  the NIC framework under `src/fpga/`; a few files were modified by Le Sun
  (explicitly marked) and the exact diffs are in `patches/corundum/`.
- **AMD/Xilinx Vitis Libraries** (Apache-2.0) provides the AES-GCM HLS example
  sources under `hls/src/project/` (vendored unmodified) and the Security
  Library headers used at build time (external dependency).

See `AUTHORS.md`, `THIRD_PARTY_NOTICES.md`, and `docs/PROVENANCE.md`.

## How fast does it run?

- The archived project carried a **~2.7/2.75 Gbps** performance baseline.
  A later cycle-level audit reproduced approximately **2.60 Gbps** for
  1518-byte frames from the actual serialized architecture.
  A clean board-level iperf artifact for that historical measurement has
  **not** been recovered from the archived project.
- The AES-GCM crypto core itself is **10G-capable** when modeled with cached
  Security Associations (~16 Gbps line for 1518-byte frames, core only).
- The reason the *whole datapath* cannot reach 10G today is architectural: the
  wrapper is single-frame store-and-forward (capture → crypto → release,
  serialized) plus a per-frame crypto setup tax
  (`GF128_prepare()` ≈ 129 cycles/frame, `updateKey()` per frame, etc.).
- **10G is a documented engineering roadmap, not a current capability claim.**

See `docs/PERFORMANCE.md` for the full modeled table (64/512/1518/9000-byte
frames, current vs cached-SA vs core-only), with every figure labeled
measured / historical-label / modeled / projected.

## Why is 2.7G the ceiling? (short answer)

`block throughput ≠ frame throughput ≠ Ethernet line rate`.

The GCM core runs CTR and GHASH at II=1 (128-bit/cycle internally). But each
frame pays ~186 cycles of serial setup (`updateKey`, `H` computation,
`GF128_prepare`, `E(K,Y0)`), and the wrapper holds **one frame in flight** —
capture, crypto, and release cannot overlap. For 1518-byte frames that yields
~2.6 Gbps line. Fixing only the crypto setup (cached-SA) still leaves the
single-frame serialization, capping at ~3.3–3.9 Gbps. Reaching 10G requires
**both** cached-SA and frame-level pipelining.

See `docs/PROJECT_HISTORY.md` and `docs/PERFORMANCE.md`.

## Why is it not secure?

The security audit (2026-08-06) confirmed, with behavioral experiments:

| Security property | Status |
| --- | --- |
| AES-GCM algorithm core | Verified at HLS level (OpenSSL oracle) |
| Nonce uniqueness | **BLOCKER** — reset rolls PN back with the same key |
| Auth before release | **BLOCKER** — RX emits plaintext for invalid-tag frames |
| Replay protection | NOT IMPLEMENTED |
| SA lifecycle | NOT IMPLEMENTED |
| Key zeroization | GAP |
| Frame context identity | GAP |
| Fail closed | GAP |
| Standard 802.1AE compliance | NOT IMPLEMENTED (custom framing) |

Two blockers were **behaviorally reproduced** in independent read-only
experiments (E1: tag corruption still releases plaintext; E2: reset rolls
`tx_pn` back to 1 with the same key). See `docs/SECURITY_STATUS.md` and
`docs/audits/`.

## What are the next steps?

```
secure first
then cached-SA
then frame-level pipelining
then 10G verification
```

A concrete roadmap (`docs/ROADMAP.md`) defines v0.3 security baseline,
v0.4 cached-SA refactor, v0.5 datapath pipelining, and v1.0-candidate
gates (10G sustained, timing met, independent oracle, security closure,
post-synth verification, board verification).

## How do I build it?

See `docs/BUILD.md`. Requirements: Vivado / Vitis HLS 2022.1, part
`xcku040-ffva1156-2-e`, Corundum baseline (see the note on
`UPSTREAM_BASELINE_UNKNOWN` in `docs/PROVENANCE.md`), and the AMD/Xilinx
Vitis Libraries 2022.1 as an external dependency. A **clean rebuild has not
yet been proven** (`CLEAN_REBUILD_NOT_YET_PROVEN`); the archived project was
built interactively and its generated IP is not redistributed.

## What is NOT included?

- AMD/Xilinx generated IP (`.xci`), generated HLS RTL, `.dcp`, `.bit`, `.ltx`
- Vivado caches / run directories / logs
- HLS-generated RTL copies, simulation build artifacts
- Corundum's full repository (only the auditable minimal subset is bundled;
  the complete upstream tree is available from the Corundum project)

See `release_metadata/FILES_EXCLUDED.md` and `docs/BUILD.md`.

## Can I use this in production?

**No.** This repository is a research and educational artifact. Its value is
that it documents a real FPGA security datapath that:

1. became functionally operational,
2. hit a real performance wall,
3. was later decomposed cycle-by-cycle,
4. was found to have security architecture gaps,
5. and now serves as an auditable starting point for a cleaner design.

The open performance and security post-mortem is the point of publishing it,
not the completeness of the archived revision.

## Repository layout (high level)

```
src/macsec/           Le Sun original MACsec RTL (BSD-2-Clause)
src/fpga/             Corundum NIC RTL subset (BSD-2-Clause-Views, some modified)
hls/src/project/      Vitis AES-GCM HLS example sources (Apache-2.0, unmodified)
tb/                   verification (cocotb integration + E1/E2 security regressions)
constraints/          XDC constraints (Corundum + MACsec additions)
patches/corundum/     diffs for the modified Corundum files
docs/                 story, architecture, performance, security, roadmap, audits
release_metadata/     provenance manifest, license/secret scans, SHA256SUMS
```

## License

Multi-license tree. Original Le Sun code: BSD-2-Clause. Third-party and
derivative files retain their upstream licenses. See `LICENSE`,
`THIRD_PARTY_NOTICES.md`, `LICENSES/`, and `docs/PROVENANCE.md`.

## Version

This release candidate is described as **v0.2-audited**. No git tags exist
yet; see `CHANGELOG.md` for the recommended tagging scheme.

---

**Publication preparation status:** `RELEASE_CANDIDATE_REQUIRES_HUMAN_REVIEW`
— see `docs/PUBLISH_REVIEW_REQUIRED.md` for the pre-publication checklist.
