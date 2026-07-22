# hsg-jinks

TEI Publisher edition of FRUS (*Foreign Relations of the United States*), themed
with USWDS.

Profiles: `base10`, `docker`, `profile-theme-uswds`.

> Only the non-standard bits are documented here. Full background:
> [`doc/uswds-profile-integration.md`](doc/uswds-profile-integration.md).

## Workflow

- **All changes go through a branch + PR targeting `main`** — in this repo
  and in `profile-theme-uswds`. No direct commits to either `main`.
- **Check a work package's assignee in OpenProject before implementing it.**
  If we decide to pick one up, assign it to the person actually doing the
  work, not the AI assistant — ask if it's unclear who that is.
- **Reference work packages as `OP#<id>`** in PR titles and descriptions —
  that is the token OpenProject's GitHub integration scans for, and how a PR
  gets linked to its work package. A bare `#1217` means nothing to it (GitHub
  reads that as an issue in *this* repo), and a work package URL
  is a link for humans, not a reference. Example title:

  ```
  fix: content band on sidebar pages respects the page width (OP#1217)
  ```

  Linking is not closing: move the work package yourself when the PR merges.
  This board's workflow only permits New, In progress, Closed, On hold and
  Rejected — **Closed is how it marks work done**.

## The devcontainer runs the generator

Unlike a stock TEI Publisher devcontainer (runtime library only), this one hosts
**Jinks itself**: `.devcontainer/Dockerfile.dev` clones `jinks` from `main`,
builds it, and copies in the USWDS profile xar. The `.devcontainer/` files are
therefore **hand-edited away from the generated `docker` profile** — do not let a
sync overwrite them.

`-Xss16m` is set in `JAVA_OPTS` there to work around a Jinks generator
StackOverflow on large profiles (`generator:filter-conflicts` recurses per file;
USWDS ships ~2600). Remove when Jinks fixes it.

### Pinned baseline

Everything except `jinks` itself is pinned to a release, in
`devcontainer.json` → `build.args` (the `Dockerfile.dev` `ARG` defaults mirror
them):

| package | version | note |
|---|---|---|
| jinks-templates | 1.4.2 | pinned to the public-repo release. Building it from `main` — which this container used to do — always self-identifies as **1.0.0**, because semantic-release stamps the version only when publishing |
| roaster | 1.12.2 | 1.11.0 answers an empty `POST /api/login` with 401 instead of clearing the session, which fails a generated test (#1216) |
| tei-publisher-lib | 6.1.0 | |
| eXist | 6.4.0 | |

After changing any of them, rebuild the container and confirm with
`xst package list --versions` — `xst package install` has been seen reporting
`updated to X@<new>` while the deployed collection stayed on the old version.

## Remapping ports

The container publishes eXist on the standard ports, 8080/8443. If those are
already taken on your machine (e.g. by other eXist instances), remap them
**on the host side only** in `.devcontainer/devcontainer.json` — which ports
you pick is up to you (keep the change local, don't commit it):

```jsonc
"appPort": [ "8091:8080", "8555:8443" ]
```

Rules:

- **Change only the left (host) side.** eXist must keep listening on 8080
  *inside* the container — `.devcontainer/init.sh` hardcodes `localhost:8080`
  and breaks if the internal port moves.
- **Use `appPort`, not `forwardPorts`**: `appPort` publishes deterministically
  via docker, whereas `forwardPorts` lets VS Code silently pick an arbitrary
  free port.
- **`.existdb.json` stays on 8080** (it is used in-container) — leave it.
- Rebuild the container for the change to take effect.

Everything that talks to eXist **from the host** must then use your remapped
port instead of the 8080 used in the examples throughout this README:

- browser: `http://localhost:8080/exist/apps/hsg-jinks`
- `jinks` CLI: `--server http://localhost:8080/exist/apps/jinks`
- `xst`: `EXISTDB_SERVER=http://localhost:8080/exist`
- Cypress: `--config baseUrl=http://localhost:8080/exist/apps/hsg-jinks`

## Refreshing the USWDS profile

`profile-theme-uswds` is **private and unreleased**, so `docker.externalXar`
can't reach it — it is built from the sibling checkout:

```sh
cd ../profile-theme-uswds && ant
rm ../hsg-jinks/.devcontainer/profile-theme-uswds-*.xar          # only one may be there:
cp build/profile-theme-uswds-*.xar ../hsg-jinks/.devcontainer/   # Dockerfile COPYs by glob
export EXISTDB_SERVER=http://localhost:8080/exist EXISTDB_USER=admin EXISTDB_PASS=""
xst package install --force build/profile-theme-uswds-*.xar
printf 'n\n' | jinks update hsg-jinks --server http://localhost:8080/exist/apps/jinks
```

(Pipe `n`: `jinks update` prompts on conflicts and dies without a TTY. The
`build.xml` / `expath-pkg.xml` conflicts are app-specific — keep ours.)

## Data

Not installed by the devcontainer. One sample volume (`frus1981-88v05`) from the
sibling repo `../hsg-jinks-data` → `/db/apps/frus-data-jinks`:

```sh
cd ../hsg-jinks-data && ant
xst package install --force build/frus-data-jinks-*.xar   # EXISTDB_* as above
```

Lives in the running container only; reinstall after a rebuild.

## Sync-down: files to exclude

`xst get` the app, then **copy, never mirror** (a mirror deletes `.existdb.json`,
`package-lock.json`, `.devcontainer/python-api.sh`, which aren't in the DB).

The DB holds stale copies of these that will overwrite newer local versions —
**exclude them and `git diff` after**:

- `.devcontainer/` — the hand-edits above
- `README.md`, `doc/` — this file and the doc
- `.gitignore` — DB copy predates the `.devcontainer/*.xar` rule
- `test/cypress/support/` — emptied by the profile once; `jinks update` won't restore

Also note: Jinks' `.jinks.json` never prunes removed files — clean stale entries
by hand.

## Tools

- `tools/inspect-page.xq` — fetch a deployed page server-side, assert on rendered
  markup by CSS class (excluded from the app build; run with `xst`, see header).
- `test/cypress/e2e/gui/breadcrumb.cy.js` — run against the container with
  `cypress run --config baseUrl=http://localhost:8080/exist/apps/hsg-jinks`.
