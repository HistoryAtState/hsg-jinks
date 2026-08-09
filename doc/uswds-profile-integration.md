# Incorporating the external `profile-theme-uswds` profile

Working notes, 2026-07-14. Everything below was verified against the sources
cited, not assumed.

## TL;DR

The USWDS theme is an **external jinks profile**, distributed as an eXist `.xar`.
Using it means running a jinks *generator* alongside the app and regenerating.

**Status: done.** The theme is applied, verified in the database, and synced back
into this repo.

## How jinks resolves profiles (the key mechanism)

`jinks/modules/generator.xql:32-42`:

```xquery
declare variable $generator:PROFILES_ROOT := $config:app-root || "/profiles";

declare function generator:profile-path($name as xs:string) {
    let $internalPath := $generator:PROFILES_ROOT || "/" || $name
    return
        if (xmldb:collection-available($internalPath)) then
            $internalPath
        else
            for $collection in xmldb:get-child-collections(repo:get-root())
            where $collection = $name
            return
                repo:get-root() || "/" || $collection
};
```

A name in `extends` resolves in two steps:

1. **Bundled profile** — `/db/apps/jinks/profiles/<name>` (`base10`, `docker`, …).
2. **External profile** — otherwise, any child collection of `/db/apps` whose
   *collection name* equals `<name>`.

Branch 2 is how an installed `.xar` profile is found. It is a plain
**collection-name string match under `/db/apps`** — not a package URI, not an
expath abbrev.

`profile-theme-uswds` deploys to `/db/apps/profile-theme-uswds` (its `repo.xml`
`<target>`), so the string in `extends` is exactly `"profile-theme-uswds"`.

Discovery: `jinks/modules/api.xql:210-229` scans `/db/apps` and treats any
collection whose `config.json` has a `type` key as an installed profile. There is
no registration API and no profile registry — installing a profile is just
deploying a `.xar`.

External-profile support was added in jinks commit `e99cb7e1`. It is **not
documented** — the jinks README (line 22) still claims profiles only live under
`profiles/`, and the USWDS README's "How to use" section is literally `**TODO**`.

### `extends` vs `depends`

- `extends` (**app** config) is the only thing the generator reads. Resolved
  recursively, deep-merged, and **order matters** — later profiles overwrite
  earlier ones.
- `depends` (**profile** config) is *never read server-side*
  (`grep -rn "depends" jinks/modules/` → nothing). It is used only by the browser
  UI to auto-tick transitive deps. Hand-written configs must list everything.

### Array merge semantics

`jinks-templates/content/templates.xqm:824-827`: arrays are **unioned
(deduplicated), not replaced**. So our `styles: ["resources/css/hsg-theme.css"]`
is *appended after* the USWDS stylesheets rather than clobbering them. Confirmed
in the expanded config:

```
resources/css/layout.css
resources/css/jinks-variables.css
resources/css/components.css
resources/css/hsg-theme.css     <- ours, last
```

### Palettes

Palette handling used to come from `theme-base10/setup.xql`, which we dropped.
USWDS brings its own — `profile-theme-uswds/setup.xql:16-47` is an
`%generator:after-write` hook that reads `$context?theme?colors?palette`
(default `neutral`) and **generates** `resources/css/components.css` by
concatenating the active palette CSS into it.

**So the palette is set purely via `theme.colors.palette`.** The USWDS README's
advice to list `palette-navy.css` in `styles` applies to their standalone vite
dev setup, *not* to a jinks-generated app.

## The canonical example: the USWDS demo app

`profile-theme-uswds/dev/jinks-uswds-demo-profile.json` (committed version):

```json
"theme": {},
"extends": [
    "base10", "registers", "serafin", "landing-page",
    "edition-navigation", "timeline", "ci", "docker",
    "profile-theme-uswds"
]
```

Two things copied from it:

- **`theme-base10` is absent.** USWDS *replaces* it (both are `type: "theme"`,
  both `depends: ["base10"]`).
- **`profile-theme-uswds` is last**, after `docker`. Order matters.

⚠️ The working copy of that demo file has uncommitted local edits containing a
typo: `"colores"` instead of `"colors"`, so its palette setting is silently
ignored and the demo falls back to `neutral`.

## Changes made to this repo

### `config.json`

Was **invalid JSON** (stray `}` at line 30) — jinks parses this file, so nothing
could have regenerated. Fixed, plus:

```diff
- "extends": ["base10", "theme-base10", "docker"],
+ "extends": ["base10", "docker", "profile-theme-uswds"],
- "theme": { "colors": { "palette": "blue" } }
+ "theme": { "colors": { "palette": "navy" } }
```

`"blue"` was a `theme-base10` palette and does not exist in USWDS, which ships
only `neutral` and `navy`.

Note `"$schema": "../jinks/schema/jinks.json"` is a dangling relative path.
Harmless, but wrong.

### `.devcontainer/`

The devcontainer was **an app runtime, not a generator**: it installs
`jinks-templates` (the runtime templating *library*) but never the **jinks
generator**. That is by design — jinks' `docker` profile only ever autodeploys
`jinks-templates.xar`. So the app could not be regenerated inside it.

The generated devcontainer was also **stale**, in ways that would have blocked
jinks outright:

| Problem | Fix |
|---|---|
| `PUBLISHER_LIB_VERSION=6.0.2`, but jinks requires `tei-publisher-lib` **semver-min 6.1** | bumped to `6.1.0` |
| `JINKS_TEMPLATES_VERSION=1.2.0`, jinks requires **min 1.4.1** (cosmetic — the Dockerfile clones `main` and ignores the arg) | bumped to `1.4.1` |
| `devcontainer.json` passed `JWT_VERSION` + `CRYPTO_VERSION`, but `Dockerfile.dev` **never declared or used them** — no jwt, no crypto in the image. jinks requires `jwt semver 2`. | added both ARGs + autodeploy lines |
| Node 20 (EOL April 2026) | bumped to Node 24 |

Then added jinks (cloned from `main`) and the USWDS profile.

**Why not `docker.externalXar`** (the profile's supported mechanism, which *does*
reach the devcontainer — `Dockerfile.dev.tpl:94-109`)?

- We track jinks **`main`**, not the v10.0.0 release.
- **`profile-theme-uswds` is a PRIVATE repo with no releases** — there is no URL
  to fetch, and an anonymous `git clone` in the image fails with exit 128.

So the USWDS xar is built from the local checkout and `COPY`d in from the build
context. Refresh it with:

```sh
cd ~/customers/eeditiones/profile-theme-uswds && ant
cp build/profile-theme-uswds-*.xar <this repo>/.devcontainer/
```

The xar is gitignored (`.devcontainer/*.xar`) — it is a build artifact.

`externalXar` becomes the right answer only once both ship releases.

The `zz-`/`zzz-` autodeploy prefixes exist because eXist autodeploys
**alphabetically**, and these must land after their dependencies.

### `.tool-versions`

`nodejs 20.19.6` → **`24.10.0`**. The `jinks` CLI (v2.0.2) is installed only under
24.10.0, so the asdf shim failed with `No version is set for command jinks`.
Node 20 went EOL in April 2026; jinks-cli needs ≥ 20; Cypress 15 supports 24.

## ⚠️ These are hand-edits to generated files

`.devcontainer/Dockerfile.dev` and `devcontainer.json` are **jinks-generated**
(tracked with sha256 in `.jinks.json`). We edited them anyway, because there is
no way to inject a *source-built* / *private* package via the `docker` profile's
config.

**`jinks update` overwrites them in the database** — the `.jinks.json` checksum
does **not** protect them. Verified: after regeneration the DB copy had no
`-Xss16m`, no jinks clone, no USWDS `COPY`, no `setup_24.x`.

**Therefore: never sync `.devcontainer/` down from the database.** Doing so would
destroy the setup that makes regeneration possible at all.

## Ports

The container publishes eXist on the standard ports (`appPort: ["8080:8080",
"8443:8443"]` in `.devcontainer/devcontainer.json`). If those are taken on your
host by other eXist instances, remap the **host (left) side only** and keep the
change local — see "Remapping ports" in the README.

**Why not `docker.ports.http` in `config.json`?** That is the profile's
config-driven knob and *would* survive regeneration — but it moves eXist's
**internal** jetty port, and `profiles/docker/.devcontainer/init.tpl.sh`
**hardcodes `http://localhost:8080`** rather than templating it. The app would
never deploy. Upstream bug; keeping the internal port at 8080 sidesteps it.

`appPort` rather than `forwardPorts` because the latter lets VS Code silently
remap to an arbitrary free port.

| Context | Port |
|---|---|
| Inside the container (`existdb-vscode`, `init.sh`) | always **8080** |
| From the host (`jinks`, `xst`, `curl`, browser) | the host side of `appPort` (**8080** unless remapped) |

`.existdb.json` therefore stays on **8080** — do not "fix" it.

## Build + regenerate (no VS Code needed)

```sh
npx @devcontainers/cli up --workspace-folder .
jinks update hsg-jinks --server http://localhost:8080/exist/apps/jinks
```

⚠️ `npx @devcontainers/cli up` **exits 0 even when the docker build fails.** Do
not trust its exit code — grep the output for `ERROR:` / `failed to solve`.

Undocumented alternative: `init.tpl.sh` supports a `docker.features.cli` flag that
`npm install -g @teipublisher/jinks-cli` *inside* the container, letting you run
`jinks` against plain `localhost:8080` with no `--server`.

## 🐛 jinks bug: StackOverflowError on large profiles

The first `jinks update` died with HTTP 500 `java.lang.StackOverflowError` from
`POST /api/generator`.

Cause — `generator:filter-conflicts` (`jinks/modules/generator.xql:133-149`) is
**non-tail-recursive with one stack frame per file written**, and runs a
`filter()` over the whole remaining tail at each level (O(n²)).
`profile-theme-uswds` copies ~2600 resource files, so it recurses thousands deep
and blows the default JVM thread stack.

**Upstream jinks bug, not a config error** — any profile with a large file count
hits it. Worth reporting; the fix is to make the function iterative.

**Workaround** (`.devcontainer/Dockerfile.dev`): `-Xss16m` in `JAVA_OPTS`. Remove
once jinks fixes the recursion.

## ⚠️ The profile leaks its own repo files into the app

`profile-theme-uswds` declares only
`skipSource: ["repo.xml", "expath-pkg.xml", "build.xml"]`, so the rest of its repo
is copied into every app that extends it. Landed in `/db/apps/hsg-jinks`:

- `.husky/` (17 files — git hooks)
- `TODO.md`, `cypress.json`, `cypress.config.js`, `.prettierrc.json`

(`package.json` was checked and is **ours** — not clobbered.)

Upstream fix: add these to the profile's `skipSource`. Until then they must be
excluded from the sync.

## Syncing the database back into git

`jinks update` writes to `/db/apps/hsg-jinks`, **not** to this checkout. Pull it
back with `xst` (the `existdb-vscode` extension does the same job from inside the
container):

```sh
export EXISTDB_SERVER=http://localhost:8080/exist EXISTDB_USER=admin EXISTDB_PASS=""
xst get /db/apps/hsg-jinks <staging-dir>
```

Then **copy, never mirror** into the repo, excluding:

- `.devcontainer/` — would destroy our hand-edits (see above)
- `README.md`, `doc/` — this doc and the operational summary (built into the xar)
- `.husky/`, `TODO.md`, `cypress.json`, `cypress.config.js`, `.prettierrc.json` —
  profile leakage
- `.claude/` — swept into the xar from the workspace
- gitignored vendor dirs (`resources/lib/`, `resources/css/prismjs/`, …)

⚠️ **Never mirror/`--delete`.** These files are tracked in git but absent from the
database, and a mirror would delete them:

- `.existdb.json`, `.gitignore`, `package-lock.json`, `.devcontainer/python-api.sh`

⚠️ **The DB also contains a stale copy of this repo's own files** (they were built
into the app xar). A sync will happily overwrite newer local files with older
snapshots. Known victims, each hit at least once — **exclude all of them** and
re-verify after every sync:

- `doc/uswds-profile-integration.md` — this document (built into the xar)
- `README.md` — jinks-managed (regenerates to the base10 stub), but holds the
  operational summary; exclude it or lose the findings
- `.gitignore` — the DB copy predates the `.devcontainer/*.xar` rule; losing it
  would commit the 15 MB profile xar
- `test/cypress/support/commands.js` (326 lines) / `e2e.js` — the DB copies were
  emptied by the profile's now-removed stubs and `jinks update` never restores
  them; keep the repo versions

Always `git diff` these after a sync.

### What the sync brought in

~30 MB of USWDS assets: 2,440 SVG icons (22 MB), 144 font files (7.7 MB),
`palette-navy.css`, `layout.css`, `styles.css`, the sass sources, and templates
(`uswds-blocks.html`, `index.html`, `identifier.html`, `bottom.html`). These must
be committed — the xar is built from the repo, so the deployed app breaks without
them.

`package.json` picked up `@teipublisher/pb-components: ^3.0.0-next-4.15` from the
profile's `script.webcomponents`. It is a prerelease pin, but the caret still
admits 3.0.5.

## Verified result

In `/db/apps/hsg-jinks` after regeneration:

| Check | Result |
|---|---|
| `extends` | `["base10", "docker", "profile-theme-uswds"]` ✅ |
| palette | `navy` ✅ |
| `components.css` | 1,229,348 bytes, 143 `.usa-banner` rules, navy tokens (`#1a4480`/`#162e51`) ✅ |
| `templates/uswds-blocks.html` | present ✅ |
| `resources/css/hsg-theme.css` | present, layered last ✅ |

Visually confirmed in the browser on the host port.

## Data

The path splits into two configuration values (PR #32 review), never one
hardcoded string: the **data directory** (`config.json` `"data"` →
`$config:data-root`, `/db/apps/frus-data-jinks/data`) and the **FRUS
volumes collection inside it** (`config.json` `"data-default"` →
`$config:frus-volumes`, `frus-v2-data`; mirrored for compiled ODD
transforms as `$global:frus-volumes` in `modules/odd-global.xqm`).
`$config:data-default` is their join. The data is supplied by the sibling repo
**`../../hsg-jinks-data`** (git `HistoryAtState/hsg-jinks-data`), an eXist data
package deploying to `/db/apps/frus-data-jinks`.

It is a slimmed data-model sample, not production data: the most recent commit
("remove-old-samples") trimmed it to a single FRUS publication —
`frus1981-88v05` ("Foreign Relations of the United States, 1981–1988, Volume V,
Soviet Union, March 1985–October 1986"), 361 TEI XML docs — plus a
`frus-tei-guidelines-resources` apparatus (`frus.odd`, `frus.rnc`, encoding
desc, placeholders, Author authority project). (Volumes now live under
`data/frus-v2-data/`; both collections were renamed from the earlier
`Publications` / `Resources` when the full legacy corpus landed.)

The devcontainer does **not** install data automatically (it only deploys the
app + jinks + theme profile). Load it manually:

```sh
cd ../../hsg-jinks-data && ant                                # -> build/frus-data-jinks-*.xar
export EXISTDB_SERVER=http://localhost:8080/exist EXISTDB_USER=admin EXISTDB_PASS=""
xst package install local build/frus-data-jinks-*.xar        # -> /db/apps/frus-data-jinks
```

Verified serving: `GET /apps/hsg-jinks/api/collection?id=Publications` renders
the volume title.

## Tooling notes

- `xst` was broken under nodejs 24.10.0: the npm global link `@existdb/xst`
  pointed at `~/projects/existdb/xst`, which is now a **git worktree
  container** (`main`, `119`, `224`, …). Repointed the symlink to `.../xst/main`.
- `xst run -f query.xq` — a bare argument is treated as a query *string*, not a
  path. Serialize maps explicitly (`map{"method":"json"}`) or you get no output.

## Open questions

- Does `resources/css/hsg-theme.css` still make sense on top of USWDS? It was
  written against theme-base10/pico and may fight the USWDS cascade.
- USWDS brings its own layout (`fixed-layout`, before/after side panels, 84rem).
  The recent commit "added left and right side panel and custom breadcrumb
  function" may now be redundant or conflicting.
- `.jinks.json` / `.jinks-versions.json` churn on every regeneration.
