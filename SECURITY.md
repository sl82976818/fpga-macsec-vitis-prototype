# Security

## Repository status

This repository is a **research prototype** for FPGA AES-GCM / experimental
MACsec. The archived revision **must not** be deployed as a production MACsec
endpoint. The known security deficiencies are **public and documented**:

- RX releases plaintext **before tag authentication** (auth-before-release
  failure) — confirmed by an independent behavioral experiment.
- Reset rolls the TX PN back to its initial value with the same key, creating
  an AES-GCM **nonce-reuse risk** — confirmed by an independent behavioral
  experiment.
- Replay protection is not implemented.
- SA/key lifecycle, key zeroization, generation/context binding are not
  implemented.
- The framing format is a custom experimental format, **not** a full
  IEEE 802.1AE implementation.

See `docs/SECURITY_STATUS.md`, `docs/VERIFICATION_STATUS.md`, and the audits
in `docs/audits/` for the complete, evidence-based picture.

## Reporting vulnerabilities

Please report suspected vulnerabilities via the repository issue tracker
(preferred) or a future security advisory process. Because this is a research
prototype, there is no promise of long-term security support or of a
guaranteed fix cadence.

## Supported scope

- The current **audited** release branch only.
- Historical generated artifacts (old bitstreams, old IP checkpoints) are
  **unsupported** and should not be used for anything security-sensitive.

Do **not** use this project's AES key handling, IV construction, or tag
verification as a reference implementation for a production MACsec design.
