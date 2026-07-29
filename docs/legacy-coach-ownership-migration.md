# Legacy coachId ownership migration

`tool/migrate_legacy_coach_ownership.js` is a Firebase Admin SDK tool for
backfilling only missing legacy `coachId` fields. It is independent from both
Flutter applications and must never be run from a client build.

## Safety contract

- `student_profiles/{studentId}.coachId` is the only ownership source.
- Only `active` profiles with a non-empty `coachId` are eligible.
- A non-empty target `coachId` is never overwritten.
- `lesson_change_requests` require a matching source Lesson before a write.
- `student_packages` records whose document ID and `studentId` differ are
  reported as conflicts for manual review.
- The tool scans all target collections by document ID, so omitted fields are
  not missed by a null query.

## Commands

All commands require an Admin SDK credential outside the Emulator. The default
mode is read-only dry-run:

```powershell
npm run migrate:legacy-coach-ownership -- --project-id body-hub-10745 --output-dir .\migration-reports
```

Apply requires explicit acknowledgement:

```powershell
npm run migrate:legacy-coach-ownership -- --apply --project-id body-hub-10745 --page-size 250 --error-threshold 0.05 --output-dir .\migration-reports
```

Resume only an interrupted run after reviewing its `summary.json` and
`checkpoint.json`:

```powershell
npm run migrate:legacy-coach-ownership -- --apply --resume <runId> --output-dir .\migration-reports
```

Rollback accepts either a run ID below `--output-dir` or a report directory:

```powershell
npm run migrate:legacy-coach-ownership -- --rollback <runId> --output-dir .\migration-reports
```

## Reports and checkpoints

Each run writes a dedicated directory containing:

- `records.jsonl` and `records.csv`: one result per scanned document.
- `rollback.jsonl`: pre-write ownership state plus successful-write entries.
- `checkpoint.json`: collection, last document ID, and completed page number.
- `summary.json`: run ID, project ID, mode, migration version, timestamps, and
  scanned/updated/skipped/conflicted/failed totals.

Apply mode continues after individual conflicts and technical failures. It uses
BulkWriter retry/backoff and an `lastUpdateTime` precondition. A document that
changes after being read is reported as failed rather than overwritten. The run
stops safely after a completed page when technical failures exceed
`--error-threshold`.

Rollback only restores records present as successful entries in the rollback
report and only while their current `coachId` still equals the exact value
written by that migration. Manual or later application changes are preserved.

## Production sequence

1. Run the Emulator fixture suite: `npm run test:coach-ownership-migration`.
2. Use a production service account with least-privilege Firestore access.
3. Run a production dry-run and review conflicts/skips before any apply.
4. Start with a low `--limit` pilot, review reports, then resume or start the
   full apply during a low-traffic window.
5. Preserve all report directories for audit and potential rollback.
