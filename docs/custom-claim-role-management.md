# Custom Claim role management

`tool/manage_custom_claim_roles.js` is the only repository-provided operator
tool for assigning BODY HUB's trusted Firebase Auth roles. Firestore Rules use
`request.auth.token.role`; `users/{uid}.role` is UI metadata only.

## Prerequisites

- A trusted operator has approved the assignment.
- Production use has a minimally privileged Firebase service-account JSON.
- Its `project_id` is explicitly supplied with `--project-id` and matches the
  JSON. The tool refuses a mismatch.
- The operator identity is supplied with `--operator` for any `--apply` run.

Never place the service-account JSON under the repository. Store it in the
approved secret manager or a protected operator workstation path.

## Commands

All mutating commands are dry-run by default. They write no Auth or Firestore
data unless `--apply` is supplied.

```powershell
# Inspect a user by UID or email.
node tool/manage_custom_claim_roles.js show-role --uid <uid> --project-id <project>

# Preview, then apply a Coach role.
node tool/manage_custom_claim_roles.js set-role --email coach@example.com --role coach --project-id <project> --service-account C:\secure\service-account.json
node tool/manage_custom_claim_roles.js set-role --email coach@example.com --role coach --apply --operator <operator-id> --project-id <project> --service-account C:\secure\service-account.json

# Remove a role, or list all current privileged users.
node tool/manage_custom_claim_roles.js remove-role --uid <uid> --apply --operator <operator-id> --project-id <project> --service-account C:\secure\service-account.json
node tool/manage_custom_claim_roles.js list-privileged-users --project-id <project> --service-account C:\secure\service-account.json
```

Only `coach` and `admin` are accepted. Existing unrelated custom claims are
preserved. The final Admin cannot be removed or demoted by this tool.

## Audit and partial failures

Each role-change attempt creates JSONL audit records in `claim-role-reports/`.
Entries include the run ID, project ID, environment, operator, UID, email,
previous role, proposed role, timestamp, and result.

The Auth claim is written first. The tool then synchronizes
`users/{uid}.role`. If that metadata document is missing or its update fails,
the result is recorded as `partial_failure`; the claim is intentionally not
rolled back, because a failed rollback could remove a valid security decision.
Operators must resolve the metadata issue and rerun the idempotent command.

## Emulator safety

Use `--emulator` only with a non-production project ID and loopback
`FIREBASE_AUTH_EMULATOR_HOST` plus `FIRESTORE_EMULATOR_HOST`. Emulator mode
rejects service accounts. Production mode rejects emulator environment
variables and requires an explicit matching service account.

The repository's Auth/Firestore Emulator test is run with:

```powershell
npx firebase emulators:exec --config test/admin/firebase.claim-role-tests.json --project bodyhub-claim-role-tests --only auth,firestore "node --test test/admin/custom_claim_role_manager.test.js"
```

## Token refresh

Custom claims are embedded in Firebase ID tokens. A role change may not affect
an already-issued token immediately. The user must sign out and sign in again,
or the client may call `currentUser.getIdToken(true)` after a trusted operator
confirms the change. Flutter application behavior is intentionally unchanged
by this operational package.
