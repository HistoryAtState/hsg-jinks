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
- **Host port 8080 is the read-only hsg-shell reference mirror. Never
  install, deploy, or write anything to it, ever** — no `xst package
  install`, no `ant`-then-deploy, no `jinks update`, no REST writes. Read-only
  probing (checking whether a data collection exists, sampling a record) is
  fine. A PreToolUse hook (`.claude/hooks/protect-reference-mirror.sh`,
  wired up in `.claude/settings.json`) blocks write-shaped Bash commands
  targeting it as a backstop, but treat that as defense-in-depth, not a
  substitute for checking which port a command targets before running it.
- **The deploy target is this worktree's own devcontainer**, not a fixed
  port — check `./.env` (`EXISTDB_SERVER`) rather than assuming 8090 or any
  other previously-seen value; the host port is assigned per worktree.
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

**`xst`'s own config can silently point at 8080.** `xst` reads `~/.xstrc` (a
personal, machine-wide file, separate from this repo's `.existdb.json`) for its
default host/port, and it may default to 8080. Do not edit `~/.xstrc` — it's
outside this repo and may be shared by other projects/checkouts. Instead keep a
repo-local `.xstrc` here (already gitignored) pointing at the correct devcontainer
port, and invoke deploys as `xst --config .xstrc package install ...` rather than
bare `xst package install ...`.

## Prefer XQuery over Python for one-off scripting

When writing throwaway scripts to inspect, transform, or validate data in this
repo (checking a data collection, reshaping XML, scripting a query against
eXist), reach for XQuery first — it runs in the same environment as the app
and against the live database directly, rather than shelling out to a
different language runtime. Only fall back to Python (or another scripting
language) when the same task genuinely can't be expressed in XQuery, or
doesn't involve XML/the database at all (e.g. validating plain JSON syntax).

## Cypress assertions on data-package counts

9 of the 12 external `HistoryAtState/*` data packages this app depends on
(`gsh`, `other-publications`, `pocom`, `rdcr`, `tags`, `travels`, `visits`,
`wwdai`, `hac` — see README "External data packages") are append-only
upstream: new records get added over time (e.g. a new Secretary of State),
existing ones are never removed. A Cypress assertion that pins an *exact*
count of data-derived content (e.g. `have.length(71)` officeholders) will
spuriously fail the next time someone refreshes to a newer release, even
though nothing actually broke — this has already happened once, in
`test/cypress/e2e/gui/departmenthistory/people.cy.js`.

Two of the other 3 are exceptions, frozen rather than append-only:

- `milestones` backs a **retired** publication whose content has been frozen
  since 2018 — new `.xar` releases only ever touch build/packaging metadata,
  not the 19 era documents themselves. An exact count assertion there (e.g.
  19 eras) is intentional and expected to stay stable.
- `conferences` backs 5 frozen conference-proceedings documents (last
  addition 2012) that are not expected to grow, so exact counts against it
  (e.g. the 5-conference landing-page listing) are fine too.

`frus-history` (behind `/historicaldocuments/frus-history`, OP#1294) sits in
between: its collections change rarely — the monograph has been frozen since
its 2015 publication, and the documents/articles collections last grew years
ago — but the package **does** keep getting `.xar` releases and nothing
declares its content closed the way milestones'/conferences' is. Treat its
counts (63 documents, 28 authored articles, 13 events, 29 monograph TOC
entries at write-time) like the append-only packages':
`.should("have.length.at.least", N)` with `N` safely below those values.

When a test counts items rendered from one of these packages, use a lower
bound instead: `.should("have.length.at.least", N)`, with `N` set a bit
below the count observed at write-time. This only applies to counts of
data-derived content — fixed UI chrome (nav links, static page structure)
should still assert an exact count.

## HTML comments in templates: never use "--" inside them

XML forbids a literal `--` anywhere inside a `<!-- ... -->` comment (only at
the closing `-->`). This repo's template files are XML, so a comment written
in ordinary prose style — using `--` as a dash, the way this file and commit
messages do — breaks the whole template with a cryptic `XPST0003 expecting
end of XML comment` error at deploy time, not at write time. It has caused
repeat, easy-to-miss bugs. Use `;`, `—` (em dash), or a full stop instead of
`--` inside any `<!-- -->` block.

It isn't only prose dashes: writing out a literal CSS class name that happens
to use BEM's `--` modifier syntax (`usa-alert--error`, `usa-alert--warning`,
etc.) inside a comment trips the exact same rule — found live when a comment
mentioning `usa-alert--warning` broke a template the same way a dash would
have. When referencing a `--`-modifier class name in a comment, write it some
other way (quote the base and modifier separately: `"usa-alert" "error"
variant`) rather than the literal class string.

Before deploying a new or edited template comment, check every changed
`.html` file's comment *bodies* specifically — a plain `grep -rn -- '--'`
over-matches (flags `--` in ordinary attributes like `class="usa-..."`
outside any comment) and under-matches if you then filter those false
positives out by pattern (a `grep -v 'usa-'` hides genuine `--` mentioned
*inside* a comment too, which is exactly how this bug slipped through once
already). A short Python one-liner checks only inside `<!-- -->` bodies,
across every changed template, with no false positives either way:
```
python3 -c "
import re, glob
for f in glob.glob('templates/**/*.html', recursive=True):
    content = open(f).read()
    for m in re.finditer(r'<!--(.*?)-->', content, re.S):
        if '--' in m.group(1):
            print(f, repr(m.group(1)[:200]))
"
```
