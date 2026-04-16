# Contributing to the Architecture Corpus

This repository contains the authoritative architecture documentation for the
Enterprise Container Registry platform. Changes are governed by the Architecture
Review Board (ARB) process.

## Who can contribute

| Change type | Who | Process |
|---|---|---|
| Editorial fixes (typos, formatting) | Any team member | PR → 1 Platform Engineering reviewer |
| Content updates (facts, procedures) | Document owner or Platform Engineering | PR → CODEOWNERS review |
| New ADR or ADR status change | Any architect | PR → ARB review (use ARB issue template first) |
| New document | Platform Engineering lead | ARB scoping → PR → full CODEOWNERS review |

## Document lifecycle

Documents move through four statuses tracked in the YAML front-matter:

```
DRAFT → REVIEW → APPROVED → SUPERSEDED
```

- **DRAFT** — actively being written; may change significantly
- **REVIEW** — submitted to ARB; no content changes during review
- **APPROVED** — ARB signed off; changes require a new PR with reviewer justification
- **SUPERSEDED** — replaced by a newer document; kept for historical record

## Making a change

1. **Open an issue first** for anything beyond an editorial fix — use the
   appropriate issue template in `.github/ISSUE_TEMPLATE/`.

2. **Branch from `main`** using the naming convention:
   - `docs/DOC-NNN-short-description` for document updates
   - `docs/adr-NNN-short-decision` for new ADRs

3. **Update the document** — ensure:
   - YAML front-matter `status` field is correct
   - Cross-references to other docs use relative links (e.g. `[DOC-009](../phase-3-entitlement/DOC-009_Token_Broker_Architecture.md)`)
   - The `date` field in front-matter is updated

4. **Open a PR** using the PR template. Tag required reviewers per CODEOWNERS.

5. **ARB review** — P0 documents require explicit ARB sign-off before merging.

## Adding an ADR

1. Open an ADR proposal issue.
2. After ARB discussion reaches a conclusion, add the ADR to
   `docs/phase-7-governance/DOC-023_Architecture_Decision_Records.md`.
3. ADRs are never deleted — only marked as `Superseded` with a link to the
   replacement ADR.

## Diagrams

Architecture diagrams live in `diagrams/`. Preferred formats:
- **Mermaid** (`.md` files with mermaid fences) — renders natively in GitHub
- **SVG** — committed directly, rendered inline by GitHub
- **Source files** (Draw.io `.drawio`, Excalidraw) — commit the source alongside
  an exported SVG

## Document naming

Do not rename existing documents — the filenames are referenced in cross-links
across the corpus. If a document is substantially replaced, create a new one
and mark the original as SUPERSEDED.

## Questions

Open a `document-feedback` issue or reach out to the Platform Engineering team.
