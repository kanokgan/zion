# 0001. Record architecture decisions

- Status: accepted
- Date: 2026-10-11

## Context
Zion Lab grew ad hoc with no record of why things are the way they are. Decisions are made in chats with both claude.ai and Claude Code, so the repo must be the shared memory.

## Decision
Record each significant decision as a short ADR in `docs/decisions/NNNN-title.md`, using `0000-template.md`. Numbers are sequential and never reused. Superseded ADRs stay, with status updated.

## Alternatives considered
- Notes in chat only: lost between sessions and between tools.
- A wiki outside the repo: violates "everything in Git".

## Consequences
Small overhead per decision. Pending decisions (GitOps tool, secrets tool, repo layout, ingress/DNS pattern) each become an ADR and are then recorded in the Conventions section of CLAUDE.md.
