# Firestore role claim provisioning contract

Firestore authorization treats Firebase Auth custom claims as the only role
source. The canonical claim is a map so a user can safely hold multiple roles:

```json
{ "roles": { "student": true, "coach": true, "admin": true } }
```

Only roles actually held are set to `true`. The scalar `request.auth.token.role`
remains a temporary V1 compatibility fallback. The `users/{uid}.role` field is
UI metadata and must not grant Firestore privileges.

## Trusted issuer

Only a trusted server-side administrative process (Firebase Admin SDK, a
protected Cloud Function, or an equivalent controlled operator workflow) may
set or remove the Firebase Auth custom claim map:

```json
{ "roles": { "coach": true } }
```

Flutter clients must never create, update, or derive this claim from a
Firestore document.

## Lifecycle

1. The trusted issuer verifies the Coach/Admin assignment.
2. It updates only managed entries of the Auth `roles` map and, if needed, the
   matching `users/{uid}.role` UI metadata label in the same administrative
   operation. The metadata label is never an authorization fallback.
3. The user refreshes their ID token (or signs in again) before using
   Coach/Admin-only queries.
4. Role removal clears or replaces the custom claim and forces a token refresh.

The issuer must keep a durable audit record outside client-writable Firestore
documents. Use `tool/manage_custom_claim_roles.js` for controlled provisioning
and revocation; it preserves unrelated claims and migrates managed scalar
claims to the canonical map. Its production and token-refresh procedure is
documented in `docs/custom-claim-role-management.md`.
