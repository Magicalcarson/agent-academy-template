---
name: backend-architecture-review
description: "Holistic backend architecture review and design - domain and service boundaries, background work, reliability, reconciliation, correctable operations, and auditability - synthesizing the system above the mechanics. Delegates HTTP contract to api-design, ORM to prisma-patterns, failure semantics to error-handling, security and deployment to security-review, and containers to docker-patterns."
---

# Backend Architecture Review Skill

Use this skill when designing, reviewing, or refactoring backend systems for SaaS, apartment/dormitory management, billing, tenant records, dashboards, admin panels, APIs, background jobs, or integrations - at the level of how the pieces fit, not the mechanics of any one piece.

## Goal

Prevent demo-app backend decisions from reaching production. The backend must be boring, auditable, secure, and operationally reliable.

## Scope and handoffs (delegate mechanics)

This skill owns the **whole-system architecture synthesis** — boundaries, responsibilities, data flow, reliability posture, and operability. It does NOT re-do the specialists' mechanics; when a concern is really a single-layer detail, name it and hand off:

- `api-design` — HTTP contract shape (paths, methods, status, pagination grammar).
- `prisma-patterns` — ORM query/transaction/migration mechanics.
- `error-handling` — typed failures, retry/backoff, circuit-breaker, silent-swallow detection.
- `security-review` — auth/authz, payments, secrets, deployment hardening, audit-log/observability review.
- `docker-patterns` — container/compose/NAS deployment mechanics.

Keep this review at the altitude those skills do not cover: does the decomposition make sense, and can the business operate and audit it.

## Review areas

1. Domain boundaries
   - company / branch / building / floor / room
   - tenant / booking / contract / invoice / receipt
   - meter reading / utility billing / payment / deposit
   - staff roles / owner roles / audit logs

2. API shape (contract details -> api-design)
   - resource naming
   - consistent pagination/filtering/sorting
   - idempotency for write endpoints
   - stable error responses
   - API versioning strategy

3. Service boundaries
   - avoid God controllers
   - separate billing calculation from persistence
   - separate read models from mutation workflows when needed
   - background jobs for slow or external work

4. Reliability (failure mechanics -> error-handling)
   - retries with limits
   - dead-letter handling
   - transaction boundaries
   - safe re-run behavior
   - observability and auditability

5. Operational fit
   - can staff correct mistakes safely?
   - can owner audit who changed what?
   - can financial data be reconciled?
   - can support debug a tenant complaint?

## Red flags

- Auth checked only in frontend.
- Company/branch scope missing from queries.
- Billing logic spread across UI and backend.
- Invoices mutable after receipt issuance without audit trail.
- Background jobs that cannot be safely retried.
- Delete operations without recovery/audit.
- Admin endpoint that bypasses normal invariants.

## Output format

```markdown
# Backend Architecture Review

## Executive summary
- 

## Architecture strengths
- 

## Critical risks
| Area | Risk | Why it matters | Fix | Owner (this / api-design / prisma / error-handling / security-review / docker) |
|---|---|---|---|---|

## Recommended architecture
- 

## API / service changes
- 

## Operational notes
- 

## Next verification steps
- 
```
