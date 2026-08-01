# ADR P0.7D-5.9 - Schedule Days Decision

## Decision

Do not introduce `schedule_days/{dayKey}` for the initial V2 production
scheduling model. The canonical scheduling coordinate remains
`dayKey + slotId`, and a V2 approval is permitted only when the exact Coach
availability document for that coordinate exists and is active.

`schedule_days` is not a concurrency lock. The Coach and Student canonical
slot documents are the only double-booking coordinates. A global day catalog
would add a trusted rolling-horizon job, a new failure mode, and an extra
Rules document access without preventing a second Coach or Student booking.

## Canonical day key

The only accepted representation is the ASCII string `YYYY-MM-DD`:

- year: `1000` through `9999`;
- month: `01` through `12`;
- day: `01` through `31`.

Rules can enforce this syntactic representation with a regular expression.
It rejects alternate forms such as `2026-8-3`, slash-separated values,
`2026-13-01`, and `0000-00-00`. Rules cannot reliably validate Gregorian
month lengths or leap years from the string alone. Therefore a syntactically
valid but non-calendar value such as `2026-02-31` is a data-quality/audit
problem, not a second representation of an actual scheduling coordinate.

It cannot bypass a canonical collision: another representation of the same
real date fails the strict format, and a non-calendar value is a distinct
coordinate with no corresponding normal UI date. A request is also gated by
the Coach availability document at exactly the same `coachId/dayKey/slotId`.

## Availability as the business gate

For a new approval, Rules must require an active V2 Coach availability
document at:

```text
coach_availability/{coachId}/days/{dayKey}/slots/{slotId}
```

The document must repeat `coachId`, `dayKey`, `slotId`, and `active: true`.
The booking request, Session, Coach slot, Student slot, and availability path
must all agree on the same coordinate. This makes an absent availability a
safe denial, while allowing each Coach to offer weekends, vacations, and
custom hours without a global calendar policy.

Availability is a Coach-owned product schedule, not a global trusted calendar.
It must not silently invalidate an existing Session. Approval checks it only
when a Session is created; later removal or deactivation affects future
requests only.

## Why no rolling horizon now

Rules cannot parse `dayKey` into a timestamp and safely compare it to
`request.time` for a rolling horizon. A `schedule_days` catalog can provide
that policy, but requires trusted documents to be continuously provisioned.
Without Cloud Functions, an overlooked provisioning run causes safe but total
booking denial for future days. BODY HUB currently has no global holiday or
facility closure requirement, and Coach availability already represents
vacations and closed days. The catalog is therefore operational cost without
a current security or product benefit.

The UI and repository should prevent past or excessively distant availability
using canonical date construction. That is product validation. It is not
presented as a Rules-enforced security boundary. A malicious Coach can only
offer its own availability; it cannot reserve another Coach or Student.

If global closures, legal calendars, or centrally managed horizons become a
real requirement, add an immutable trusted `schedule_days` catalog later as a
separate versioned policy gate. Existing Sessions remain valid because their
coordinate snapshot is immutable.

## Rules cost

Replacing the catalog lookup with one exact availability lookup does not
increase Rules access calls. A future approval needs approximately five
distinct relation documents: booking request, Coach availability, Coach slot,
Student slot, and Session (plus entitlement/roster when those packages are
implemented). Reused `getAfter()` calls are cached within one evaluation.
This stays below the 10 per-operation / 20 atomic-operation Rules budgets in
the isolated proof; final production Rules must measure the exact rule graph
again when entitlement and roster writes are added.

## Rejected alternative

`schedule_days/{dayKey}` is deferred rather than deleted as a future option.
It is not required to make the hourly slot collision proof correct.
