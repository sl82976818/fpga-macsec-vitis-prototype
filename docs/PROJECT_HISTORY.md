# Project History

This is the story of how the archived prototype evolved. It is the most
important narrative document in this repository: without the history, the
"why" behind the architecture, the performance ceiling, and the security gaps
is not understandable.

## The arc

```
Motivation
  -> Corundum integration
  -> Vitis AES-GCM integration
  -> functional success
  -> ~2.7G ceiling observed
  -> project archived
  -> performance audit
  -> crypto core exonerated
  -> wrapper bottleneck localized
  -> security audit
  -> two security blockers behaviorally reproduced
  -> new architectural roadmap
```

## Motivation

The goal was an inline (on-the-wire) encryption/authentication datapath for
Ethernet frames on an FPGA NIC: receive plaintext frames, protect them with
AES-GCM, transmit; and the inverse on receive. MACsec (IEEE 802.1AE) was the
model, but the goal was a working research datapath, not a standards
certification.

## Corundum integration

The [Corundum](https://github.com/alexforencich/corundum) FPGA NIC framework
provided the PCIe interface, DMA engine, and 10G Ethernet MAC
(`eth_mac_10g`), plus the board support for a Xilinx Kintex UltraScale
(xcku040) based board. This gave a working, packet-moving NIC that could be
extended with a protection stage.

## Vitis AES-GCM integration

The cryptographic core was synthesized with Vitis HLS 2022.1 from the
AMD/Xilinx Vitis Security Library AES-128-GCM code
(`gcm.hpp` / `gmac.hpp` / `aes.hpp`), targeting `xcku040-ffva1156-2-e`. The
HLS IP (`ip/aes128gcm_enc|dec`) exposes an AP_FIFO-style 128-bit interface.
Project-specific Verilog bridged the Corundum 64-bit AXI-Stream MAC domain to
the HLS 128-bit AP_FIFO domain, assembled the custom IV/AAD, appended/stripped
the 16-byte ICV tag, and carried the packet PN as sideband metadata.

## Functional success

The datapath became end-to-end functional:

- xsim project-mode simulation passed a plaintext frame sweep from 64 to 1520
  bytes through the full TX-encrypt / RX-decrypt loopback path.
- The HLS core was independently verified against OpenSSL AES-GCM goldens
  (300 vectors, C-sim) and RTL cosim.
- On hardware, a peer ARP/mDNS capture showed *something* protected flowing
  (the capture was malformed — a lasting verification caveat, see
  `docs/VERIFICATION_STATUS.md`).

## ~2.7G ceiling observed

The project was labeled/archived with a **~2.7 / 2.75 Gbps** performance
baseline (reflected in the project directory names and archive zips). At the
time, that looked like a fundamental performance wall. The exact board-level
iperf artifact for that number was not preserved with the archived project.

## Project archived

The project was shelved because **performance appeared fundamentally too
low** — ~2.7G looked like an unbreakable limit, well short of the 10G line
rate the MAC could support.

## Performance audit

A later read-only, cycle-level audit (2026-08-06) decomposed the datapath.

## Crypto core exonerated

The audit showed the cryptographic core is **not** fundamentally a 2.7G
engine:

- CTR and GHASH loops run at **II=1** (128-bit per cycle internally).
- Modeled with cached Security Associations, the core alone reaches roughly
  **16 Gbps line** for 1518-byte frames — comfortably 10G capable.

## Wrapper bottleneck localized

The 2.7G ceiling comes from the **integration architecture**, not the crypto:

- A per-frame crypto setup tax: `GF128_prepare()` ≈ 129 cycles/frame,
  `updateKey()` per frame, `H` recomputation, `E(K,Y0)` — ≈ 186 cycles/frame
  serial overhead.
- A **single-frame-in-flight store-and-forward** wrapper: capture → crypto →
  release are fully serialized; the next frame cannot start until the current
  frame's tag is complete.

The audit reproduced ~2.60 Gbps for 1518-byte frames from this model, which
matches the historical ~2.7/2.75G label — the measurement was **architecture
consistent**, not invalid. But it also meant the wall was movable.

## Security audit

The same audit cycle evaluated the security contract of the actual
implementation. It found the revision is **not production-secure MACsec**:

- RX releases plaintext **without authenticating the tag first**.
- **Reset rolls the TX PN back** to its initial value with the same key,
  creating an AES-GCM **nonce-reuse** risk.
- Replay protection, SA/key lifecycle, key zeroization, and generation/context
  binding are not implemented.
- The framing is a custom experimental format, not IEEE 802.1AE.

## Two security blockers behaviorally reproduced

Independent, read-only experiments (in a temporary directory, production files
untouched) confirmed the two most serious issues at the behavioral level:

- **E1 — auth-before-release**: a frame with a corrupted ICV tag was still
  stripped of its tag and **released as plaintext** (the FSM only drops frames
  shorter than 24 bytes, never tag mismatches).
- **E2 — reset/PN rollback**: after a frame advanced `tx_pn`, asserting reset
  rolled `tx_pn` back to `PN_INIT=1` with the same key — the same
  `(key, IV)` nonce structure can recur.

These results are recorded in `docs/SECURITY_STATUS.md` and
`docs/audits/`.

## New architectural roadmap

Performance potential does **not** imply security closure. The roadmap
(`docs/ROADMAP.md`) therefore sequences the work as:

```
secure first
then cached-SA
then frame-level pipelining
then 10G verification
```

This release candidate documents that roadmap; it does not claim any of the
future milestones are implemented.
