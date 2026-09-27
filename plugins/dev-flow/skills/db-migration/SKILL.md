---
name: db-migration
description: Design, write and review database schema migrations and data backfills safely, with rollback and zero-downtime in mind. Use whenever the user adds, alters or drops tables, columns, indexes or constraints, writes a migration file (Laravel, Doctrine, Flyway, Liquibase, Alembic, Prisma, raw SQL), backfills data, or asks "is this migration safe". Stops for confirmation before anything destructive.
---

# Database migrations

## Before writing
1. Find the migration tool and conventions in the repo (`code-intel`): directory, naming, whether `down`/rollback is expected, how it runs in CI and prod.
2. Establish scale and traffic: approximate row counts and whether the table is hot. If unknown, ask; do not assume small.
3. Identify every reader and writer of the affected columns across services (search sibling repos if available). Mixed-version deploys mean old code and new schema coexist.

## Safe change patterns (expand, migrate, contract)
- **Add column**: nullable or with a constant default first. Avoid volatile defaults and full-table rewrites on large tables. Add NOT NULL only after backfill.
- **Rename or change type**: never in place. Add new column, dual-write, backfill in batches, switch reads, stop writing old, drop old in a later release.
- **Drop column/table**: only after no code reads or writes it in any deployed version. Requires explicit user confirmation.
- **Indexes**: build concurrently where the engine supports it (`CREATE INDEX CONCURRENTLY` on PostgreSQL; online DDL/`ALGORITHM=INPLACE` on MySQL). Check lock behaviour for the engine and version in use.
- **Constraints and foreign keys**: add as not-valid or deferred, validate separately when supported; check existing data violates nothing first (write the query).
- **Backfills**: separate from schema DDL, batched (for example 1k to 10k rows), resumable, idempotent, throttled, and outside a single giant transaction. Log progress.

## Checklist before declaring it done
- [ ] Runs on an empty DB and on a copy or seed of realistic data. Show output.
- [ ] Rollback path exists and was tested, or the user accepted that it is forward-only, with the reason recorded.
- [ ] Locking and duration estimated for the largest table touched.
- [ ] Old app version still works against the new schema, and new version against the old schema during rollout.
- [ ] ORM entities, DTOs, API contracts, fixtures and seeders updated.
- [ ] Data-loss risk stated plainly.

## Hard rules
- Never run a migration against a shared, staging or production database yourself. Provide the command and let the user run it.
- Never write `DROP`, `TRUNCATE`, or `DELETE` without a `WHERE` in a migration without explicit approval of that statement.
- Do not edit a migration that may already have run anywhere; add a new one.
- Report anything you could not test (engine version differences, production data shape).
