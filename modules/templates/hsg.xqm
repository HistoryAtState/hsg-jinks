xquery version "3.1";

module namespace hsg="https://history.state.gov/ns/templates/hsg";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace xi="http://www.w3.org/2001/XInclude";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "../config.xqm";

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
        for $division in collection($config:data-default || "/" || $publication)/tei:TEI
            [tei:teiHeader//tei:bibl[@type='frus-division-type'] != 'document']
        where normalize-space(($division//tei:bibl[@type='frus-division-subtype'])[1]) != 'table-of-contents'
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
declare %private function hsg:toc-entries($division as element(tei:TEI)?, $divisions as map(*),
        $publication as xs:string, $current as xs:string?, $current-is-document as xs:boolean,
        $context as map(*)) {
    for $include in $division//tei:text//xi:include
    let $id := $include/@xpointer/string()
    where map:contains($divisions, $id)
    let $included := $divisions($id)
    (: A chapter/compilation title may be split across two title elements (a
       date range plus a descriptive subtitle, frus-unbound-alpha); join both
       rather than showing only the date range. :)
    let $title := normalize-space(string-join($included//tei:fileDesc//tei:titleStmt/tei:title, ''))
    (: current when it is the page being viewed, or -- on a document page, where
       the document itself is not listed -- when it is the division including it :)
    let $is-current :=
        $id = $current or
        ($current-is-document and exists($included//tei:text//xi:include[@xpointer = $current]))
    let $children := hsg:toc-entries($included, $divisions, $publication, $current, $current-is-document, $context)
    return
        <li class="usa-sidenav__item">
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
        let $volume := doc($config:data-default || "/" || $publication || "/" || $publication || ".xml")
        (: see hsg:resolve-include / hsg:volume-list. :)
        let $volume-titleStmt := hsg:resolve-include($volume//tei:teiHeader, 'titleStmt')
        let $volume-title := normalize-space(($volume-titleStmt/tei:title)[1])
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
                (: See hsg:toc-entries: the title may be split into a date
                   range and a subtitle; join both. :)
                let $own-title := normalize-space(string-join($context?doc?content//tei:titleStmt/tei:title, ''))
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
        (: titleStmt/editor/publicationStmt are xincluded from the volume's
           shared *_includes.xml; see hsg:volume-list for why this needs
           util:expand(). notesStmt is inline, so hsg:volume-cover and
           hsg:volume-ways-to-explore don't need it. :)
        let $header := util:expand($doc//tei:teiHeader)
        let $title := normalize-space(($header//tei:titleStmt/tei:title)[1])
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
                    {hsg:volume-editors($header)}
                    {hsg:volume-published-info($header)}
                </div>
                {hsg:volume-landing-toc($context)}
            </div>
};

(:~
 : The volume's cover image, if it has one. Reference parity with hsg-shell
 : (fh:cover-uri): the URL is built from the volume id rather than read from
 : notesStmt's own @target -- matches the data in practice, and is what the
 : reference site does. Gated on the jpg relatedItem's existence, not the
 : constructed URL's reachability, so a volume with no cover renders no
 : <img>, same as hsg-shell.
 :)
declare %private function hsg:volume-cover($doc as node(), $volume-id as xs:string, $title as xs:string) as element(img)? {
    if (exists($doc//tei:notesStmt/tei:relatedItem[@type = 'jpg'])) then
        <img class="hsg-frus__cover"
            src="https://static.history.state.gov/frus/{$volume-id}/covers/{$volume-id}.jpg"
            alt="Book Cover of {$title}"/>
    else ()
};

(:~
 : Editor / General Editor bylines. Reference parity with hsg-shell:
 : titleStmt/editor[@role='primary'] labeled "Editor:" ("Editors:" if more
 : than one), editor[@role='general'] labeled "General Editor:". Takes the
 : already-expanded header from hsg:volume-landing-content rather than
 : re-expanding per field.
 :)
declare %private function hsg:volume-editors($header as node()?) {
    let $primary := $header//tei:titleStmt/tei:editor[@role = 'primary'][normalize-space(.) != '']
    let $general := $header//tei:titleStmt/tei:editor[@role = 'general'][normalize-space(.) != '']
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
declare %private function hsg:volume-published-info($header as node()?) {
    let $publisher := normalize-space($header//tei:publicationStmt/tei:publisher)
    let $place := normalize-space($header//tei:publicationStmt/tei:pubPlace)
    let $year := normalize-space($header//tei:publicationStmt/tei:date[@type = 'publication-date'])
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
    let $title-parts := $included//tei:fileDesc//tei:titleStmt/tei:title
    (: A date-range title plus a descriptive subtitle (frus-unbound-alpha)
       reads as a run-on without a break between them -- hsg-shell inserts
       a <br/> here too. :)
    let $title :=
        if (count($title-parts) gt 1) then (
            normalize-space($title-parts[1]),
            <br/>,
            normalize-space(string-join($title-parts[position() gt 1], ' '))
        ) else
            normalize-space($title-parts)
    let $range-label := hsg:document-range-label(hsg:document-range($included))
    let $children := hsg:landing-toc-entries($included, $divisions, $publication, $context)
    return
        <li>
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
        if ($type = 'document') then
            ($root//tei:bibl[@type = 'frus-document-number'])[1]/string()
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
        let $related := $doc//tei:notesStmt/tei:relatedItem
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
    let $item := $related[@type = $type]
    return
    if (not(exists($item))) then ()
    else
        let $href := $item//tei:ref/@target/string()
        let $bytes := xs:integer($item//tei:measure/@quantity)
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
