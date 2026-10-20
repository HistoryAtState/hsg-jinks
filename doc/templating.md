# Templating

How page templates and their XQuery are split in hsg-jinks. Templates use
[jinks-templates](https://github.com/eeditiones/jinks-templates) (its README
documents the full syntax); this article covers the conventions this app
follows on top of it, and the engine's limits we have run into.

## The goal: markup visible in templates

A page's markup lives in its template under `templates/pages/`. Anyone who
opens the template sees the page's structure: its wrappers, landmarks,
headings and the order of its sections. Repeating patterns are easier to
spot there, and people who don't write XQuery can still read and change the
markup.

Templates hold their logic to three directives:

- `[% if %]` … `[% elif %]` … `[% else %]` … `[% endif %]`
- `[% for $x in … %]` … `[% endfor %]`
- `[% let $x = … %]` … `[% endlet %]`

plus `[[ … ]]` for output.

## Where things go

| In the template | In XQuery (`modules/templates/*.xqm`) |
|---|---|
| Page wrappers, `header`/`nav`/`article`, headings | Loading documents, resolving xincludes, lookups in taxonomies |
| Order of the page's sections | Anything computed from the data: titles, ids, counts, offsets |
| Conditions on whether a section shows | Fragments reused across pages (pagination, cards) |
| Loops over the page's entries | Fragments whose markup is mostly conditional (a metadata row that only shows when the data has a value) |

## The pattern

A page has one function that returns its **data** as a map. The template
builds the markup from that map and calls **fragment functions** for the
parts that belong in XQuery.

### Populate the context before rendering

Where the route handler renders through `vapi:html`, it calls the data
function and passes the map as `vapi:html`'s second argument (`$extConfig`).
The template then reads it from the context, e.g. `$context?facsimile`
(`hsgapi:view-facsimile`). This is the preferred way.

- Use one key per page, named after the page. `vapi:html` merges
  `context.json` first and keeps the first value of a key, so a key that
  `context.json` already has (`data`, `type`, `id`, `label`, `theme`, …) is
  dropped silently.
- Name the key and the handler that fills it in the template's header
  comment, since the template no longer shows where its data comes from.
- Keep an `exists()` guard: a `?template=` parameter can pair the template
  with a route that does not fill its key.

### Pages rendered through `vapi:view`

Document pages (the volume landing page, the division listings) render
through jinks' `vapi:view`, which takes no `$extConfig`. Until it does, such
a template binds its data itself with `[% let %]`:

```html
[% let $volume = hsg:volume-landing($context) %]
[% if exists($volume) %]
<article class="hsg-frus__landing">
    <header class="hsg-frus__landing-header">
        [[ hsg:volume-administration-tags($volume?doc) ]]
        <h1>[[ $volume?title ]]</h1>
    </header>
    …
</article>
[% endif %]
[% endlet %]
```

- The data function returns the empty sequence when there is nothing to
  show, and the template guards with `exists()`.
- Expensive work happens once, in the data function, not once per fragment.
- Fragment functions take what they need from the map as arguments, not
  `$context`, where they can.
- A function a template calls must be public (not `%private`).

`templates/pages/volume/landing.html` and
`templates/pages/volume/division-listing.html` follow this pattern. Most
other pages still call one function per section; move them over when you
next change them.

## Layout constraints

- **One root element in `main`.** The layout's `main` is a flex row whose
  children each get `flex: 1` (`resources/css/layout.css`), so sibling
  elements at the top of a page template lay out as columns. Wrap the page
  in one element.
- **Sidebars per page:** a template's front-matter can override the theme
  for that page, e.g. hide a sidebar with
  `"theme": { "layout": { "before": { "hidden": true } } }`.
- **Overriding theme blocks:** the app fills the theme's `[% block %]`s with
  `[% template! name %]` in files registered under `templating.use` in
  `config.json` (e.g. `templates/hsg-blocks.html`).

## Comments

Prefer `[# … #]`: the engine discards it, so it never reaches the page.
Inside an HTML comment `<!-- … -->` a literal `--` breaks the template
(see `CLAUDE.md`).

## Known engine limits

- **`[% if %]` inside a `[% for %]` body renders as literal text** once
  the body has whitespace around it, as any indented template does; inside
  a `[% let %]` the whole loop does
  ([jinks-templates#95](https://github.com/eeditiones/jinks-templates/issues/95)).
  Use an inline expression instead: `[[ if (…) then … else … ]]`, or wrap
  the `if` in an element.
- **`[% include %]` of a partial whose root is a control block**
  (`if`/`for`/`let`) fails with `XPST0003` when the include sits inside
  another block
  ([jinks-templates#84](https://github.com/eeditiones/jinks-templates/issues/84)).

Add new limits here when you hit them, with the workaround you used.
