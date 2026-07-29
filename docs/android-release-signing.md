# Android release signing

Release builds require an untracked `android/key.properties` file. Copy
`android/key.properties.example` and replace every placeholder locally. Keep
the keystore outside the repository, retain at least two secure backups, and
never put keystore passwords in Git, chat, or build logs.

Verify a release artifact after signing:

```text
apksigner verify --print-certs <apk-path>
```

Add the resulting SHA-1 and SHA-256 fingerprints to the matching Firebase
Android app in Firebase Console before distributing a release. When Play App
Signing is enabled, retain and register both the upload certificate and the
Play app-signing certificate as appropriate.
