# Changelog

All significant changes to the architecture corpus are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Initial 25-document architecture corpus (DOC-001 through DOC-025)
- README with quick-start navigation and production readiness gate tracker
- CONTRIBUTING guide and Architecture Review Board process
- GitHub issue templates: ARB review, ADR proposal, document feedback
- CODEOWNERS with security-sensitive document co-review requirements

### Pending
- ADR-007 Connected Registry decision (in progress)
- Token Broker penetration test (GATE-002)
- Chaos engineering test execution (GATE-003)
- EMS API integration validation (GATE-005)

---

## How to use this changelog

When merging a PR that changes a document, add an entry here:

```markdown
## [YYYY-MM-DD]

### Changed
- DOC-009: Updated Token Broker scaling triggers (Section 5.2)

### Added
- DOC-023: ADR-016 — [new decision title] (Approved)
```
