# Backups, exports and rollback

Replace `<PROJECT>`, `<BUCKET>`, `<REGION>` and `<SITE>` with real values.
Nothing here is deployed by git: these are console / `gcloud` settings and
runbook commands. Status of each item in production: **to verify**.

## 1. One-time protection (do before first release)

1. Point-in-time recovery (7 days):

       gcloud firestore databases update --database="(default)" --enable-pitr --project=<PROJECT>

2. Scheduled backups:

       gcloud firestore backups schedules create --database="(default)" --recurrence=daily --retention=14d --project=<PROJECT>
       gcloud firestore backups schedules create --database="(default)" --recurrence=weekly --day-of-week=SUNDAY --retention=8w --project=<PROJECT>

3. Backup bucket for manual exports:

       gcloud storage buckets create gs://<PROJECT>-backups --location=<REGION> --uniform-bucket-level-access

4. Storage protection for uploads (prescriptions, reports, KYC):

       gcloud storage buckets update gs://<BUCKET> --versioning --soft-delete-duration=7d

   `<BUCKET>` is the project's default Storage bucket (see `firebase.json` /
   the Firebase console).

## 2. Before every release and before any migration `--apply`

    gcloud firestore export gs://<PROJECT>-backups/pre-release-$(date +%F) --project=<PROJECT>

Migration scripts in `functions/scripts/` should be dry-run first;
`migrate_general_physician.js` is dry-run by default and needs `--apply`. The
other scripts: confirm their default before running.

## 3. Restore

Never overwrite production wholesale.

- Point in time into a new database, then copy documents back selectively:

      gcloud firestore databases clone --source-database="projects/<PROJECT>/databases/(default)" --snapshot-time=<RFC3339> --destination-database=restore-1

- From a scheduled backup:

      gcloud firestore databases restore --source-backup=<BACKUP> --destination-database=restore-1

- From an export, only chosen collections:

      gcloud firestore import gs://<PROJECT>-backups/<folder> --collection-ids=payments,settlements

Restore drill: restore into a scratch database weekly at first, then at least
quarterly, and check `payments`, `wallet_ledger` and `settlements` counts.
Account deletion (`processAccountDeletion`) hard-deletes user data, so backups
are the only recovery path.

## 4. Release tagging and rollback

Tag every deployed batch on the exact commit that is deployed (functions, rules,
hosting and app builds all come from that tag):

    git tag release-YYYY-MM-DD
    git push origin release-YYYY-MM-DD

Rollback (use the previous tag):

- Functions (always a full deploy, see `functions/DEPLOY.md`):

      git checkout <prev-tag> -- functions
      firebase deploy --only functions

- Rules:

      git checkout <prev-tag> -- firestore.rules storage.rules
      firebase deploy --only firestore:rules,storage

- Hosting: `firebase hosting:rollback --site <SITE>` (or the console Rollback).
  Targets: `admin` and `web`.
- Mobile apps: halt the Play staged rollout / iOS phased release. Raise
  `app_config/versions.<app>.minVersion` only to push users to a fixed build,
  never to the broken one.

After a rollback by `git checkout <tag> -- <path>`, restore the working tree
(`git checkout <branch> -- <path>`) so the next commit does not revert the
rollback by accident.

## 5. Kill-switches (fast mitigation without a deploy)

| Switch | Where | Effect |
|---|---|---|
| Real payments | `app_config/payments.requirePayment` | Turns gateway payments on/off for new bookings |
| Payouts | `app_config/payouts` | Controls provider payout requests |
| Price check | `settlement_config/global.enforcePriceCheck` | Server price enforcement (fail-closed default) |
| Test credit | `testCreditEnabled` (with timestamp expiry) | Must stay off in production |
| Forced update | `app_config/versions` | Blocks old app versions |

Only Directors may write these through the admin panel. Record who flipped a
switch and when (the admin actions write `audit_logs`; direct `app_config` edits
are not audited yet).

## 6. Schedule summary

PITR always on; daily and weekly scheduled backups; export before each release;
restore drill at least quarterly; tag every release.
