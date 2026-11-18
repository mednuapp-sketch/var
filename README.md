# MedNu

## Firestore / Storage rules tests

The rules test suite lives in `firestore-tests/` (see `firestore-tests/README.md`).

It needs Java for the Firebase emulators. Install (examples, run yourself):
`winget install EclipseAdoptium.Temurin.17.JDK` or `choco install temurin17`, then
check `java -version` in a new terminal.

Run (from the repo root, after `cd firestore-tests && npm install`):

```
firebase emulators:exec --only firestore,storage --project mednu-rules-test "npm --prefix firestore-tests test"
```
