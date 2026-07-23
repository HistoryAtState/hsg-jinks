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

## Parallel worktrees & the read-only mirror

- Work happens in parallel git worktrees (flat siblings, `../hsg-jinks--<slug>`),
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
