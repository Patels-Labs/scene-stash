#!/usr/bin/env node
// Imports CloudKit/schema.ckdb into the Development environment, then reads it back to check every field
// landed. Stands in for `xcrun cktool import-schema`, which needs Xcode. Afterwards, Deploy Schema Changes
// in CloudKit Console copies Development to Production; Apple only allows that from the console.
//
//   node scripts/cloudkit-import.mjs          validate, import, verify
//   node scripts/cloudkit-import.mjs export   print the Development schema
//
// Needs a CloudKit management token (CloudKit Console > Settings > Tokens) in ~/.config/scenestash/cloudkit-token.
import { execSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const teamId = "XS64NY3897", containerId = "iCloud.com.heetpatel.scenestash";

// Apple's CKTool JS, installed outside the repo on first run so there's no package.json to keep here.
const cache = join(homedir(), ".cache/scenestash/cktool");
if (!existsSync(join(cache, "node_modules/@apple/cktool.database"))) {
    mkdirSync(cache, { recursive: true });
    execSync("npm install --silent --prefix . @apple/cktool.database@1.3.2 @apple/cktool.target.nodejs@1.3.2", { cwd: cache, stdio: "inherit" });
}
const require = createRequire(join(cache, "index.js"));
const { PromisesApi, CKEnvironment } = require("@apple/cktool.database");
const { createConfiguration, File } = require("@apple/cktool.target.nodejs");

const token = readFileSync(join(homedir(), ".config/scenestash/cloudkit-token"), "utf8").trim();
const api = new PromisesApi({ configuration: createConfiguration(), security: { ManagementTokenAuth: token } });
// Development only: Production changes solely through Deploy Schema Changes.
const target = { teamId, containerId, environment: CKEnvironment.DEVELOPMENT };
const development = async () => await (await api.exportSchema(target)).result.text();

/// "CD_Tracked.CD_name STRING" for every field, so two schemas compare whatever their spacing and order.
function fields(schema) {
    const out = new Set();
    let type = null;
    for (const raw of schema.split("\n")) {
        const line = raw.replace(/\/\/.*/, "").trim();
        const open = line.match(/^RECORD TYPE "?([\w.]+)"? \($/);
        if (open) type = open[1];
        else if (line.startsWith(")")) type = null;
        else if (type && line && !line.startsWith("GRANT")) out.add(`${type}.${line.replace(/,$/, "").replace(/"/g, "").split(/\s+/).slice(0, 2).join(" ")}`);
    }
    return out;
}

try {
    if (process.argv[2] === "export") {
        console.log(await development());
    } else {
        const path = join(dirname(fileURLToPath(import.meta.url)), "../CloudKit/schema.ckdb");
        const text = readFileSync(path, "utf8");
        const file = () => new File([text], "schema.ckdb");
        const wanted = fields(text), before = fields(await development());
        const adding = [...wanted].filter((f) => !before.has(f));
        console.log(adding.length ? `Adding ${adding.length} to Development:\n  ${adding.join("\n  ")}` : "Development already has every field.");
        const check = (await api.validateSchema({ ...target, file: file() })).result;
        if (check.isValid === false) throw new Error(`Schema isn't valid: ${JSON.stringify(check)}`);
        await api.importSchema({ ...target, file: file() });
        const after = fields(await development());
        const missing = [...wanted].filter((f) => !after.has(f));
        if (missing.length) throw new Error(`Imported, but Development is missing:\n  ${missing.join("\n  ")}`);
        console.log(`Imported. Development has all ${wanted.size} fields. Now Deploy Schema Changes in CloudKit Console.`);
    }
} catch (error) {
    console.error(error?.message ?? error, JSON.stringify(error?.errors ?? error?.result ?? ""));
    process.exit(1);
}
