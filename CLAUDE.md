# hsg-jinks

Jinks-generated TEI Publisher application (`abbrev: hsg-jinks`) for the Office of
the Historian. This is a **Mode B** repo: `expath-pkg.xml` + `config.json` at the
root, no `profiles/`. Edit `config.json` and regenerate via `jinks update` rather
than hand-editing generated files (see the jinks skills for the full workflow).

This repo expects several companion repos as flat siblings in one parent
directory — `jinks`, `jinks-templates`, `profile-theme-uswds`, `hsg-jinks-data`,
`hsg-project` — see README "Workspace layout" for the full picture and what
each one is for.

## Reference implementation (old app)

The pre-v10 TEI Publisher application this project replaces lives outside this
repo, in a sibling checkout of the full HSG source tree:

- Source root: `../../hsg-project` (its own git repo — do not copy it in here)
- Application code: `../../hsg-project/repos/hsg-shell`

`hsg-shell` is the old, hand-built app (custom `controller.xql`, `modules/`,
`templates/`, `pages/`, `transform/`, styling, `cantaloupe.properties`, etc.). Use
it as the source of truth for **behavior and content to port**, not as code to
copy wholesale — most of its plumbing is superseded by Jinks profiles
(`base10`, `docker`, `profile-theme-uswds`) here. When a feature is missing or a
page renders differently in `hsg-jinks`, check how `hsg-shell` implemented it
before re-deriving it from scratch.

If migrating a specific piece of it, the **update-old-app** skill's model
applies: keep `hsg-shell` intact for comparison, port logic into this repo's
custom extension points (`modules/`, `api`, `styles`, `templating.modules` in
`config.json`) rather than overwriting Jinks-managed files.

See `doc/` for in-progress migration/feature planning notes
(`epic-518-rendering-plan.md`, `uswds-profile-integration.md`).

## Parallel worktrees & the read-only mirror

- Work happens in parallel git worktrees (flat siblings, `../<slug>`),
  each with its own devcontainer on its own host port — created via
  `tools/new-worktree.sh` (README "Parallel worktrees"). This checkout's own
  instance is defined by `./.env` (`EXISTDB_SERVER`) — trust it, never fall
  back to defaults.
- **Host port 8080 is the read-only hsg-shell reference mirror** — guest reads
  only. Never install packages, run jinks, or REST-write against it; a
  PreToolUse hook blocks write-shaped commands targeting it.
- Shared machine-local state (OP_TOKEN, port registry, baseline profile xar)
  lives in `~/.config/hsg/`. For OpenProject writes:
  `source ~/.config/hsg/secrets.env` first — never inline the token.

## Measuring rendered layout

When a visual/layout question needs an actual browser (not just reading CSS),
use **Cypress** (`test/cypress/`, already configured) rather than assuming
browser-automation tooling is available. Point it at the worktree's own
instance: `CYPRESS_BASE_URL=$(worktree port) npx cypress run --spec <path>`.
For one-off measurements (not a permanent regression test), write a throwaway
spec under `test/cypress/e2e/gui/`, run it, read the result, then delete it.

## Prefer XQuery over Python for one-off scripting

When writing throwaway scripts to inspect, transform, or validate data in this
repo (checking a data collection, reshaping XML, scripting a query against
eXist), reach for XQuery first — it runs in the same environment as the app
and against the live database directly, rather than shelling out to a
different language runtime. Only fall back to Python (or another scripting
language) when the same task genuinely can't be expressed in XQuery, or
doesn't involve XML/the database at all (e.g. validating plain JSON syntax).

## HTML comments in templates: never use "--" inside them

XML forbids a literal `--` anywhere inside a `<!-- ... -->` comment (only at
the closing `-->`). This repo's template files are XML, so a comment written
in ordinary prose style — using `--` as a dash, the way this file and commit
messages do — breaks the whole template with a cryptic `XPST0003 expecting
end of XML comment` error at deploy time, not at write time. It has caused
repeat, easy-to-miss bugs. Use `;`, `—` (em dash), or a full stop instead of
`--` inside any `<!-- -->` block. Before deploying a new or edited template
comment, a quick check across changed files:
`grep -rn -- '--' templates/**/*.html | grep -v 'usa-\|context-path'` (or
review each `<!-- -->` block by eye) catches it before the round trip.
