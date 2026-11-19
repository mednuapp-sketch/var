# MedNu

MedNu is a healthcare platform: a patient app (`mednu/`), a partner app for
doctors, labs, pharmacies, ambulances, nurses, therapists, dieticians and
hospitals (`mednu_doctor/`), a web target (`mednu_web/`), an admin panel
(`mednu-admin/`), Cloud Functions (`functions/`) and Firestore/Storage rules.

## Documentation

- [Architecture, money flows and debugging guide](docs/ARCHITECTURE.md)
- [Data model](docs/DATA_MODEL.md)
- [Backups, restore and rollback](docs/BACKUP_AND_ROLLBACK.md)
- [Deploying functions](functions/DEPLOY.md)
- [Go-live checklist](GO_LIVE_CHECKLIST.md), [client handover](HANDOVER_CLIENT.md)

## Tests

- Server logic and helpers: `node functions/test/run_all.js` (Node 20+, no install needed)
- Flutter: `flutter test` inside `mednu/` or `mednu_doctor/`
- Rules: see below. CI runs all of these (`.github/workflows/ci.yml`).

## Firestore / Storage rules tests

The rules test suite lives in `firestore-tests/` (see `firestore-tests/README.md`).

It needs Java for the Firebase emulators. Install (examples, run yourself):
`winget install EclipseAdoptium.Temurin.17.JDK` or `choco install temurin17`, then
check `java -version` in a new terminal.

Run (from the repo root, after `cd firestore-tests && npm install`):

```
firebase emulators:exec --only firestore,storage --project mednu-rules-test "npm --prefix firestore-tests test"
```
