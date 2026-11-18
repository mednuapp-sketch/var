"use strict";
// Runs the server-logic suite: node functions/test/run_all.js
const { spawnSync } = require("child_process");
const path = require("path");
const r = spawnSync(process.execPath, ["--test", path.join(__dirname, "money.test.js"), path.join(__dirname, "payouts.test.js")], { stdio: "inherit", env: { ...process.env, MEDNU_TEST: "1", GCLOUD_PROJECT: "demo-check" } });
process.exit(r.status === null ? 1 : r.status);
