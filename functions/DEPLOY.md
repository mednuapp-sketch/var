# Deploying Cloud Functions

Always deploy the whole codebase:

    firebase deploy --only functions

Never use a hand-kept `--only functions:a,functions:b` list. Old deploy lists
drifted (96 names vs 156 exports) and silently skipped money-critical functions.
`deploy_list.txt` and `retry_list.txt` are git-ignored scratch files and must
not be relied on.

## Checking what is deployed

    firebase functions:list

Compare with `functions/EXPORTS.txt` (sorted list of every export of
`index.js`, the `__testing` helper excluded). Regenerate it after adding,
removing or renaming a function and commit it, so refactors can be diffed:

    cd functions
    GCLOUD_PROJECT=demo-check node -e "console.log(Object.keys(require('./index.js')).filter(k=>!k.startsWith('__')).sort().join('\n'))" > EXPORTS.txt

## Removing functions

Delete a deployed function only if it no longer exists in `index.js` (it shows
up in `firebase functions:list` but not in `EXPORTS.txt`):

    firebase functions:delete <name> --region <region>

A full deploy also offers to delete such orphans; answer deliberately, one by
one. Never delete a function that is still exported.

## Before and after

- Run `node functions/test/run_all.js` first.
- Tag the deployed commit (see docs/BACKUP_AND_ROLLBACK.md).
- Rollback = check out the previous tag and deploy again.
