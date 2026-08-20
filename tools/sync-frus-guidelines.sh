#!/usr/bin/env bash
# Vendor the canonical FRUS TEI artifacts from the frus-tei-guidelines repo into
# this app. That repo is the single source for the FRUS TEI customization: the
# schema, the processing model, the rendition vocabulary and the reference
# stylesheets. Its dist workflow publishes exactly six artifacts
# (frus.odd frus.rnc frus-encodingDesc.xml frus.css print.css VERSION); this
# script is how they reach hsg-jinks.
#
# Only ONE of them is live in the running app:
#
#   resources/odd/frus.odd    compiled into the transforms. resources/odd/hsg-jinks.odd
#                             carries source="frus.odd", so odd:compile
#                             (tei-publisher-lib odd2odd.xql) resolves it by
#                             filename inside $config:odd-root and merges the two.
#
# The rest are vendored for reference only, under resources/frus-tei-guidelines/,
# and excluded from the app build in build.xml. Two deliberate choices there:
#
#   frus.css MUST NOT be copied into resources/odd/. TEI Publisher's
#   css:global-css-by-rendition resolves the ODD's <rendition source="frus.css"/>
#   against the odd collection and inlines whatever it finds into the generated
#   web stylesheet. frus.css is an oXygen Author / raw-TEI stylesheet: it
#   declares no default namespace and selects on bare element names (p, div,
#   head, label, body ...), which in an HTML page match HTML elements. Leaving it
#   out of the odd collection makes that lookup miss and emit only a harmless
#   "external styles not found" comment.
#
#   frus.odd is vendored BYTE-IDENTICAL to canonical: no banner, no local edit.
#   That is what makes --check meaningful. Provenance lives in
#   resources/frus-tei-guidelines/PROVENANCE.txt instead.
#
# frus-encodingDesc.xml is NOT copied here at all: it reaches the app through the
# frus-data-jinks data package (data/frus-tei-guidelines-resources/), and
# tools/generate-frus-renditions.xq derives resources/css/frus-renditions.css
# from the deployed copy. --check verifies that copy rather than duplicating it.
#
# Usage:
#   tools/sync-frus-guidelines.sh            copy the artifacts, rewrite PROVENANCE.txt
#   tools/sync-frus-guidelines.sh --check    write nothing; exit nonzero on drift
#   tools/sync-frus-guidelines.sh --allow-dirty
#       sync from an upstream checkout with uncommitted changes; refused by
#       default, because the recorded commit would not describe the bytes copied
#
#   FRUS_GUIDELINES_DIR=/path/to/checkout tools/sync-frus-guidelines.sh
#       override the upstream checkout (default: ../../frus-tei-guidelines,
#       the flat sibling -- see README "Workspace layout")
#
# After a sync that changes frus.odd, recompile the ODDs so the transforms pick
# up the new models -- they are generated at deploy time and are gitignored:
#
#   jinks run hsg-jinks fix-odds
#
# and if the rendition vocabulary changed, refresh the generated stylesheet too
# (see tools/generate-frus-renditions.xq).

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
upstream="${FRUS_GUIDELINES_DIR:-$repo_root/../../frus-tei-guidelines}"
ref_dir="$repo_root/resources/frus-tei-guidelines"
# the data package's vendored copy, checked but never written by this script
data_encoding_desc="$repo_root/../../hsg-jinks-data/data/frus-tei-guidelines-resources/frus-encodingDesc.xml"

check_only=0
allow_dirty=0
for arg in "$@"; do
    case "$arg" in
        --check) check_only=1 ;;
        --allow-dirty) allow_dirty=1 ;;
        *) echo "usage: tools/sync-frus-guidelines.sh [--check] [--allow-dirty]" >&2; exit 1 ;;
    esac
done

[ -d "$upstream" ] || {
    echo "error: frus-tei-guidelines checkout not found: $upstream" >&2
    echo "clone it as a flat sibling, or set FRUS_GUIDELINES_DIR" >&2
    exit 1
}
upstream=$(cd "$upstream" && pwd)

# upstream artifact -> destination, relative to the repo root
artifacts="
frus.odd|resources/odd/frus.odd
frus.css|resources/frus-tei-guidelines/frus.css
print.css|resources/frus-tei-guidelines/print.css
frus.rnc|resources/frus-tei-guidelines/frus.rnc
"

for a in $artifacts; do
    src="$upstream/${a%%|*}"
    [ -f "$src" ] || { echo "error: missing upstream artifact: $src" >&2; exit 1; }
done

drift=0

if [ "$check_only" -eq 1 ]; then
    echo "==> checking vendored artifacts against $upstream"
    for a in $artifacts; do
        src="$upstream/${a%%|*}"; dest="$repo_root/${a##*|}"
        if [ ! -f "$dest" ]; then
            echo "MISSING: ${a##*|} (never synced)" >&2; drift=1
        elif cmp -s "$src" "$dest"; then
            echo "  ok       ${a##*|}"
        else
            echo "DRIFT:   ${a##*|} differs from canonical" >&2
            diff -u "$dest" "$src" | head -40 >&2 || true
            drift=1
        fi
    done

    # frus-encodingDesc.xml lives in the data package, not here. Upstream ships
    # the comparison itself (c14n-normalized), so delegate rather than reimplement.
    echo "==> checking the data package's vendored rendition vocabulary"
    if [ -f "$data_encoding_desc" ]; then
        "$upstream/check-rendition-drift.sh" "$data_encoding_desc" || drift=1
    else
        echo "  skipped  hsg-jinks-data checkout not found at $data_encoding_desc" >&2
    fi

    # Stale copies in the data package are out of scope for this script, but
    # silence would let them rot unnoticed -- they predate the 2026-08 upstream
    # consolidation that moved the processing model into frus.odd.
    for f in frus.odd frus.rnc; do
        stale="$repo_root/../../hsg-jinks-data/data/frus-tei-guidelines-resources/$f"
        if [ -f "$stale" ] && ! cmp -s "$upstream/$f" "$stale"; then
            echo "  note     hsg-jinks-data's $f is stale (not synced by this script)" >&2
        fi
    done

    # A clean byte match still leaves one question open: has upstream moved on
    # since the sync? Compare the recorded commit against upstream HEAD.
    if [ -f "$ref_dir/PROVENANCE.txt" ]; then
        recorded=$(awk '$1 == "commit" { print $2 }' "$ref_dir/PROVENANCE.txt")
        current=$(git -C "$upstream" rev-parse HEAD 2>/dev/null || echo "unknown")
        if [ "$recorded" != "$current" ]; then
            echo "  note     upstream HEAD is $current, provenance records $recorded" >&2
            echo "           (artifacts match, so the difference is in unpublished files)" >&2
        fi
    else
        echo "MISSING: resources/frus-tei-guidelines/PROVENANCE.txt" >&2; drift=1
    fi

    [ "$drift" -eq 0 ] && echo "==> no drift" || echo "==> drift detected" >&2
    exit "$drift"
fi

# Provenance that names a commit which does not contain the bytes just copied is
# worse than no provenance at all, so a dirty upstream tree is refused by default.
if [ -n "$(git -C "$upstream" status --porcelain 2>/dev/null)" ] && [ "$allow_dirty" -eq 0 ]; then
    echo "error: $upstream has uncommitted changes" >&2
    echo "commit them, or pass --allow-dirty to record the commit anyway" >&2
    exit 1
fi

echo "==> syncing from $upstream"
mkdir -p "$ref_dir"
for a in $artifacts; do
    src="$upstream/${a%%|*}"; rel="${a##*|}"; dest="$repo_root/$rel"
    if cmp -s "$src" "$dest" 2>/dev/null; then
        echo "  unchanged  $rel"
    else
        cp "$src" "$dest"
        echo "  updated    $rel"
    fi
done

version=$(cat "$upstream/VERSION")
commit=$(git -C "$upstream" rev-parse HEAD 2>/dev/null || echo "unknown")
branch=$(git -C "$upstream" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
dirty=""
git -C "$upstream" diff --quiet 2>/dev/null || dirty=" (working tree dirty)"

cat > "$ref_dir/PROVENANCE.txt" <<EOF
FRUS TEI guidelines artifacts vendored into hsg-jinks.

GENERATED by tools/sync-frus-guidelines.sh -- do not edit by hand, and do not
edit the vendored artifacts either: they are kept byte-identical to canonical so
that "tools/sync-frus-guidelines.sh --check" can detect drift.

source    https://github.com/joewiz/frus-tei-guidelines
version   $version
branch    $branch
commit    $commit$dirty
synced    $(date -u +%Y-%m-%dT%H:%M:%SZ)

Live in the app:
  resources/odd/frus.odd        the FRUS processing model + schema customization.
                                resources/odd/hsg-jinks.odd derives from it via
                                schemaSpec/@source and overrides it where this app
                                needs its own behaviour.

Reference only (excluded from the app build in build.xml):
  frus.css                      oXygen Author / raw-TEI reference stylesheet. NOT
                                safe to load in the web app: bare TEI element
                                selectors would match HTML elements.
  print.css                     Prince paged-media layer for the PDF pipeline.
  frus.rnc                      generated RelaxNG-compact schema, for validating
                                FRUS TEI outside the app.

Not vendored here:
  frus-encodingDesc.xml         reaches the app through the frus-data-jinks data
                                package; see tools/generate-frus-renditions.xq.
EOF
echo "  updated    resources/frus-tei-guidelines/PROVENANCE.txt"
echo "==> synced frus-tei-guidelines $version ($commit)"
echo "    if frus.odd changed, recompile the transforms: jinks run hsg-jinks fix-odds"
