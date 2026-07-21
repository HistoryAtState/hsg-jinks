# hsg-jinks

Jinks-generated TEI Publisher application (`abbrev: hsg-jinks`) for the Office of
the Historian. This is a **Mode B** repo: `expath-pkg.xml` + `config.json` at the
root, no `profiles/`. Edit `config.json` and regenerate via `jinks update` rather
than hand-editing generated files (see the jinks skills for the full workflow).

## Reference implementation (old app)

The pre-v10 TEI Publisher application this project replaces lives outside this
repo, in a sibling checkout of the full HSG source tree:

- Source root: `../hsg-project` (its own git repo — do not copy it in here)
- Application code: `../hsg-project/repos/hsg-shell`

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
