# AI-Assisted FPGA Engineering and Audit Methodology

This project was developed and audited with heavy use of AI coding and
reasoning agents. This document is a candid record of what that means for the
credibility of the results — and what it does not mean.

## The headline

**AI output is not an oracle.** Every claim in the audits was required to be
supported by source code, a simulation, a cycle model, or an independent
experiment. An AI agent "finding" a bug is a hypothesis, not proof.

## What AI was used for

- Generation and iteration of the FPGA RTL integration (wrappers, bridges,
  tag handling) during development.
- Writing and debugging testbenches (xsim project-mode frame sweep, cocotb
  integration testbench).
- The read-only audits: source analysis, cycle-level performance modeling,
  verification-coverage enumeration, and security-contract review.
- Drafting this release package (this document included).

## The audit method (four steps)

Every important audit conclusion followed the pattern:

```
agent hypothesis
  -> source evidence        (file:line, RTL structure)
  -> independent experiment (E1/E2 iverilog tests, OpenSSL goldens, cycle model)
  -> classification          (BLOCKER / GAP / NOT_IMPLEMENTED / PROVEN / ...)
```

Examples:

1. **Performance bottleneck** — the hypothesis that "the crypto core is not
   the 2.7G limit" was supported by: the HLS source (`gcm.hpp`/`gmac.hpp`
   showing per-frame `GF128_prepare`/`updateKey`), the HLS II=1 reports, the
   RTL wrapper structure (single-frame store-and-forward), and a cycle model
   that reproduced 2.60 Gbps for 1518-byte frames. Classification:
   `CRYPTO_CAPABLE_INTEGRATION_BOTTLENECK`.
2. **Auth-before-release blocker** — the hypothesis was supported by: RTL
   source (`icv_check_enable=0`, no tag-compare FSM branch) **and** an
   independent iverilog experiment (E1) on the byte-identical production
   `macsec_tag_strip.v`. Classification: `BLOCKER`, behaviorally confirmed.
3. **Reset/PN nonce-reuse risk** — hypothesis supported by RTL source and the
   independent iverilog experiment (E2) on production `macsec_aes_encrypt.v`.
   Classification: `BLOCKER`, behaviorally confirmed.

## Where AI output was NOT used as evidence

- AI statements alone are never cited as PASS evidence.
- The flaky integration regression was reported as flaky (44 PASS / 23 FAIL,
  same-day PASS+FAIL) — it was not laundered into a green.
- No performance number was invented: the 2.7/2.75G label is reported as a
  historical label, the 2.60 Gbps figure as modeled, and the 10G/core numbers
  as projected.
- The security audits explicitly refuse to assume completeness ("assume real
  MACsec") and instead document the actual implemented security contract.

## Limitations and risk

- AI-assisted RTL can be subtly wrong; the negative-test gap (no corrupted
  tag/cipher/AAD/IV/key tests) is real and is called out, not hidden.
- The integration-level oracle is not independent (loopback self-consistency
  only). This is documented in `docs/VERIFICATION_STATUS.md`.
- A human must still perform the legal/provenance review for publication
  (`docs/PUBLISH_REVIEW_REQUIRED.md`); AI classification of "original vs
  upstream vs generated" is cross-checked against headers, hashes, and diffs
  but is not a legal determination.

## Recommendations for readers

Treat every "verified", "modeled", "PROVEN", "BLOCKER", and "NOT_IMPLEMENTED"
label in the audits as an evidence-backed classification whose evidence you
can re-inspect from the sources in this release.
