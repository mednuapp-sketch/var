"use strict";
// Runs the server-logic suite: node functions/test/run_all.js
const { spawnSync } = require("child_process");
const path = require("path");
const fs = require("fs");
// Plain-script unit tests in test/unit/*.test.js: each runs as its own process, exit code != 0 means failure.
const unitDir = path.join(__dirname, "unit");
const unitFiles = fs.existsSync(unitDir) ? fs.readdirSync(unitDir).filter((f) => f.endsWith(".test.js")).sort().map((f) => path.join(unitDir, f)) : [];
const r = spawnSync(process.execPath, ["--test", path.join(__dirname, "money.test.js"), path.join(__dirname, "payouts.test.js"), path.join(__dirname, "ratelimit.test.js"), ...unitFiles], { stdio: "inherit", env: { ...process.env, MEDNU_TEST: "1", GCLOUD_PROJECT: "demo-check" } });
process.exit(r.status === null ? 1 : r.status);
