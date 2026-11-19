#!/usr/bin/env node
// Stamps a release version into expath-pkg.xml, the version source for
// build.xml and build.cjs. Run by semantic-release in CI before the build;
// the change is not committed (see README "Releases").
"use strict";
{
    const fs = require("fs");

    const version = process.argv[2];
    if (!/^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/.test(version ?? "")) {
        console.error("usage: tools/set-version.cjs <semver>");
        process.exit(1);
    }

    const file = "expath-pkg.xml";
    const xml = fs.readFileSync(file, "utf8");
    const root = /(<package\b[^>]*?\bversion=")[^"]*(")/;
    if (!root.test(xml)) {
        console.error(`no version attribute on <package> in ${file}`);
        process.exit(1);
    }
    fs.writeFileSync(file, xml.replace(root, `$1${version}$2`));
    console.log(`${file}: version ${version}`);
}
