# Contributing

This is a **research prototype** repository. Contributions are welcome.

## Priorities

- **Security correctness is prioritized over performance.** Any change to
  crypto or security-relevant RTL must be accompanied by:
  - an **independent oracle** (e.g. OpenSSL / PyCryptodome / NIST vectors)
    comparison for the affected path, not only loopback self-consistency;
  - a **negative test** (e.g. corrupted tag, corrupted ciphertext, wrong
    AAD/IV/key) proving the intended drop/fail-closed behavior;
  - a **reset behavior** analysis (especially nonce/PN behavior across reset);
  - a **nonce uniqueness analysis** for any new IV construction.
- A performance claim must state, at minimum:
  - the clock frequency;
  - the frame size;
  - the measurement point (block/core/wrapper/Ethernet line rate);
  - whether the figure is **measured**, **modeled**, or **projected**.

## Process

1. Open an issue or discussion before large changes; the security status is
   not stable enough for drive-by redesign.
2. Follow the existing file organization and attribution rules
   (`docs/PROVENANCE.md`).
3. Preserve upstream copyright and SPDX headers when editing third-party
   files; add a `Modified by <author>, <year>` note.
4. Do not introduce secrets, test keys are public test keys only.

## Verification expectations

Given the documented security blockers (see `SECURITY.md`,
`docs/SECURITY_STATUS.md`), contributions cannot rely on "it passes the
existing loopback test". Proposed verification for new functionality must
address the gaps listed in `docs/VERIFICATION_STATUS.md`.
