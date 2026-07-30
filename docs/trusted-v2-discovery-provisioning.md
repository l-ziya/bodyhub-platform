# Trusted V2 discovery provisioning

`sports` and `coach_profiles` are source records created only by a trusted
Firebase Admin SDK process. Neither Flutter client has a Firestore create or
delete permission for them.

Use `tool/provision_v2_discovery.js` with a protected service account in
production. It defaults to dry-run, requires `--apply` and `--operator` for a
write, verifies the project through the shared Admin context, and records
JSONL audit output outside Git.

```powershell
# Preview a stable sports catalogue item.
node tool/provision_v2_discovery.js upsert-sport --input C:\secure\tennis.json --project-id <project> --service-account C:\secure\service-account.json

# Provision a canonical-claim Coach profile after its sport IDs exist.
node tool/provision_v2_discovery.js upsert-coach-profile --input C:\secure\coach-a.json --apply --operator <operator-id> --project-id <project> --service-account C:\secure\service-account.json
```

The profile command requires the target Auth user to have canonical `roles`
with `coach: true` or `admin: true` (the temporary scalar claim fallback is
accepted for legacy accounts) and every `specialtyId` to reference an active
sport. It writes system visibility fields (`active`, `bookingEnabled`,
`schemaVersion`, audit timestamps) that Coaches cannot change from Flutter.

For an Emulator-only rehearsal add `--emulator`, use a non-production project
ID, and set the Auth and Firestore emulator hosts. Never use this tool to
create or modify production data without an approved change window.
