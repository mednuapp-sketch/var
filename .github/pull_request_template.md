## What and why

<!-- One or two sentences. Link the issue / checklist item. -->

## Test plan

- [ ] `node functions/test/run_all.js` passes
- [ ] Rules suite passes if `firestore.rules` / `storage.rules` changed
- [ ] `flutter analyze` and `flutter test` pass in every touched app
- [ ] Bug fix: a test that failed before and passes now is included

## Release checklist (only for release PRs)

- [ ] CI green on this branch
- [ ] Pre-release Firestore export taken (see docs/BACKUP_AND_ROLLBACK.md)
- [ ] Tag created on the exact commit being deployed: `git tag release-YYYY-MM-DD`
- [ ] Deploy order followed (see GO_LIVE_CHECKLIST.md): rules, functions, hosting, then app builds
- [ ] Kill-switches checked: `app_config/payments`, `app_config/payouts`, `settlement_config/global.enforcePriceCheck`, `testCreditEnabled` is OFF in production
- [ ] Previous tag noted for rollback
- [ ] Smoke test on a real device after deploy
