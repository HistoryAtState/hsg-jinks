xquery version "3.1";

module namespace opds="https://history.state.gov/ns/templates/opds-catalog";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "../config.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace atom="http://www.w3.org/2005/Atom";

(:~
 : Ported from hsg-shell's modules/opds-catalog.xql. Only used to resolve
 : cover-image URLs -- epub/mobi/pdf hrefs come straight from each volume's
 : own tei:relatedItem/tei:ref/@target, which is already an absolute
 : static.history.state.gov URL in the source data, not built here.
 :)
declare variable $opds:S3_URL := "https://static.history.state.gov";

(:~ Mirrors hsg-shell's tags-html.xqm $tags:TAXONOMY_COL. Deployed by the
 : `tags` data package (HistoryAtState/tags), which the /tags section also
 : depends on; see README "External data packages". :)
declare variable $opds:TAXONOMY_COL := "/db/apps/tags/taxonomy";

declare variable $opds:FEED_AUTHOR_NAME := "Office of the Historian";

(:~
 : Every volume this app knows about that has an ebook -- "has an ebook" is
 : defined the same way hsg-shell's fh:volumes-with-ebooks() defines it:
 : carries an epub tei:relatedItem. mobi/pdf-only volumes (no epub) are not
 : considered ebook volumes by any route in this section, matching hsg-shell.
 :)
declare function opds:ebook-volumes() as element(tei:TEI)* {
    collection($config:data-root)//tei:relatedItem[@type eq "epub"]/root(.)/tei:TEI
};

(:~
 : Build an absolute, externally-resolvable URL for a path relative to this
 : app's own root -- OPDS feed/entry ids and links must be absolute since an
 : e-reader client resolves them outside of any browser/page context. Same
 : technique as modules/lib/api/iiif.xql's iiif:link (scheme + server-name +
 : non-default port + $config:context-path).
 :)
declare function opds:absolute-url($relpath as xs:string) as xs:string {
    let $host := request:get-scheme() || "://" || request:get-server-name()
    let $port :=
        if (request:get-server-port() = (80, 443)) then
            ()
        else
            ":" || request:get-server-port()
    return
        string-join(($host, $port, replace($config:context-path || "/" || $relpath, "//", "/")))
};

declare function opds:base-url() as xs:string {
    opds:absolute-url("api/v1/catalog")
};

(:~ Generic Atom &lt;link&gt;, explicitly namespaced (see opds:entry for why). :)
declare function opds:link($type as xs:string?, $rel as xs:string?, $href as xs:string?, $title as xs:string?) as element(atom:link) {
    element { QName('http://www.w3.org/2005/Atom', 'link') } {
        if ($type) then attribute type {$type} else (),
        if ($rel) then attribute rel {$rel} else (),
        if ($href) then attribute href {$href} else (),
        if ($title) then attribute title {$title} else ()
    }
};

declare function opds:navigation-link($rel as xs:string?, $href as xs:string?, $title as xs:string?) as element(atom:link) {
    opds:link('application/atom+xml;profile=opds-catalog;kind=navigation', $rel, $href, $title)
};

declare function opds:acquisition-link($rel as xs:string?, $href as xs:string?, $title as xs:string?) as element(atom:link) {
    opds:link('application/atom+xml;profile=opds-catalog;kind=acquisition', $rel, $href, $title)
};

(:~
 : Generic Atom &lt;entry&gt;. Every child is built via an explicit atom
 : QName rather than a bare `element title {...}` -- hsg-shell's opds:entry
 : relies on ambient default-namespace inheritance from the enclosing
 : &lt;feed xmlns="..."&gt; for its children, which is fragile (this module
 : declares no default element namespace at all), so this port names every
 : element explicitly instead of assuming inheritance carries it through
 : serialize().
 :
 : No &lt;content&gt; element, matching hsg-shell's own deliberate choice
 : (its comment: "suppressing the content element since ShuBooks won't show
 : summary when content is present") -- an e-reader compatibility fix, not a
 : bug, so it is kept rather than "corrected".
 :)
declare function opds:entry($title as xs:string, $id as xs:string, $updated as xs:string?, $summary as xs:string?, $links as element(atom:link)*) as element(atom:entry) {
    element { QName('http://www.w3.org/2005/Atom', 'entry') } {
        element { QName('http://www.w3.org/2005/Atom', 'title') } { $title },
        element { QName('http://www.w3.org/2005/Atom', 'id') } { $id },
        element { QName('http://www.w3.org/2005/Atom', 'updated') } { $updated },
        element { QName('http://www.w3.org/2005/Atom', 'summary') } { attribute type {'text'}, $summary },
        $links
    }
};

declare function opds:feed($id as xs:string, $title as xs:string, $links as element(atom:link)*, $entries as element(atom:entry)*) as element(atom:feed) {
    element { QName('http://www.w3.org/2005/Atom', 'feed') } {
        attribute xml:lang { 'en' },
        element { QName('http://www.w3.org/2005/Atom', 'id') } { $id },
        element { QName('http://www.w3.org/2005/Atom', 'title') } { $title },
        element { QName('http://www.w3.org/2005/Atom', 'updated') } { current-dateTime() },
        element { QName('http://www.w3.org/2005/Atom', 'author') } {
            element { QName('http://www.w3.org/2005/Atom', 'name') } { $opds:FEED_AUTHOR_NAME },
            element { QName('http://www.w3.org/2005/Atom', 'uri') } { opds:absolute-url("") }
        },
        $links,
        $entries
    }
};

(:~
 : One acquisition &lt;entry&gt; per volume. Each of epub/mobi/pdf is gated on
 : its OWN tei:relatedItem existing -- hsg-shell's opds:ebook-entries instead
 : gates the mobi link on `exists($epub)`, so a volume with a mobi but no
 : epub silently loses its mobi link, and a volume with an epub but no mobi
 : still emits an href-less mobi &lt;link&gt;. Fixed here as a deliberate
 : behavior change (#1201).
 :)
declare function opds:ebook-entries($vols as element(tei:TEI)*) as element(atom:entry)* {
    for $vol in $vols
    let $title := normalize-space($vol//tei:title[@type eq 'complete'])
    let $volId := $vol/@xml:id/string()
    let $epub := $vol//tei:relatedItem[@type eq "epub"]
    let $mobi := $vol//tei:relatedItem[@type eq "mobi"]
    let $pdf := $vol//tei:relatedItem[@corresp eq ("#" || $volId) and @type eq "pdf"]
    let $updated := $epub//tei:date/@when/string()
    let $links := (
        if (exists($epub)) then
            opds:acquisition-link('http://opds-spec.org/acquisition', $epub//tei:ref/@target/string(), $title || ' (EPUB)')
        else (),
        if (exists($mobi)) then
            opds:acquisition-link('http://opds-spec.org/acquisition', $mobi//tei:ref/@target/string(), $title || ' (Mobi)')
        else (),
        if (exists($pdf)) then
            opds:acquisition-link('http://opds-spec.org/acquisition', $pdf//tei:ref/@target/string(), $title || ' (PDF)')
        else (),
        opds:link('image/jpeg', 'http://opds-spec.org/image', $opds:S3_URL || '/frus/' || $volId || '/covers/' || $volId || '.jpg', 'Cover of ' || $title),
        opds:link('image/jpeg', 'http://opds-spec.org/image/thumbnail', $opds:S3_URL || '/frus/' || $volId || '/covers/' || $volId || '-thumb.jpg', 'Thumbnail-sized cover of ' || $title)
    )
    return
        opds:entry($title, $volId, $updated, $title, $links)
};

(:~ #1200: fixed 3-entry navigation feed, one entry per other route. :)
declare function opds:catalog-feed() as element(atom:feed) {
    let $base := opds:base-url()
    let $feed-id := $base
    let $entries := (
        opds:entry('All', $base || '/all', string(current-dateTime()), 'Every FRUS ebook', opds:acquisition-link('subsection', $base || '/all', 'All')),
        opds:entry('Recent', $base || '/recent', string(current-dateTime()), 'Recently published FRUS ebooks', opds:acquisition-link('subsection', $base || '/recent', 'Recent')),
        opds:entry('Browse', $base || '/browse', string(current-dateTime()), 'Browse ebooks by subject', opds:navigation-link('subsection', $base || '/browse', 'Browse'))
    )
    return
        opds:feed($feed-id, 'Office of the Historian eBooks', opds:navigation-link('self', $feed-id, 'Office of the Historian eBooks'), $entries)
};

(:~ #1201: every ebook volume, sorted by @xml:id, unpaginated (matches
 : hsg-shell's current scope; see #1201's own rework note on pagination). :)
declare function opds:all-feed() as element(atom:feed) {
    let $base := opds:base-url()
    let $feed-id := $base || '/all'
    let $sorted := for $vol in opds:ebook-volumes() order by $vol/@xml:id return $vol
    return
        opds:feed($feed-id, 'All Ebooks', (
            opds:acquisition-link('self', $feed-id, 'All Ebooks'),
            opds:navigation-link('start', $base, 'Home')
        ), opds:ebook-entries($sorted))
};

(:~ #1202: sorted by tei:change/@when descending, cast explicitly as
 : xs:date (hsg-shell relies on lexical string ordering of an untyped
 : attribute, which happens to coincide for YYYY-MM-DD but isn't explicit),
 : truncated to $n. Validating $n itself is the caller's job (opdsapi:recent
 : raises BAD_REQUEST before this is ever invoked).
 :
 : The cast has to be guarded: @when is not always a full YYYY-MM-DD. In the
 : frus-v2-data corpus frus1861 carries when="1861" (year only) and
 : frus1958-60v05mSupp has no matching tei:change at all, and an unguarded
 : xs:date() on the former aborts the whole feed with a 500. Note eXist
 : misreports that as "xs:date must not have hour, minute or second fields
 : set", which points away from the actual cause. Volumes without a usable
 : date sort last ("empty least" under descending), which is where an
 : undated or imprecisely-dated volume belongs in a recency feed. :)
declare function opds:recent-feed($n as xs:integer) as element(atom:feed) {
    let $base := opds:base-url()
    let $feed-id := $base || '/recent'
    let $sorted :=
        for $vol in opds:ebook-volumes()
        let $volId := $vol/@xml:id/string()
        let $when := ($vol//tei:change[@corresp eq ("#" || $volId)]/@when/string())[1]
        order by (if ($when castable as xs:date) then xs:date($when) else ()) descending empty least
        return $vol
    return
        opds:feed($feed-id, 'Recently Published', (
            opds:acquisition-link('self', $feed-id, 'Recently Published'),
            opds:navigation-link('start', $base, 'Home')
        ), opds:ebook-entries(subsequence($sorted, 1, $n)))
};

(:~ True only for an id that actually exists in the taxonomy -- callers use
 : this to decide 404 before invoking opds:browse-feed. :)
declare function opds:tag-exists($tag as xs:string) as xs:boolean {
    exists(collection($opds:TAXONOMY_COL)/taxonomy//id[. = $tag])
};

(:~
 : Count of distinct ebook volumes tagged (directly or via a descendant tag)
 : under $node. tei:keywords/tei:term[. = $node//id] returns one hit per
 : matching TERM, not per volume -- a volume with two tags under the same
 : branch (e.g. two people-tags in one keywords list) would double-count if
 : that were used directly (found live: the one sample ebook volume carries
 : both "reagan-ronald" and "shultz-george-pratt", both under "people",
 : which inflated the People category's count to 2 for a single volume).
 : The trailing /root(.)/tei:TEI walk is what hsg-shell's own equivalent
 : code relies on for correctness here -- XPath path-step evaluation
 : deduplicates a step's result, so multiple matching terms in the same
 : document collapse to the same TEI root and are counted once.
 :)
declare %private function opds:tagged-volume-count($node as element()) as xs:integer {
    count(
        opds:ebook-volumes()//tei:keywords[@scheme eq "https://history.state.gov/tags"]
            /tei:term[. = $node//id]/root(.)/tei:TEI
    )
};

(:~
 : #1203. No $tag: the 3 top-level categories (People/Places/Topics) as
 : navigation entries. With $tag (already validated to exist by the caller):
 : that node's own category/tag children as navigation entries, PLUS one
 : acquisition entry per ebook volume tagged with it directly -- both kinds
 : can appear in the same feed, so (per the source spec) the response omits
 : a fixed `kind` from its Content-Type.
 :)
declare function opds:browse-feed($tag as xs:string?) as element(atom:feed) {
    let $base := opds:base-url()
    let $taxonomy := collection($opds:TAXONOMY_COL)/taxonomy
    let $node := if ($tag) then $taxonomy//id[. = $tag]/.. else $taxonomy
    let $feed-id := $base || '/browse' || (if ($tag) then '?tag=' || $tag else ())
    let $feed-title := if ($tag) then $node/label/string() else 'Keywords'
    let $sub-nodes := $node/(category | tag)
    let $nav-entries :=
        for $sub in $sub-nodes
        let $subId := $sub/id/string()
        let $subTitle := $sub/label/string()
        let $descendantCount := count($sub/(descendant::category | descendant::tag))
        let $summary := string-join((
            if ($descendantCount gt 0) then $descendantCount || ' sub-topics' else (),
            opds:tagged-volume-count($sub) || ' volumes'
        ), ', ')
        return
            opds:entry($subTitle, $subId, string(current-dateTime()), $summary, opds:navigation-link('subsection', $base || '/browse?tag=' || $subId, $subTitle))
    let $vol-entries :=
        if ($tag) then
            let $tagged := opds:ebook-volumes()[.//tei:keywords[@scheme eq "https://history.state.gov/tags"]/tei:term = $tag]
            let $sorted := for $vol in $tagged order by $vol/@xml:id return $vol
            return opds:ebook-entries($sorted)
        else
            ()
    return
        opds:feed($feed-id, $feed-title, (
            opds:link('application/atom+xml;profile=opds-catalog', 'self', $feed-id, $feed-title),
            opds:navigation-link('start', $base, 'Home')
        ), ($nav-entries, $vol-entries))
};

(:~
 : #1204. Runs ft:query() against taxonomy label text ONLY, never ebook
 : content -- matches hsg-shell's actual (if misleadingly-titled) scope; not
 : silently expanded to full-text search here. No try/catch here: malformed
 : Lucene syntax is left to propagate so the caller (opdsapi:search) can
 : catch it specifically and raise BAD_REQUEST, replacing hsg-shell's
 : catch-all `catch * { () }` that silently swallows every error, not just
 : bad syntax.
 :)
declare function opds:taxonomy-tag-hits($q as xs:string) as element()* {
    collection($opds:TAXONOMY_COL)/taxonomy//label[ft:query(., $q)]/..
};

declare function opds:search-feed($q as xs:string?, $hits as element()*) as element(atom:feed) {
    let $base := opds:base-url()
    let $feed-id := $base || '/search' || (if ($q) then '?q=' || $q else ())
    let $feed-title := if ($q) then 'Search ebooks for "' || $q || '"' else 'Search'
    let $entries :=
        for $tag in $hits
        let $title := $tag/label/string()
        let $id := $tag/id/string()
        let $descendantCount := count($tag/(descendant::category | descendant::tag))
        let $summary := string-join((
            if ($descendantCount gt 0) then $descendantCount || ' sub-topics' else (),
            opds:tagged-volume-count($tag) || ' volumes'
        ), ', ')
        order by $title
        return
            opds:entry($title, $id, string(current-dateTime()), $summary, opds:navigation-link('subsection', $base || '/browse?tag=' || $id, $title))
    return
        opds:feed($feed-id, $feed-title, (
            opds:navigation-link('self', $feed-id, $feed-title),
            opds:navigation-link('start', $base, 'Home')
        ), $entries)
};
