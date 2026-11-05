# Risks and decisions

Source: submitted SRS V0.1. All risk outcomes below remain unverified.

| SRS risk | Likelihood / impact | Submitted mitigation |
|---|---|---|
| R-01: handwriting recognition accuracy | Medium / High | Correction UI first, limited symbol scope, measured benchmark |
| R-02: AI exceeds 300 ms target | Medium / Medium | Smaller model for editor actions, streaming/cache, sprint latency measurements |
| R-03: CAS GPU access/capacity | Medium / Medium | Confirm access/specs; capped Modal/AWS fallback |
| R-04: platform breadth or iPad pen latency | Medium / Medium | Shared core, early pen prototype, possible native Swift fallback |
| R-05: exam-period team availability | Medium / Medium | Lighter sprints, two people per critical component |

## Open decisions before setup

- The stack table proposes React/TypeScript + Electron + Capacitor with Swift fallback, while the repository-structure section names a SwiftUI iPad interface. Confirm the intended first implementation.
- The constraints say no proprietary third-party software, while model/infrastructure plans name Gemini and commercial cloud services. Clarify permitted dependencies and cost limits.
- Math command implementation references SymPy in requirements but an own engine in feasibility text. Decide the correctness boundary and reference implementation.
- Define benchmark datasets, supported expressions, hardware, latency measurement boundaries and relevance evaluation before claiming SRS quantitative targets met.
- Keep November 22 team readiness distinct from November 23 course delivery.

## Decision log

| Date | Decision | Authority / rationale |
|---|---|---|
| 2026-11-04 | Maintain capstone trackers in this repository first; documentation baseline before application setup | Saad's explicit request in this chat |

Future changes should state the affected requirement IDs, rationale, team agreement and verification impact. Preserve the submitted PDF as historical baseline.
