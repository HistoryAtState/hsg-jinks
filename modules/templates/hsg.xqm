xquery version "3.1";

module namespace hsg="https://history.state.gov/ns/templates/hsg";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace xi="http://www.w3.org/2001/XInclude";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "../config.xqm";
import module namespace page="http://teipublisher.com/ns/templates/page" at "page.xqm";

(:~
 : Build an absolute, externally-resolvable URL for a path relative to this
 : app's own root -- for content consumed outside any browser/page context
 : (OPDS feed ids and links, and anything else that must not emit a
 : root-relative href). Central home per PR #26 review: use this instead of
 : re-deriving scheme/host/port at the call site. Mirrors the technique of
 : modules/lib/api/iiif.xql's iiif:link (scheme + server-name + non-default
 : port + $config:context-path); that file is jinks-managed and so keeps its
 : own private copy rather than importing from here.
 :)
declare function hsg:absolute-url($relpath as xs:string) as xs:string {
    let $host := request:get-scheme() || "://" || request:get-server-name()
    let $port :=
        if (request:get-server-port() = (80, 443)) then
            ()
        else
            ":" || request:get-server-port()
    return
        string-join(($host, $port, replace($config:context-path || "/" || $relpath, "//", "/")))
};

(:~
 : Resolve one fragment of a header by name (titleStmt, publicationStmt,
 : seriesStmt): inline at the volume root's chapter/compilation level, but
 : xincluded from the volume's shared *_includes.xml at the volume-root
 : level (frus-unbound-alpha) -- so check for an inline child first. Plain
 : descendant steps like // don't see across an unexpanded xi:include; this
 : follows the specific include named by $name directly (doc() + id(), the
 : same pattern already used for footnotes in resources/odd/hsg-jinks.odd
 : and hsg:document-range below) rather than util:expand()ing the whole
 : header, which would also expand (and so attempt to resolve) teiHeader's
 : unrelated encodingDesc include -- a remote https:// URL -- for callers
 : that only want a title.
 :)
declare %private function hsg:resolve-include($header as element()?, $name as xs:string) as element()? {
    let $inline := $header/tei:fileDesc/*[local-name() = $name]
    return
        if (exists($inline)) then $inline
        else
            let $inc := $header//xi:include[@xpointer = $name]
            return
                if (not(exists($inc))) then ()
                else id($name, doc(util:collection-name($inc) || '/' || $inc/@href))
};

(:~
 : The full title of the publication a division belongs to, resolved from the
 : volume root document (whose titleStmt is xincluded from the shared
 : *_includes.xml; see hsg:resolve-include). Shared by
 : hsg:collection-breadcrumbs and hsg:navigation-title, and public for
 : tags.xqm's resource listings (the direct titleStmt lookup #1101 used
 : misses the xincluded titleStmt of the v2 volume roots).
 :)
declare function hsg:volume-title($doc as node()?) as xs:string? {
    if (not(exists($doc))) then ()
    else
        let $publication := config:get-relpath($doc, $config:data-default) => tokenize("/") => head()
        let $volume := doc($config:data-default || "/" || $publication || "/" || $publication || ".xml")
        let $titleStmt := hsg:resolve-include($volume//tei:teiHeader, 'titleStmt')
        return normalize-space(($titleStmt/tei:title)[1])
};

(:~
 : The volume-title heading rendered above the content of every interior
 : division page (chapter, document, section). Reference parity with
 : hsg-shell's pages:navigation-title, which puts this h2 on all
 : volume-interior pages.
 :)
declare function hsg:navigation-title($context as map(*)) as element(h2)? {
    let $title := hsg:volume-title($context?doc?content)
    return
        if ($title != '') then
            <h2 class="hsg-navigation-title" id="navigation-title">{$title}</h2>
        else ()
};

(:~
 : The volume's table of contents, as a USWDS side navigation (#1089).
 :
 : Shape (reference parity): front matter flat, then each compilation as a node
 : with its chapters nested beneath, then the back matter. Documents are never
 : listed. The print table of contents (front/toc.xml) is omitted.
 :
 : Rendered into the layout's `before` block, so it appears on the comp, chapter
 : and document pages -- but not on the volume landing, whose TOC belongs in the
 : main content instead (#1080); see the guard below.
 :
 : The same tree is what #1080 needs in main content, so keep this the only
 : traversal.
 :)
declare function hsg:volume-toc($context as map(*)) {
    let $doc := $context?doc?content
    let $publication := ($doc//tei:bibl[@type='frus-volume-id'])[1]/string()
    return
    (: Only a division of a volume gets the sidebar. The volume file itself
       carries no typed bibl ids at all -- only its divisions do -- so an absent
       frus-volume-id is what identifies the landing page, which has no sidebar:
       its table of contents belongs in the main content (#1080). :)
    if (exists($doc) and $publication != '') then
        let $current := ($doc//tei:bibl[@type='frus-division-id'])[1]/string()
        let $current-is-document := ($doc//tei:bibl[@type='frus-division-type'])[1] = 'document'
        let $volume := doc($config:data-default || "/" || $publication || "/" || $publication || ".xml")
        let $divisions := hsg:toc-divisions($publication)
        return
            <nav aria-label="Side navigation" class="toc">
                <h5>
                    <pb-i18n key="document.contents">Contents</pb-i18n>
                </h5>
                <ul class="usa-sidenav">
                    {hsg:toc-entries($volume/tei:TEI, $divisions, $publication, $current, $current-is-document, $context)}
                </ul>
            </nav>
    else
        ()
};

(:~
 : Every division of a volume that the table of contents can list, keyed by id.
 :
 : Fetched in one collection scan rather than by resolving each xi:include in
 : turn: a volume has ~16 listable divisions but ~340 documents, and opening
 : every document only to discover it is a document cost ~4.8s per page against
 : ~95ms for this.
 :
 : Documents are excluded because they are never listed, and the print table of
 : contents by its subtype rather than by hardcoding front/toc.xml, so both
 : generalise to other volumes.
 :)
declare %private function hsg:toc-divisions($publication as xs:string) as map(*) {
    map:merge(
        (: Keep only listable divisions: those carrying a frus-division-type that
           is neither 'document' nor 'document-pending'. Excluding only
           'document' let a pending chapter's 71 document-pending includes leak
           into the table of contents as "Document 1..71" child entries. The
           empty-string guard also drops the volume root (and anything else with
           no frus-division-type), which carries no frus-division-id either and
           would give map:entry below an empty key -- exactly what the original
           '!= "document"' comparison excluded implicitly. :)
        for $division in collection($config:data-default || "/" || $publication)/tei:TEI
        let $division-type := normalize-space(($division/tei:teiHeader//tei:bibl[@type='frus-division-type'])[1])
        where $division-type != ''
            and not(starts-with($division-type, 'document'))
            and normalize-space(($division//tei:bibl[@type='frus-division-subtype'])[1]) != 'table-of-contents'
        return
            map:entry(($division//tei:bibl[@type='frus-division-id'])[1]/string(), $division)
    )
};

(:~
 : One level of the table of contents: the divisions a division includes.
 :
 : Walks the parent's xi:include order -- which is where document order comes
 : from -- and looks each @xpointer up in $divisions. Anything absent from the
 : map is a document (or the print TOC) and is skipped without opening it, so a
 : chapter's ~50 document includes cost 50 map lookups and no I/O.
 :
 : Recursion stops for the same reason: a chapter's includes are all documents,
 : so it yields no children. Volumes with several compilations, with none, or
 : with subchapters need no special casing -- though the loaded fixture has
 : exactly one compilation and cannot exercise those variants.
 :)
(:~
 : A division title for display (OP#1085): frus-unbound-alpha splits a
 : chapter/compilation title into a date-range title plus a descriptive
 : subtitle, which read as a run-on when merely concatenated. The reference
 : renders a line break between them (its tei-lb br) everywhere the title
 : appears as a block -- heading, TOCs, document list -- so this returns
 : (title, <br/>, subtitle) for the split case and the plain title otherwise.
 : Breadcrumbs, which cannot break lines, join with a space instead.
 :
 : normalize-space is load-bearing, not noise (PR #47 review): 1431 of the
 : 2714 titleStmt titles in the loaded corpus carry line wraps from TEI
 : source indentation, which would otherwise pass through into the emitted
 : markup and into exact-text assertions as raw newline-plus-indent runs.
 :)
declare %private function hsg:split-title($titles as element(tei:title)*) {
    if (count($titles) gt 1) then (
        head($titles) => normalize-space(),
        <br/>,
        tail($titles) => string-join(' ') => normalize-space()
    ) else (
        $titles => normalize-space()
    )
};

declare %private function hsg:toc-entries($division as element(tei:TEI)?, $divisions as map(*),
        $publication as xs:string, $current as xs:string?, $current-is-document as xs:boolean,
        $context as map(*)) {
    for $include in $division//tei:text//xi:include
    let $id := $include/@xpointer/string()
    where map:contains($divisions, $id)
    let $included := $divisions($id)
    (: A chapter/compilation title may be split across two title elements (a
       date range plus a descriptive subtitle, frus-unbound-alpha); show both
       with the reference's line break between them (OP#1085). :)
    let $title := hsg:split-title($included//tei:fileDesc//tei:titleStmt/tei:title)
    (: current when it is the page being viewed, or -- on a document page, where
       the document itself is not listed -- when it is the division including it :)
    let $is-current :=
        $id = $current or
        ($current-is-document and exists($included//tei:text//xi:include[@xpointer = $current]))
    (: An unpublished division ('chapter-pending', 'section-pending', ...) is
       shown muted (italic, non-link colour), reference parity with hsg-shell's
       li.pending -- here on the sidebar too, not only the landing TOC. :)
    let $is-pending := ends-with(normalize-space(($included//tei:bibl[@type='frus-division-type'])[1]), '-pending')
    (: Document range "(Documents N-M)", reference parity with hsg-shell's
       sidebar, shown after divisions that contain documents. :)
    let $range-label := hsg:document-range-label(hsg:document-range($included))
    let $children := hsg:toc-entries($included, $divisions, $publication, $current, $current-is-document, $context)
    return
        <li class="usa-sidenav__item{if ($is-pending) then ' pending' else ''}">
            {
                element a {
                    attribute href {
                        $context?context-path || "/historicaldocuments/" || $publication || "/" || $id
                    },
                    if ($is-current) then (
                        attribute class {"usa-current"},
                        attribute aria-current {"page"}
                    ) else (),
                    $title
                }
            }
            {if (exists($range-label)) then <span class="toc-range">{$range-label}</span> else ()}
            {
                if (exists($children)) then
                    <ul class="usa-sidenav__sublist">{$children}</ul>
                else
                    ()
            }
        </li>
};

(:~
 : List every volume in the Historical Documents section as linked list items.
 :
 : Scaffolding for the section landing (#1084): barebones navigation, nothing
 : more. There is one volume today.
 :
 : A volume is a child collection of the data root holding a TEI file named
 : after it (frus1981-88v05/frus1981-88v05.xml) -- the same shape
 : hsg:collection-breadcrumbs() relies on -- so this discovers volumes rather
 : than listing them anywhere.
 :)
declare function hsg:volume-list($context as map(*)) {
    for $volume in xmldb:get-child-collections($config:data-default)
    let $path := $config:data-default || "/" || $volume || "/" || $volume || ".xml"
    where doc-available($path)
    (: titleStmt lives in a shared *_includes.xml, xincluded rather than
       duplicated inline (frus-unbound-alpha) -- see hsg:resolve-include. :)
    let $titleStmt := hsg:resolve-include(doc($path)//tei:teiHeader, 'titleStmt')
    let $title := normalize-space(($titleStmt/tei:title)[1])
    order by $title
    return
        <li>
            <a href="{$context?context-path}/historicaldocuments/{$volume}">{$title}</a>
        </li>
};

(:~
 : The administrations taxonomy (frus-data-jinks, OP#1214): one category per
 : administration slug, one catDesc per presidency. Its xml:id is the target
 : the volume headers' keywords scheme "#frus-administration-coverage" point
 : at, so the slugs here and the terms in the volumes are one vocabulary.
 :)
declare %private function hsg:administrations() as element(tei:taxonomy)? {
    doc($config:data-root || "/administrations/administrations.xml")
        //tei:taxonomy[@xml:id = 'frus-administration-coverage']
};

declare function hsg:administration($admin-id as xs:string) as element(tei:category)? {
    hsg:administrations()/tei:category[@xml:id = $admin-id]
};

(:~
 : Every volume root TEI classified under the given administration.
 :
 : Membership lives in each volume's own header (keywords scheme
 : "#frus-administration-coverage"), so this walks the volume collections the
 : same way hsg:volume-list does rather than querying a registry; there is no
 : bibliography collection in the v2 data.
 :)
declare %private function hsg:volumes-in-administration($admin-id as xs:string) as element(tei:TEI)* {
    for $volume in xmldb:get-child-collections($config:data-default)
    let $path := $config:data-default || "/" || $volume || "/" || $volume || ".xml"
    where doc-available($path)
    let $root := doc($path)/tei:TEI
    where $root/tei:teiHeader//tei:keywords[@scheme = '#frus-administration-coverage']/tei:term = $admin-id
    return $root
};

(:~
 : The section landing's administration grid: one card per presidency, in the
 : taxonomy's chronological order, reference parity with hsg-shell's
 : pages/historicaldocuments/index.xml thumbnails. A catDesc without a
 : portrait ptr (pre-truman, the nixon-ford combined heading entry) is not a
 : card. Both Nixon and Ford link to the shared nixon-ford page, and the two
 : Cleveland terms stay separate, matching the slugs the volume headers use.
 :)
declare function hsg:administration-cards($context as map(*)) {
    for $category in hsg:administrations()/tei:category
    for $presidency in $category/tei:catDesc[tei:ptr[@type = 'portrait']]
    let $name := normalize-space($presidency/tei:term)
    let $dates := normalize-space($presidency/tei:date[@type = 'coverage'])
    return
        <li class="usa-card hsg-admin-card">
            <div class="usa-card__container">
                <div class="usa-card__media">
                    <div class="usa-card__img">
                        <img src="{$presidency/tei:ptr[@type = 'portrait']/@target}"
                            alt="{replace($name, ' Administration$', '')}" loading="lazy"/>
                    </div>
                </div>
                <div class="usa-card__header">
                    <h2 class="usa-card__heading">
                        <a href="{$context?context-path}/historicaldocuments/{$category/@xml:id}">{$name}</a>
                    </h2>
                </div>
                <div class="usa-card__body">
                    <p>{$dates}</p>
                </div>
            </div>
        </li>
};

(:~
 : Administration page heading, reference parity with hsg-shell's
 : frus:administration-name: "Ronald Reagan Administration (1981-1989)" with
 : the term-of-office dates, not the coverage dates the landing cards show.
 : nixon-ford uses its combined catDesc; a category without a term date
 : (pre-truman) falls back to its coverage date.
 :)
declare function hsg:administration-heading($context as map(*)) as xs:string {
    let $category := hsg:administration($context?administration-id)
    let $head := ($category/tei:catDesc[@n = 'combined'], $category/tei:catDesc)[1]
    let $date := ($head/tei:date[@type = 'term'], $head/tei:date[@type = 'coverage'])[1]
    return normalize-space($head/tei:term) || " (" || normalize-space($date) || ")"
};

(:~
 : The administrations whose volumes predate administration-organized
 : sub-series (the series was organized by year for 1861-1951 and
 : triennially for 1952-1963), reference parity with the closed list in
 : hsg-shell's fh:administration-listing-note. Their pages carry an
 : explanatory note; administration-organized pages carry none (hsg-shell
 : has that branch commented out, and the reference site renders nothing).
 :)
declare %private variable $hsg:pre-administration-subseries-admins := (
    "lincoln", "johnson-a", "grant", "hayes", "garfield", "arthur",
    "cleveland-22", "harrison", "cleveland-24", "mckinley", "roosevelt-t",
    "taft", "wilson", "harding", "coolidge", "hoover", "roosevelt-fd",
    "truman", "kennedy"
);

(:~
 : The FRUS production tracks, reference parity with the
 : frus-production-tracks taxonomy in hsg-shell's code table
 : (frus repo, shared/frus-production.xml). frus-data-jinks carries no code
 : table, and the vocabulary is closed and stable (three fixed categories),
 : so the ids and display labels live here. Order is the taxonomy's, which
 : fixes the order of the per-track headings on administration pages.
 :)
declare %private variable $hsg:production-tracks := (
    map { "id": "regular", "label": "Regular" },
    map { "id": "accelerated", "label": "Accelerated" },
    map { "id": "retrospective", "label": "Retrospective" }
);

(:~
 : The production track under which a volume covers the given
 : administration. The volume's #frus-administration-coverage terms carry
 : xml:ids, and its #frus-production-priority terms point back at them, so a
 : retrospective volume spanning several administrations can be Regular for
 : one and Retrospective for another. Most volumes point via @corresp; a few
 : v2 headers use @ana for the same relation (e.g. frus1977-80v27), so both
 : are accepted.
 :)
declare %private function hsg:production-track($root as element(tei:TEI), $admin-id as xs:string) as xs:string? {
    let $admin-terms := $root/tei:teiHeader//tei:keywords[@scheme = '#frus-administration-coverage']
        /tei:term[. = $admin-id]
    let $refs := $admin-terms/@xml:id ! ("#" || .)
    let $tracks := $root/tei:teiHeader//tei:keywords[@scheme = '#frus-production-priority']
        /tei:term[(@corresp, @ana) = $refs]
    return ($tracks ! string(.))[1]
};

(:~
 : The production tracks in use among an administration's volumes, in order
 : of first appearance with the volumes sorted by id. That matches what the
 : reference site's group-info sentence shows (hsg-shell's order-by there
 : compares against an attribute that does not exist on categories, so its
 : groups keep first-appearance order), while the per-track headings below
 : use the taxonomy order instead, same as the reference.
 :)
declare %private function hsg:tracks-in-use($roots as element(tei:TEI)*, $admin-id as xs:string) as xs:string* {
    let $per-volume :=
        for $root in $roots
        order by $root/@xml:id
        return hsg:production-track($root, $admin-id)
    return distinct-values($per-volume)
};

(:~
 : The explanatory note on pages of administrations that predate
 : administration-organized sub-series, reference parity with hsg-shell's
 : fh:administration-listing-note and the pre-administration-based-subseries
 : paragraph in its administrations.xml.
 :)
declare function hsg:administration-listing-note($context as map(*)) as element(p)? {
    if ($context?administration-id = $hsg:pre-administration-subseries-admins) then
        <p id="pre-administration-based-subseries-note">
            <strong>Note:</strong> The volumes listed
            below contain at least one document from the period of this presidential
            administration; {hsg:administration-search-link($context)}. The <em>Foreign
            Relations</em> series was organized by year for the volumes covering
            1861–1951, triennially for 1952–1963, and by presidential administration
            for 1964 onward—with some exceptions.</p>
    else
        ()
};

(:~
 : "view and search within the available documents", a search scoped to the
 : president's term of office, reference parity with hsg-shell's
 : fh:admin-search-href. Term dates come from the travels data package's
 : presidents register; the taxonomy position + 14 maps an administration to
 : its president's ordinal, which is sound for every administration that
 : gets the note (one category per president up to kennedy; the combined
 : nixon-ford category sits after them and never renders it).
 :)
declare %private function hsg:administration-search-link($context as map(*)) as element(a) {
    let $ordinal := index-of(
            hsg:administrations()/tei:category/@xml:id/string(),
            $context?administration-id
        ) + 14
    let $president := doc("/db/apps/travels/presidents/presidents.xml")//president[@n = $ordinal]
    return
        <a href="{$context?context-path}/search?within=documents&amp;start-date={$president/took-office-date}&amp;end-date={$president/left-office-date}&amp;sort=date-asc"
            >view and search within the available documents</a>
};

(:~
 : "Volumes are grouped into X and Y categories." with in-page links, shown
 : only when more than one production track is in use, reference parity with
 : hsg-shell's fh:group-info including its list punctuation (Oxford comma
 : from three items up).
 :)
declare function hsg:administration-group-info($context as map(*)) as element(p)? {
    let $admin-id := $context?administration-id
    let $tracks := hsg:tracks-in-use(hsg:volumes-in-administration($admin-id), $admin-id)
    return
        if ($admin-id != 'pre-truman' and count($tracks) gt 1) then
            <p>Volumes are grouped into {
                for $track at $n in $tracks
                return (
                    <a href="#{$track}-volumes">{
                        $hsg:production-tracks[?id = $track]?label
                    }</a>,
                    if ($n lt count($tracks)) then
                        concat(
                            if (count($tracks) gt 2) then ', ' else (),
                            if ($n = count($tracks) - 1) then ' and ' else ()
                        )
                    else ()
                )
            } categories.</p>
        else
            ()
};

(:~
 : The volumes of one administration, reference parity with hsg-shell's
 : administrations.xml rendering chain: when several production tracks are
 : in use (nixon-ford, kennedy, ...), an h2 per track ("Regular volumes",
 : anchor {track}-volumes) in taxonomy order, each holding the track's
 : volumes grouped by sub-series; otherwise the sub-series groups alone. A
 : sub-series group is an h3 ("Foreign Relations of the United States,
 : 1981-1988") over a list of volumes with availability notices, ordered by
 : the sub-series' @n. pre-truman instead gets the reference's flat
 : chronological list of complete titles (frus:volumes-pre-truman); its
 : volumes predate administration-based sub-series, so sub-series grouping
 : would just repeat each title.
 :)
declare function hsg:administration-volumes($context as map(*)) {
    let $admin-id := $context?administration-id
    let $roots := hsg:volumes-in-administration($admin-id)
    return
        if (empty($roots)) then
            <p class="hsg-admin__empty">No volumes for this administration are available in this
                instance's data set.</p>
        else if ($admin-id = 'pre-truman') then
            <ol class="hsg-admin__volumes">
                {
                    for $root in $roots
                    let $title := normalize-space((hsg:resolve-include($root/tei:teiHeader, 'titleStmt')/tei:title)[1])
                    order by $root/@xml:id
                    return hsg:admin-volume-item($context, $root, $title)
                }
            </ol>
        else if (count(hsg:tracks-in-use($roots, $admin-id)) gt 1) then
            for $track in $hsg:production-tracks
            let $track-roots := $roots[hsg:production-track(., $admin-id) = $track?id]
            where exists($track-roots)
            return (
                <h2 id="{$track?id}-volumes" class="hsg-admin__track">{$track?label} volumes</h2>,
                hsg:sub-series-groups($context, $track-roots)
            )
        else
            hsg:sub-series-groups($context, $roots)
};

(:~
 : Sub-series groups over a set of volume roots: an h3 per sub-series in
 : sub-series order (@n), each over its volumes ordered by id, reference
 : parity with hsg-shell's fh:volumes-by-group / fh:volumes-by-administration
 : (including the "Other" fallback label for a volume without series titles).
 :)
declare %private function hsg:sub-series-groups($context as map(*), $roots as element(tei:TEI)*) {
    for $root in $roots
    let $seriesStmt := hsg:resolve-include($root/tei:teiHeader, 'seriesStmt')
    let $group := normalize-space(string-join((
            $seriesStmt/tei:title[@type = 'series'],
            $seriesStmt/tei:title[@type = 'sub-series']
        )[. != ''], ", "))
    group by $group
    order by ($seriesStmt/tei:title[@type = 'sub-series']/@n/string())[1]
    return (
        <h3 class="hsg-admin__sub-series">{($group[. != ''], 'Other')[1]}</h3>,
        <ul class="hsg-admin__volumes">
            {
                for $vol-root in $root
                let $volStmt := hsg:resolve-include($vol-root/tei:teiHeader, 'seriesStmt')
                let $label := normalize-space(string-join((
                        $volStmt/tei:title[@type = 'volume-number'],
                        $volStmt/tei:title[@type = 'volume']
                    )[. != ''], ", "))
                let $label := if ($label != '') then
                        $label
                    else
                        normalize-space(($volStmt/tei:title[@type = 'sub-series'])[1])
                order by $vol-root/@xml:id
                return hsg:admin-volume-item($context, $vol-root, $label)
            }
        </ul>
    )
};

declare %private function hsg:admin-volume-item($context as map(*), $root as element(tei:TEI), $label as xs:string) {
    <li>
        <a href="{$context?context-path}/historicaldocuments/{$root/@xml:id}">{$label}</a>
        {" "}
        <span class="hsg-status-notice">{hsg:volume-availability($root)}</span>
    </li>
};

(:~
 : Availability notice per volume, reference parity with hsg-shell's
 : fh:volume-availability-summary: published volumes list their formats, any
 : other revisionDesc status is shown humanized ("(Being Cleared)"). Full
 : text means the volume has a body collection; the v2 corpus also carries
 : root-only volumes without one.
 :)
declare %private function hsg:volume-availability($root as element(tei:TEI)) as xs:string {
    let $status := $root/tei:teiHeader//tei:revisionDesc/@status/string()
    return
        if ($status = 'published') then
            let $formats := (
                "Full Text"[xmldb:collection-available(util:collection-name($root) || "/body")],
                "Ebook"[$root/tei:teiHeader//tei:relatedItem[@type = 'epub']],
                "PDF"[$root/tei:teiHeader//tei:relatedItem[@type = 'pdf']]
            )
            return
                if (exists($formats)) then
                    "(Published and available in " || string-join($formats, ", ") || ")"
                else
                    "(Published)"
        else
            "(" ||
            string-join(
                for $word in tokenize(translate($status, '-', ' '), '\s+')
                return upper-case(substring($word, 1, 1)) || substring($word, 2),
                " ")
            || ")"
};

(:~
 : Breadcrumb for section pages that render without a document of their own
 : (the landing and the administration pages), where the layout's
 : hsg:collection-breadcrumbs is gated on $context?doc. Same trail contract
 : as dh:breadcrumb: Home > Historical Documents [> $trail].
 :)
declare function hsg:section-breadcrumb($context as map(*), $trail as map(*)*) as element(li)+ {
    (
        <li>
            <a href="{$context?context-path}/">
                <pb-i18n key="breadcrumb.home">Home</pb-i18n>
            </a>
        </li>,
        if (empty($trail)) then
            <li aria-current="page">
                <pb-i18n key="breadcrumb.historicaldocuments">Historical Documents</pb-i18n>
            </li>
        else
            <li>
                <a href="{$context?context-path}/historicaldocuments">
                    <pb-i18n key="breadcrumb.historicaldocuments">Historical Documents</pb-i18n>
                </a>
            </li>,
        for $crumb at $pos in $trail
        return
            if ($pos = count($trail)) then
                <li aria-current="page">{$crumb?label}</li>
            else
                <li>
                    <a href="{$context?context-path}{$crumb?href}">{$crumb?label}</a>
                </li>
    )
};

(:~
 : Generate the breadcrumb trail: Home > Historical Documents > volume title.
 : The volume title is the current (non-link) crumb only on the volume
 : landing page; on any interior page it links back there.
 :
 : When the page being viewed is itself a chapter, document, or compilation,
 : one more crumb -- the current (non-link), final one -- is appended on a
 : new line: the division's own title for a chapter or compilation, or
 : "Document <n>" (its encoded frus-document-number) for a document.
 :)
declare function hsg:collection-breadcrumbs($context as map(*)) {
    if (exists($context?doc)) then
        let $components := config:get-relpath($context?doc?content, $config:data-default) => tokenize("/")
        let $publication := $components[1]
        let $is-landing := count($components) = 2
        let $volume-title := hsg:volume-title($context?doc?content)
        let $division-type := ($context?doc?content//tei:bibl[@type='frus-division-type'])[1]/string()
        return (
            <li>
                <a href="{$context?context-path}/">
                    <pb-i18n key="breadcrumb.home">Home</pb-i18n>
                </a>
            </li>,
            <li>
                <a href="{$context?context-path}/historicaldocuments">
                    <pb-i18n key="breadcrumb.historicaldocuments">Historical Documents</pb-i18n>
                </a>
            </li>,
            if ($is-landing) then
                <li aria-current="page">{$volume-title}</li>
            else
                <li>
                    <a href="{$context?context-path}/historicaldocuments/{$publication}">{$volume-title}</a>
                </li>,
            if (not($is-landing) and $division-type = ('chapter', 'compilation')) then
                (: See hsg:split-title: the title may be split into a date
                   range and a subtitle. A breadcrumb cannot break lines, so
                   join with a space, as the reference breadcrumb does;
                   normalize-space for the same reason as there. :)
                let $own-title := $context?doc?content//tei:titleStmt/tei:title
                    => string-join(' ') => normalize-space()
                return <li class="breadcrumb-current" aria-current="page">{$own-title}</li>
            else if (not($is-landing) and $division-type = 'document') then
                let $number := ($context?doc?content//tei:bibl[@type='frus-document-number'])[1]/string()
                return <li class="breadcrumb-current" aria-current="page">Document {$number}</li>
            else ()
        )

    else ()
};

(:~
 : The volume landing page's main content: title, cover, editors, publisher
 : info, and the full table of contents (#1080). Replaces the ODD transform
 : for this page entirely -- app chrome (cover image, download links, byte
 : formatting), not generic TEI rendering, the same reasoning that already
 : keeps hsg:volume-toc/hsg:volume-list/hsg:collection-breadcrumbs outside
 : the ODD pipeline.
 :)
declare function hsg:volume-landing-content($context as map(*)) {
    let $doc := $context?doc?content
    return
    if (not(exists($doc))) then ()
    else
        let $volume-id := config:get-relpath($doc, $config:data-default) => tokenize("/") => head()
        (: titleStmt/publicationStmt are xincluded from the volume's shared
           *_includes.xml; see hsg:resolve-include. notesStmt is inline, so
           hsg:volume-cover and hsg:volume-ways-to-explore don't need it. :)
        let $header := $doc//tei:teiHeader
        let $titleStmt := hsg:resolve-include($header, 'titleStmt')
        let $publicationStmt := hsg:resolve-include($header, 'publicationStmt')
        let $title := normalize-space(($titleStmt/tei:title)[1])
        (: One root element: the layout's main is a flex row whose children
           each get flex: 1 (resources/css/layout.css, .sticky-layout > main
           > *), so returning these as siblings lays them out as columns
           instead of stacking them -- same pitfall templates/pages/
           historicaldocuments.html's own comment warns about. :)
        return
            <div class="hsg-frus__landing">
                <h1>{$title}</h1>
                {hsg:volume-cover($doc, $volume-id, $title)}
                <div class="hsg-frus__meta">
                    {hsg:volume-editors($titleStmt)}
                    {hsg:volume-published-info($publicationStmt)}
                </div>
                {hsg:volume-landing-toc($context)}
            </div>
};

(:~
 : The volume's cover image, if it has one. Reference parity with hsg-shell
 : (fh:cover-uri): the URL is built from the volume id rather than read from
 : notesStmt's own @target -- matches the data in practice, and is what the
 : reference site does. Gated on the *volume-scoped* jpg relatedItem's
 : existence (@corresp = "#" || the volume id, as fh:exists-cover-image
 : does; see hsg:volume-ways-to-explore on why the bare @type is not
 : enough), not the constructed URL's reachability, so a volume with no
 : cover renders no <img>, same as hsg-shell.
 :)
declare %private function hsg:volume-cover($doc as node(), $volume-id as xs:string, $title as xs:string) as element(img)? {
    if (exists($doc//tei:notesStmt/tei:relatedItem[@type = 'jpg'][@corresp = '#' || $volume-id])) then
        <img class="hsg-frus__cover"
            src="https://static.history.state.gov/frus/{$volume-id}/covers/{$volume-id}.jpg"
            alt="Book Cover of {$title}"/>
    else ()
};

(:~
 : Editor / General Editor bylines. Reference parity with hsg-shell:
 : titleStmt/editor[@role='primary'] labeled "Editor:" ("Editors:" if more
 : than one), editor[@role='general'] labeled "General Editor:". Takes the
 : already-resolved titleStmt from hsg:volume-landing-content rather than
 : re-resolving it.
 :)
declare %private function hsg:volume-editors($titleStmt as node()?) {
    let $primary := $titleStmt/tei:editor[@role = 'primary'][normalize-space(.) != '']
    let $general := $titleStmt/tei:editor[@role = 'general'][normalize-space(.) != '']
    return (
        if (exists($primary)) then (
            <div class="hsg-frus__editor-label">{if (count($primary) gt 1) then 'Editors:' else 'Editor:'}</div>,
            <ul class="hsg-list-editors">{for $editor in $primary return <li>{normalize-space($editor)}</li>}</ul>
        ) else (),
        if (exists($general)) then (
            <div class="hsg-frus__editor-label">General Editor:</div>,
            <ul class="hsg-list-editors">{for $editor in $general return <li>{normalize-space($editor)}</li>}</ul>
        ) else ()
    )
};

(:~
 : Publisher, place, and publication year. Reference parity with hsg-shell:
 : publicationStmt/publisher, /pubPlace, /date[@type='publication-date'] --
 : not the content-date range, which hsg-shell doesn't show here either.
 :)
declare %private function hsg:volume-published-info($publicationStmt as node()?) {
    let $publisher := normalize-space($publicationStmt/tei:publisher)
    let $place := normalize-space($publicationStmt/tei:pubPlace)
    let $year := normalize-space($publicationStmt/tei:date[@type = 'publication-date'])
    return
        <div class="hsg-frus__published">
            {if ($publisher != '') then <span class="hsg-frus__publisher">{$publisher}</span> else ()}
            {if ($place != '') then <span class="hsg-frus__pubplace">{$place}</span> else ()}
            {if ($year != '') then <span class="hsg-frus__pubdate">{$year}</span> else ()}
        </div>
};

(:~
 : The volume landing page's own table of contents, in main content rather
 : than the sidebar (#1080): front matter flat, the compilation with its
 : chapters nested beneath (each annotated with its document range,
 : reference parity with hsg-shell), then back matter. Documents are never
 : listed.
 :
 : Reuses hsg:toc-divisions -- the same generic, whole-collection map -- but
 : not hsg:toc-entries: this shape is a plain nested list with document
 : ranges, not a usa-sidenav with a "current page" highlight (every entry is
 : equally "not current" on the landing page).
 :
 : Walks text//xi:include (front, body, and back all live under one <text>),
 : not text/body//xi:include like the ODD model this replaces did -- that
 : hardcoded "body" is why front and back matter never appeared before.
 :)
declare function hsg:volume-landing-toc($context as map(*)) as element(ul)? {
    let $doc := $context?doc?content
    return
    if (not(exists($doc))) then ()
    else
        let $publication := config:get-relpath($doc, $config:data-default) => tokenize("/") => head()
        let $divisions := hsg:toc-divisions($publication)
        return
            <ul class="hsg-frus__toc">
                {hsg:landing-toc-entries($doc/tei:TEI, $divisions, $publication, $context)}
            </ul>
};

declare %private function hsg:landing-toc-entries($division as element(tei:TEI)?, $divisions as map(*),
        $publication as xs:string, $context as map(*)) {
    for $include in $division//tei:text//xi:include
    let $id := $include/@xpointer/string()
    where map:contains($divisions, $id)
    let $included := $divisions($id)
    (: hsg-shell inserts a <br/> between date-range title and subtitle here
       too; shared logic in hsg:split-title (OP#1085). :)
    let $title := hsg:split-title($included//tei:fileDesc//tei:titleStmt/tei:title)
    let $range-label := hsg:document-range-label(hsg:document-range($included))
    (: Unpublished division: muted, reference parity with hsg-shell's
       li.pending. See hsg:toc-entries. :)
    let $is-pending := ends-with(normalize-space(($included//tei:bibl[@type='frus-division-type'])[1]), '-pending')
    let $children := hsg:landing-toc-entries($included, $divisions, $publication, $context)
    return
        <li class="{if ($is-pending) then 'pending' else ''}">
            <a href="{$context?context-path}/historicaldocuments/{$publication}/{$id}">{$title}</a>
            {$range-label}
            {if (exists($children)) then <ul>{$children}</ul> else ()}
        </li>
};

(:~
 : The first and last document numbers under a division's own xi:include
 : tree, for a TOC entry's "(Documents N-M)" suffix. Reference parity with
 : hsg-shell, which read this off a @n attribute the unbound data model
 : doesn't have -- frus-document-number is the equivalent here (numeric, or
 : alphabetic for the appendix: "A".."C").
 :
 : Opens only the first and last leaf document at each level, not every one
 : -- the same performance discipline as hsg:toc-divisions.
 :)
declare %private function hsg:document-range($division as element(tei:TEI)?) as xs:string* {
    let $includes := $division//tei:text//xi:include
    return
        if (empty($includes)) then ()
        else (
            hsg:leading-document-number($includes[1], true()),
            hsg:leading-document-number($includes[last()], false())
        )
};

declare %private function hsg:leading-document-number($include as element(xi:include), $want-first as xs:boolean) as xs:string? {
    let $root := root(id($include/@xpointer, doc(util:collection-name($include) || '/' || $include/@href)))
    let $type := ($root//tei:bibl[@type = 'frus-division-type'])[1]/string()
    return
        (: Documents, published ('document') or not ('document-pending'). An
           unpublished document carries no frus-document-number, so fall back to
           the number encoded in its division id ("d148" -> "148"). This is what
           lets a pending chapter (France) still show "(Documents 148-214)",
           reference parity with hsg-shell. :)
        if (starts-with($type, 'document')) then
            let $num := normalize-space(($root//tei:bibl[@type = 'frus-document-number'])[1])
            return
                if ($num != '') then $num
                else tokenize(replace(normalize-space(($root//tei:bibl[@type = 'frus-division-id'])[1]), '^d', ''), '-')[1]
        else
            let $inner := $root//tei:text//xi:include
            return
                if (empty($inner)) then ()
                else if ($want-first) then hsg:leading-document-number($inner[1], true())
                else hsg:leading-document-number($inner[last()], false())
};

declare %private function hsg:document-range-label($range as xs:string*) as xs:string? {
    if (count($range) != 2 or $range[1] = '' or $range[2] = '') then ()
    else if ($range[1] = $range[2]) then ' (Document ' || $range[1] || ')'
    else ' (Documents ' || $range[1] || '–' || $range[2] || ')'
};

(:~
 : The volume landing page's "Ways to Explore" sidebar panel, rendered into
 : the layout's `after` (right-hand) block by templates/pages/volume/
 : landing.html: search-within-volume, ebook downloads with sizes, and the
 : GPO bookstore link. Reference parity with hsg-shell.
 :
 : Points at /search (#1102, not yet merged as of writing) -- the route
 : won't resolve until that PR lands, the normal state for a route built
 : ahead of a dependency in this repo's parallel-PR workflow.
 :
 : Each ebook link is independently gated on its own relatedItem's
 : existence (fh:exists-epub/-mobi/-pdf in hsg-shell), so a volume missing
 : one format just omits that link rather than erroring.
 :)
declare function hsg:volume-ways-to-explore($context as map(*)) {
    let $doc := $context?doc?content
    return
    if (not(exists($doc))) then ()
    else
        let $volume-id := config:get-relpath($doc, $config:data-default) => tokenize("/") => head()
        (: Volume-scoped items only. A volume's notesStmt also carries a
           relatedItem per *associated file* -- frus1958-60v05mSupp, a
           microfiche supplement, has 562 type="pdf" entries, one per
           document -- and those are told apart from the volume's own
           download solely by @corresp pointing at the volume id. Reference
           parity with hsg-shell's fh:exists-pdf / fh:exists-epub / etc.,
           which all gate on @corresp eq "#" || $vol-id for this reason.
           Without the gate the ebook links below select all 562 and die
           with a cardinality error. :)
        let $related := $doc//tei:notesStmt/tei:relatedItem[@corresp = '#' || $volume-id]
        return
            <div class="hsg-panel hsg-frus__ways-to-explore">
                <h2 class="hsg-sidebar-title">
                    <pb-i18n key="historicaldocuments.waysToExplore">Ways to Explore</pb-i18n>
                </h2>
                <form action="{$context?context-path}/search" method="GET" class="usa-search usa-search--small" role="search">
                    <label class="usa-sr-only" for="frus-search-q">
                        <pb-i18n key="search.search">Search</pb-i18n>
                    </label>
                    <p><pb-i18n key="historicaldocuments.searchInsideVolume">Search inside this volume</pb-i18n></p>
                    <input id="frus-search-q" class="usa-input" name="q" type="search"/>
                    <button class="usa-button" type="submit">
                        <pb-i18n key="search.search">Search</pb-i18n>
                    </button>
                    <input name="volume-id" type="hidden" value="{$volume-id}"/>
                </form>
                <ul class="hsg-list-group hsg-frus__downloads">
                    <li>
                        <pb-i18n key="historicaldocuments.download">Download:</pb-i18n>
                        <ul class="hsg-ebook-list">
                            {hsg:ebook-link($related, 'epub', 'EPUB')}
                            {hsg:ebook-link($related, 'mobi', 'Mobi')}
                            {hsg:ebook-link($related, 'pdf', 'PDF')}
                        </ul>
                    </li>
                    <li>
                        <pb-i18n key="historicaldocuments.browseGpoPrefix">Browse the</pb-i18n>
                        {' '}<a href="https://bookstore.gpo.gov/catalog/foreign-relations-united-states-series-frus">U.S. Government Bookstore (GPO)</a>
                    </li>
                </ul>
            </div>
};

declare %private function hsg:ebook-link($related as element()*, $type as xs:string, $label as xs:string) {
    (: [1]: callers pass the volume-scoped relatedItems, so one per type is
       expected; take the first regardless rather than let stray duplicate
       encoding turn a download link into a 500. :)
    let $item := ($related[@type = $type])[1]
    return
    if (not(exists($item))) then ()
    else
        let $href := ($item//tei:ref/@target/string())[1]
        let $bytes := ($item//tei:measure/@quantity)[1] ! xs:integer(.)
        return
            <li>
                <a class="hsg-link-button" href="{$href}">{$label} (<span>{hsg:bytes-to-readable($bytes)}</span>)</a>
            </li>
};

(:~
 : Format a byte count the way hsg-shell's app:bytes-to-readable does:
 : over 1,000,000 bytes as N.NNmb, over 1,000 as Nkb. Used for the ebook
 : download sizes in the "Ways to Explore" panel.
 :)
declare %private function hsg:bytes-to-readable($bytes as xs:integer?) as xs:string {
    if (empty($bytes)) then 'unknown'
    else if ($bytes gt 1000000) then (round($bytes div 10000) div 100) || 'mb'
    else if ($bytes gt 1000) then round($bytes div 1000) || 'kb'
    else $bytes || ' bytes'
};

(:~
 : Right-hand sidebar panels for interior division pages (PR #32 review):
 : Persons and Abbreviations &amp; Terms panels listing the registered
 : entities the current division references. Data-driven panels only; the
 : static Historical Documents section navigation is not built here but
 : included as a template partial by templates/pages/volume/interior.html's
 : `after` block, the same sidebar.html every other page in the section
 : mounts. Rendered into the layout's `after` block by that template,
 : mirroring how the volume landing mounts hsg:volume-ways-to-explore.
 :
 : Reference parity with hsg-shell's fh:facets/fh:view-persons/fh:view-gloss
 : plus the site.xml "sections" aside, with one structural difference: shell
 : resolved #p_X / #t_X ids with id() inside the same monolithic volume
 : document, while frus-v2-data keeps the registers in separate front-matter
 : files (front/persons.xml, front/terms.xml) where the entries are marked
 : persName/term @sameAs="#p_X" rather than @xml:id -- so the lookup is a
 : cross-file @sameAs match.
 :)
declare function hsg:division-asides($context as map(*)) {
    let $doc := $context?doc?content
    return
    if (not(exists($doc))) then ()
    else
        let $type := normalize-space(($doc//tei:bibl[@type='frus-division-type'])[1])
        let $subtype := normalize-space(($doc//tei:bibl[@type='frus-division-subtype'])[1])
        (: fh:facets parity: no persons/terms panels on container listings
           (compilation, chapter) or the index. Other divisions collect their
           references below; the register list pages themselves mark entries
           with @sameAs, not @corresp/@target, so they naturally list
           nothing. :)
        let $show-registers := not($type = 'compilation' or starts-with($type, 'chapter') or $subtype = 'index')
        let $publication := config:get-relpath($doc, $config:data-default) => tokenize("/") => head()
        return (
            if ($show-registers) then (
                hsg:register-panel($context, $publication,
                    'historicaldocuments.persons', 'Persons', 'persons',
                    $doc//tei:persName/@corresp,
                    doc($config:data-default || "/" || $publication || "/front/persons.xml")//tei:persName[@sameAs]),
                hsg:register-panel($context, $publication,
                    'historicaldocuments.terms', 'Abbreviations &amp; Terms', 'terms',
                    $doc//tei:gloss/@target,
                    doc($config:data-default || "/" || $publication || "/front/terms.xml")//tei:term[@sameAs])
            ) else ()
        )
};

(:~
 : One register panel (Persons or Abbreviations &amp; Terms): every distinct
 : reference the division makes, resolved against the volume's register list
 : and rendered as a link to the register page with the entry's description
 : as its tooltip -- fh:get-persons/fh:get-gloss parity, including the
 : name-sorted order and the hide-if-empty behaviour (a division with no
 : references gets no panel).
 :
 : Both sides are grouped rather than scanned (PR #32 review): $idrefs arrives
 : with duplicates (a division names the same person up to 249 times) and the
 : register runs to 441 entries, so pairing them with a predicate lookup per
 : reference walked the register once per distinct id. One group-by pass over
 : each side turns that into a map lookup, and drops the caller's own
 : distinct-values with it -- grouping the references dedupes them anyway.
 :)
declare %private function hsg:register-panel($context as map(*), $publication as xs:string,
        $key as xs:string, $label as xs:string, $page as xs:string,
        $idrefs as node()*, $register as element()*) {
    let $byId := map:merge(
        for $entry in $register
        group by $id := string($entry/@sameAs)
        return map:entry($id, head($entry))
    )
    let $entries :=
        for $ref in $idrefs
        group by $idref := string($ref)
        let $name := $byId($idref)
        where exists($name)
        let $display := normalize-space($name)
        order by $display
        return
            <li>
                <a href="{$context?context-path}/historicaldocuments/{$publication}/{$page}{$idref}"
                    title="{hsg:register-description($name)}">{$display}</a>
            </li>
    return
        if (empty($entries)) then ()
        else
            <div class="hsg-panel hsg-frus__register">
                <h2 class="hsg-sidebar-title">
                    <pb-i18n key="{$key}">{$label}</pb-i18n>
                </h2>
                <ul class="hsg-list-group">{$entries}</ul>
            </div>
};

(:~
 : A register entry's description: the text following the name -- following
 : siblings of the wrapping hi when the name sits inside one (the usual
 : encoding: item/hi/persName), of the name itself otherwise -- with the
 : leading comma stripped. fh:get-persons/fh:get-gloss parity.
 :)
declare %private function hsg:register-description($name as element()) as xs:string {
    let $following :=
        if ($name/parent::tei:hi) then
            $name/parent::tei:hi/following-sibling::node()
        else
            $name/following-sibling::node()
    return normalize-space(replace(string-join($following, ''), '^\s*,\s*', ''))
};

(:~
 : A chapter or compilation listing page: the division title, previous/next
 : navigation, and each child as an entry -- documents with their number,
 : title, dateline, source note and (when present) a summary; child divisions
 : (a compilation's chapters) as a titled link with a document range. Replaces
 : the ODD's bare bulleted list of titles, reference parity with hsg-shell's
 : toc:document-list. Rendered by templates/pages/volume/interior.html for a
 : chapter or compilation instead of the volume-interior ODD transform.
 :)
declare function hsg:division-listing($context as map(*)) {
    let $doc := $context?doc?content
    return
    if (not(exists($doc))) then ()
    else
        let $publication := ($doc//tei:bibl[@type='frus-volume-id'])[1]/string()
        (: Line break between date-range title and subtitle, reference parity
           (OP#1085). :)
        let $title := hsg:split-title($doc//tei:teiHeader//tei:titleStmt/tei:title)
        let $type := normalize-space(($doc//tei:bibl[@type='frus-division-type'])[1])
        return
            <div class="hsg-frus__division">
                <h1 class="hsg-frus__division-title">{$title}</h1>
                {hsg:prev-next($context)}
                {(: A compilation lists its chapters under a "Contents" heading,
                    reference parity with hsg-shell's document-list. :)
                 if ($type = 'compilation') then <h2 class="hsg-frus__contents">Contents</h2> else ()}
                <div class="hsg-frus__doclist">
                    {
                        (: Walk the parent's xi:include order -- that is document
                           order -- opening each target file once (as
                           hsg:toc-divisions notes, a chapter has ~18-70 of
                           these, an acceptable cost for a listing page). :)
                        for $inc in $doc//tei:text//xi:include
                        let $target := doc(util:collection-name($inc) || '/' || $inc/@href)/tei:TEI
                        where exists($target)
                        let $type := normalize-space(($target//tei:bibl[@type='frus-division-type'])[1])
                        return
                            if (starts-with($type, 'document')) then
                                hsg:doclist-document($target, $publication, $type, $context)
                            else
                                hsg:doclist-division($target, $publication, $type, $context)
                    }
                </div>
            </div>
};

(:~ One document entry in a chapter listing: number-prefixed title link,
 : dateline, summary and source note. An unpublished ('document-pending')
 : document is shown muted and unlinked -- it has no page of its own yet. :)
declare %private function hsg:doclist-document($target as element(tei:TEI), $publication as xs:string,
        $type as xs:string, $context as map(*)) {
    let $number := normalize-space(($target//tei:bibl[@type='frus-document-number'])[1])
    let $id := normalize-space(($target//tei:bibl[@type='frus-division-id'])[1])
    let $head := normalize-space(($target//tei:text/tei:body//tei:head)[1])
    (: The head already begins with the number ("72. Telegram..."); fall back
       to a synthesised label only for a pending document with no real head. :)
    let $title := if ($head != '') then $head else ('Document ' || $number)
    let $dateline := normalize-space(($target//tei:text/tei:body//tei:opener/tei:dateline)[1])
    let $summary := normalize-space(($target//tei:standOff//tei:note[@type='summary'])[1])
    let $source := normalize-space(($target//tei:standOff//tei:note[@type='source'])[1])
    let $pending := ends-with($type, '-pending')
    return
        <div class="hsg-frus__doc-entry{if ($pending) then ' pending' else ''}">
            <h4 class="hsg-frus__doc-title">
                {
                    if ($pending or $id = '') then
                        <span>{$title}</span>
                    else
                        <a href="{$context?context-path}/historicaldocuments/{$publication}/{$id}">{$title}</a>
                }
            </h4>
            {if ($dateline != '') then <p class="dateline">{$dateline}</p> else ()}
            {if ($summary != '') then <p class="summary">{$summary}</p> else ()}
            {if ($source != '') then <p class="sourcenote">{$source}</p> else ()}
        </div>
};

(:~ A child division (e.g. a compilation's chapters): a titled link with its
 : document range, muted when unpublished. :)
declare %private function hsg:doclist-division($target as element(tei:TEI), $publication as xs:string,
        $type as xs:string, $context as map(*)) {
    let $id := normalize-space(($target//tei:bibl[@type='frus-division-id'])[1])
    (: Line break between date-range title and subtitle, reference parity
       (OP#1085). :)
    let $title := hsg:split-title($target//tei:teiHeader//tei:titleStmt/tei:title)
    let $range := hsg:document-range-label(hsg:document-range($target))
    let $pending := ends-with($type, '-pending')
    return
        <div class="hsg-frus__doc-entry hsg-frus__division-entry{if ($pending) then ' pending' else ''}">
            <h4 class="hsg-frus__doc-title">
                <a href="{$context?context-path}/historicaldocuments/{$publication}/{$id}">{$title}</a>
                {$range}
            </h4>
        </div>
};

(:~
 : Previous / next navigation for a division page, built from the document's own
 : relatedItem prev/next targets (relative file paths in notesStmt). Reference
 : parity with hsg-shell's reading order, which descends into and ascends out of
 : the volume tree (a chapter's "next" is its first document; a document's
 : "next" is the following document, or the next chapter at a boundary).
 :)
declare function hsg:prev-next($context as map(*)) {
    let $doc := $context?doc?content
    return
    if (not(exists($doc))) then ()
    else
        let $base := util:collection-name(root($doc))
        let $type := normalize-space(($doc//tei:bibl[@type='frus-division-type'])[1])
        let $notesStmt := $doc//tei:notesStmt
        (: A chapter's "previous" is its parent compilation -- one level up, e.g.
           back to "Western Europe" -- not the previous chapter's last document
           (which for a pending chapter would be an unnumbered "Document"). Its
           "next" is its first document. Reference parity with hsg-shell, where
           both Canada and FRG point back to the compilation. Documents keep the
           encoded prev/next reading order. :)
        let $prevTarget :=
            if (starts-with($type, 'chapter')) then
                ($notesStmt/tei:relatedItem[@type='parent']/@target)[1]
            else
                ($notesStmt/tei:relatedItem[@type='prev']/@target)[1]
        let $prev := hsg:nav-target($base, $prevTarget)
        let $next := hsg:nav-target($base, ($notesStmt/tei:relatedItem[@type='next']/@target)[1])
        return
            if (empty($prev) and empty($next)) then ()
            else
                <nav class="hsg-frus__pager" aria-label="Document navigation">
                    {
                        if (exists($prev)) then
                            <a class="hsg-frus__pager-link hsg-frus__pager-prev" rel="prev"
                                href="{$context?context-path}/historicaldocuments/{$prev?publication}/{$prev?id}">
                                <span class="hsg-frus__pager-arrow" aria-hidden="true">&#8592;</span>
                                <span class="hsg-frus__pager-label">{$prev?label}</span>
                            </a>
                        else <span class="hsg-frus__pager-link hsg-frus__pager-empty"/>
                    }
                    {
                        if (exists($next)) then
                            <a class="hsg-frus__pager-link hsg-frus__pager-next" rel="next"
                                href="{$context?context-path}/historicaldocuments/{$next?publication}/{$next?id}">
                                <span class="hsg-frus__pager-label">{$next?label}</span>
                                <span class="hsg-frus__pager-arrow" aria-hidden="true">&#8594;</span>
                            </a>
                        else <span class="hsg-frus__pager-link hsg-frus__pager-empty"/>
                    }
                </nav>
};

(:~ Resolve one relatedItem target (a file path relative to the current
 : division's own file) to the linked division's id, publication and a short
 : label. :)
declare %private function hsg:nav-target($base as xs:string, $rel as xs:string?) as map(*)? {
    if (empty($rel) or normalize-space($rel) = '') then ()
    else
        let $path := hsg:resolve-relative($base, $rel)
        let $target := doc($path)/tei:TEI
        return
            if (not(exists($target))) then ()
            else
                let $id := normalize-space(($target//tei:bibl[@type='frus-division-id'])[1])
                let $type := normalize-space(($target//tei:bibl[@type='frus-division-type'])[1])
                let $publication := normalize-space(($target//tei:bibl[@type='frus-volume-id'])[1])
                let $label :=
                    if (starts-with($type, 'document')) then
                        'Document ' || normalize-space(($target//tei:bibl[@type='frus-document-number'])[1])
                    else
                        normalize-space(string-join($target//tei:teiHeader//tei:titleStmt/tei:title, ' '))
                return
                    if ($id = '' or $publication = '') then ()
                    else map { "id": $id, "publication": $publication, "label": $label }
};

(:~ Resolve a "../a/b.xml"-style relative path against a base collection path,
 : returning the absolute database path. Used to follow relatedItem targets. :)
declare %private function hsg:resolve-relative($base as xs:string, $rel as xs:string) as xs:string {
    let $baseParts := tokenize($base, '/')[. != '']
    let $relParts := tokenize($rel, '/')[. != '']
    let $combined :=
        fold-left($relParts, $baseParts, function($acc, $part) {
            if ($part = '..') then $acc[position() != last()]
            else ($acc, $part)
        })
    return '/' || string-join($combined, '/')
};

(:~
 : Newest FRUS volumes as landing-page "Latest Publications" cards (#1258).
 :
 : Enumerates the volume collections under $config:data-default (mirrors
 : about:recent-publications / hsg:volume-list), reads each volume header's
 : publication date -- publicationStmt/date/@when when the encoding carries it,
 : otherwise the published revisionDesc/change -- and returns the newest $n as
 : tei:item elements in the shared landing card encoding consumed by
 : uswds:cards / uswds-landing.odd: a figure/graphic cover, the "Historical
 : Documents" + year tags, a head linking to the volume landing page, and a
 : teaser drawn from the volume abstract when present.
 :
 : Returns the empty sequence when no dated volume is found (or the collection
 : is absent), so uswds:cards falls back to the editorially authored items in
 : the landing document -- the hybrid data contract of OP#1094.
 :)
declare function hsg:latest-publications($context as map(*), $n as xs:integer) as element(tei:item)* {
    try {
        let $base := $config:data-default
        let $cards :=
            for $id in xmldb:get-child-collections($base)
            let $path := $base || "/" || $id || "/" || $id || ".xml"
            where doc-available($path)
            let $header := doc($path)//tei:teiHeader
            (: titleStmt/publicationStmt are xincluded from the volume's shared
               *_includes.xml in the frus-unbound-alpha model, so resolve them
               through hsg:resolve-include rather than a plain descendant step. :)
            let $when := head((
                hsg:resolve-include($header, 'publicationStmt')//tei:date/@when[. castable as xs:date],
                $header//tei:revisionDesc/tei:change[@status = 'published']/@when[. castable as xs:date]
            ))
            where exists($when)
            let $title := normalize-space((hsg:resolve-include($header, 'titleStmt')//tei:title)[1])
            where $title != ""
            let $teaser := normalize-space(($header/root()//tei:abstract//tei:p)[1])
            order by xs:date($when) descending
            return map {
                "id": $id,
                "year": year-from-date(xs:date($when)),
                "title": $title,
                "teaser": $teaser
            }
        for $card in subsequence($cards, 1, $n)
        return
            <tei:item>
                <tei:figure>
                    <tei:graphic url="https://static.history.state.gov/frus/{$card?id}/covers/{$card?id}.jpg"/>
                    <tei:figDesc>Cover of {$card?title}</tei:figDesc>
                </tei:figure>
                <tei:term>Historical Documents</tei:term>
                <tei:term>{string($card?year)}</tei:term>
                <tei:head>
                    <tei:ref target="historicaldocuments/{$card?id}">{$card?title}</tei:ref>
                </tei:head>
                { if ($card?teaser != "") then <tei:p>{$card?teaser}</tei:p> else () }
            </tei:item>
    } catch * {
        ()
    }
};

(:~
 : The "Guide to Sources on Vietnam, 1969-1975" TEI monograph (OP#1301),
 : from the other-publications data package, rendered as a single page.
 : hsg-shell transformed it with the frus ODD; the guide's element inventory
 : (div/head/hi/p/lb/ref) is plain TEI the default ODD covers. Its ref
 : targets are absolute production URLs and stay untouched, exactly as the
 : reference's app:fix-links (which only rewrote $app-prefixed hrefs) left
 : them.
 :)
declare function hsg:vietnam-guide($context as map(*)) {
    page:transform(
        doc("/db/apps/other-publications/vietnam-guide/guide-to-sources-on-vietnam-1969-1975.xml")
            //tei:body/*)
};
