# Firestore role claim provisioning contract

Firestore authorization treats `request.auth.token.role` as the only Coach/Admin
role source. The `users/{uid}.role` field is UI metadata and must not grant
Firestore privileges.

## Trusted issuer

Only a trusted server-side administrative process (Firebase Admin SDK, a
protected Cloud Function, or an equivalent controlled operator workflow) may
set or remove the Firebase Auth custom claim:

```json
{ "role": "coach" }
```

or:

```json
{ "role": "admin" }
```

Flutter clients must never create, update, or derive this claim from a
Firestore document.

## Lifecycle

1. The trusted issuer verifies the Coach/Admin assignment.
2. It updates the Auth custom claim and, if needed, the matching
   `users/{uid}.role` UI metadata in the same administrative operation.
3. The user refreshes their ID token (or signs in again) before using
   Coach/Admin-only queries.
4. Role removal clears or replaces the custom claim and forces a token refresh.

The issuer must keep a durable audit record outside client-writable Firestore
documents. Production provisioning code and production claim changes are out
of scope for this repository package.
