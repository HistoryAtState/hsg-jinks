xquery version "3.1";

module namespace fh="https://history.state.gov/ns/templates/frus-history";

import module namespace page="http://teipublisher.com/ns/templates/page" at "page.xqm";
import module namespace pages="http://www.tei-c.org/tei-simple/pages" at "../lib/pages.xql";
import module namespace nav="http://www.tei-c.org/tei-simple/navigation" at "../navigation.xql";
import module namespace hsg="https://history.state.gov/ns/templates/hsg" at "hsg.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : The FRUS History subsection (OP#1294), backed by the frus-history data
 : package: one monolithic TEI monograph ("Toward 'Thorough, Accurate, and
 : Reliable'", frozen since 2015) whose divisions are addressed by @xml:id --
 : the conferences/departmenthistory shape (conf:*, dh:monograph-*), not the
 : xinclude-split FRUS volume shape -- plus three sibling collections:
 : documents/ (63 declassified TEI documents), articles/ (32 TEI research
 : posts, 28 of which carry a tei:author and are the ones listed, reference
 : parity with hsh-shell's fhh:articles-list author filter), and events/
 : (13 non-TEI <event> records holding stored XHTML fragments).
 :
 : Ported from hsg-shell's modules/frus-history-html.xqm (fhh:*), with
 : eXist html-templating ($node, $model) replaced by this app's
 : $context-taking template functions and pages:process-content by
 : page:transform where real ODD rendering is wanted, or by fh:inline for
 : header fields (titles, heads) that must render *inline* -- hsg-shell fed
 : titles through the ODD and got a block <div class="content"> nested
 : inside <h1>/<a>, which is invalid HTML the reference site ships to this
 : day; rendering tei:hi as <em> directly gives the same visible text
 : without the nesting violation.
 :)
declare variable $fh:COL := "/db/apps/frus-history";
declare variable $fh:STATIC := "https://static.history.state.gov";
declare variable $fh:ROUTE := "/historicaldocuments/frus-history";

declare function fh:monograph() as document-node() {
    doc($fh:COL || "/monograph/frus-history.xml")
};

(:~
 : Render TEI header/heading content inline: tei:hi becomes <em> (every
 : rend in this package's titles/heads is italic), tei:note is dropped
 : entirely (the appendix-b head carries a multi-hundred-word source note
 : that the reference site's own TOC/labels exclude), any other element is
 : unwrapped to its content. Used everywhere a title or head renders inside
 : h1/h2/a instead of as a block.
 :)
declare %private function fh:inline($nodes as node()*) as node()* {
    for $node in $nodes
    return
        typeswitch ($node)
            case element(tei:note) return ()
            case element(tei:hi) return <em>{fh:inline($node/node())}</em>
            case element() return fh:inline($node/node())
            default return $node
};

(:~
 : A division's head as inline nodes, cleaned of trailing whitespace runs
 : (the source pretty-printing leaves newline-indent runs inside heads).
 :)
declare %private function fh:head-label($division as element(tei:div)) as node()* {
    fh:tidy-space(fh:inline($division/tei:head[1]/node()))
};

(:~
 : Collapse whitespace runs in text nodes without gluing element boundaries
 : together -- normalize-space() on the whole sequence would destroy the
 : <em> children.
 :)
declare %private function fh:tidy-space($nodes as node()*) as node()* {
    for $node at $pos in $nodes
    return
        typeswitch ($node)
            case text() return
                let $collapsed := replace($node, '\s+', ' ')
                let $collapsed := if ($pos = 1) then replace($collapsed, '^\s+', '') else $collapsed
                let $collapsed := if ($pos = count($nodes)) then replace($collapsed, '\s+$', '') else $collapsed
                return text { $collapsed }
            default return $node
};

(:~
 : Port of hsg-shell's app:date-to-english: ISO date to "Month D, YYYY"
 : (or "Month YYYY" for a YYYY-MM value); anything else passes through.
 :)
declare function fh:date-to-english($date as xs:string) as xs:string {
    let $months := ('January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December')
    return
        if ($date castable as xs:date) then
            let $d := xs:date($date)
            return concat($months[month-from-date($d)], ' ', day-from-date($d), ', ', year-from-date($d))
        else if (matches($date, '^\d{4}-\d{2}$')) then
            concat($months[xs:integer(substring($date, 6, 2))], ' ', substring($date, 1, 4))
        else
            $date
};

(:~
 : Byte count the way hsg-shell's app:bytes-to-readable formats it (copied
 : from hsg:bytes-to-readable, which is %private there): over 1,000,000
 : bytes as N.NNmb, over 1,000 as Nkb. Reproduces the reference landing
 : page's hard-coded "EPUB (853kb) / Mobi (1.29mb) / PDF (2.5mb)" from the
 : monograph's own relatedItem measures.
 :)
declare %private function fh:bytes-to-readable($bytes as xs:integer?) as xs:string {
    if (empty($bytes)) then 'unknown'
    else if ($bytes gt 1000000) then (round($bytes div 10000) div 100) || 'mb'
    else if ($bytes gt 1000) then round($bytes div 1000) || 'kb'
    else $bytes || ' bytes'
};

(: ==================================================================
 : Monograph landing page
 : ================================================================== :)

(:~ The complete monograph title, inline (for the landing page h1). :)
declare function fh:monograph-title($context as map(*)) as node()* {
    fh:tidy-space(fh:inline((fh:monograph()//tei:titleStmt/tei:title[@type = 'complete'])[1]/node()))
};

(:~
 : Reference parity with fhh:monograph-editors: the four titlePage names as
 : a dl of dd entries (the reference's dt label is commented out there too).
 :)
declare function fh:monograph-editors($context as map(*)) as element(dl) {
    <dl class="frus-description-list">{
        for $name in fh:monograph()//tei:titlePage//tei:name
        return <dd>{$name/string()}</dd>
    }</dl>
};

(:~
 : Reference parity with fhh:monograph-edition-info: publisher, pubPlace and
 : the sourceDesc paragraphs ("Printed Edition" / "March 2015"), one line
 : each, br-separated.
 :)
declare function fh:monograph-edition-info($context as map(*)) as element(p) {
    let $doc := fh:monograph()
    let $lines := (
        $doc//tei:fileDesc//tei:publisher,
        $doc//tei:fileDesc//tei:pubPlace,
        $doc//tei:fileDesc//tei:sourceDesc/tei:p
    )
    return
        <p>{
            for $line at $i in $lines
            return ($line/string(), if ($i lt count($lines)) then <br/> else ())
        }</p>
};

(:~
 : The monograph's full book TOC for the landing page: every id-bearing
 : division of front/body/back as a nested list (parts hold their chapters
 : one level down), links into the {sectionId} route. Same 29-entry list and
 : order as the reference's toc:toc-passthru output (verified against the
 : live page: epigraph, foreword, introduction, part-1 > chapter-1..5,
 : part-2 > chapter-6..12, conclusion, then the back matter through index).
 : The toc-link class / toc-{id} anchors are kept from the reference.
 :)
declare function fh:monograph-toc($context as map(*)) as element(ul) {
    fh:toc-list($context, fh:monograph()/tei:TEI/tei:text/(tei:front | tei:body | tei:back)/tei:div[@xml:id], 'hsg-frus__toc')
};

declare %private function fh:toc-list($context as map(*), $divisions as element(tei:div)*, $class as xs:string?) as element(ul) {
    <ul>{
        if ($class) then attribute class { $class } else (),
        for $division in $divisions
        let $id := $division/@xml:id/string()
        return
            <li>
                <a class="toc-link" id="toc-{$id}" href="{$context?context-path}{$fh:ROUTE}/{$id}">{fh:head-label($division)}</a>
                {
                    if ($division/tei:div[@xml:id]) then
                        fh:toc-list($context, $division/tei:div[@xml:id], ())
                    else ()
                }
            </li>
    }</ul>
};

(:~
 : "Download this publication" sidebar panel (landing page). Unlike
 : hsg-shell's index.xml, which hard-codes the URLs, sizes and the
 : "last updated" date, everything here is derived from the monograph's own
 : notesStmt relatedItems (verified present in the deployed package: png
 : cover + epub/mobi/pdf, each with ref/@target, measure/@quantity bytes and
 : a publication-date). The formatted sizes reproduce the reference's
 : displayed values exactly (853kb / 1.29mb / 2.5mb).
 :)
declare function fh:download-panel($context as map(*)) as element(div) {
    let $related := fh:monograph()//tei:relatedItem[@corresp = '#frus-history']
    let $cover := ($related[@type = 'png']//tei:ref/@target/string(), $fh:STATIC || '/frus-history/covers/frus-history.png')[1]
    let $updated := max($related[@type = ('epub', 'mobi', 'pdf')]//tei:date[@type = 'publication-date']/@when/substring(., 1, 10))
    return
        <div class="hsg-panel hsg-frus__register" id="downloads">
            <h2 class="hsg-sidebar-title">Download this publication</h2>
            <p>
                <img src="{$cover}"
                    alt="A History of the Foreign Relations of the United States Series E-Book"
                    title="A History of the Foreign Relations of the United States Series E-Book"
                    class="img-responsive" width="100"/>
            </p>
            {
                if (exists($updated)) then
                    <p>Ebook editions last updated: {fh:date-to-english($updated)}.</p>
                else ()
            }
            <ul class="hsg-list-group">
                {
                    for $format in ('epub', 'mobi', 'pdf')
                    let $item := ($related[@type = $format])[1]
                    let $label := map { 'epub': 'EPUB', 'mobi': 'Mobi', 'pdf': 'PDF' }($format)
                    return
                        if (exists($item)) then
                            <li class="hsg-list-group-item">
                                <a href="{($item//tei:ref/@target/string())[1]}">{$label}
                                    ({fh:bytes-to-readable(($item//tei:measure/@quantity)[1] ! xs:integer(.))})</a>
                            </li>
                        else ()
                }
                <li class="hsg-list-group-item">
                    <a href="{$context?context-path}/historicaldocuments/ebooks">About ebooks</a>
                </li>
            </ul>
        </div>
};

(:~
 : "FRUS History Resources" sidebar panel. Every frus-history page except
 : the document/article views mounts it, but each with a different subset of
 : sub-lists -- the reference never cross-links a page to itself (the
 : landing omits Publications, the documents page omits Documents, etc.).
 : $include is a space-separated subset of
 : "publications documents research events", in reference order per page.
 :)
declare function fh:resources-panel($context as map(*), $include as xs:string) as element(div) {
    let $parts := tokenize($include, '\s+')
    return
        <div class="hsg-panel hsg-frus__register" id="sections">
            <h2 class="hsg-sidebar-title"><em>FRUS</em> History Resources</h2>
            <p>Other resources about the history of the <em>Foreign Relations of the
                United States</em> series.</p>
            {
                if ($parts = 'publications') then (
                    <h3 class="hsg-sidebar-title-second-level">
                        <a href="{$context?context-path}{$fh:ROUTE}">Publications</a>
                    </h3>,
                    <ul class="hsg-list-group">
                        <li class="hsg-list-group-item">
                            <a href="{$context?context-path}{$fh:ROUTE}">
                                <img src="{$fh:STATIC}/frus-history/covers/frus-history.png" width="100"
                                    alt="A History of the Foreign Relations of the United States Series E-Book"/>
                                <br/>Toward &#8220;Thorough, Accurate, and Reliable&#8221;: A History of
                                the <em>Foreign Relations of the United States</em> Series</a>
                        </li>
                    </ul>
                ) else (),
                if ($parts = 'documents') then (
                    <h3 class="hsg-sidebar-title-second-level">
                        <a href="{$context?context-path}{$fh:ROUTE}/documents">Documents</a>
                    </h3>,
                    fh:most-recent-documents($context)
                ) else (),
                if ($parts = 'research') then (
                    <h3 class="hsg-sidebar-title-second-level">
                        <a href="{$context?context-path}{$fh:ROUTE}/research">Research</a>
                    </h3>,
                    fh:most-recent-articles($context)
                ) else (),
                if ($parts = 'events') then
                    fh:most-recent-events($context)
                else ()
            }
        </div>
};

(:~
 : Reference parity with fhh:most-recent-documents: the 3 most recently
 : posted documents (posted desc, created asc within a batch), then the
 : "... All Documents (N)" link with the count outside the anchor, exactly
 : as the reference renders it.
 :)
declare function fh:most-recent-documents($context as map(*)) as element(ul) {
    let $documents :=
        for $doc in collection($fh:COL || '/documents')/tei:TEI
        order by $doc//tei:date[@type = 'posted']/@when descending, $doc//tei:date[@type = 'created']/@when
        return $doc
    return
        <ul class="hsg-list-group">
            {
                for $doc in subsequence($documents, 1, 3)
                let $id := substring-before(util:document-name($doc), '.xml')
                return
                    <li class="hsg-list-group-item">
                        <a href="{$context?context-path}{$fh:ROUTE}/documents/{$id}">{($doc//tei:title[@type = 'short'])[1]/string()}</a>
                    </li>
            }
            <li class="hsg-list-group-item">
                <a href="{$context?context-path}{$fh:ROUTE}/documents">... All Documents</a> ({count($documents)})
            </li>
        </ul>
};

(:~
 : Reference parity with fhh:most-recent-articles: 3 most recent authored
 : articles by publication date, each with its "(date)" suffix, then
 : "... All Articles (N)". Only TEI carrying a tei:author count -- the same
 : filter that puts 28, not 32, on the live sidebar.
 :)
declare function fh:most-recent-articles($context as map(*)) as element(ul) {
    let $articles :=
        for $doc in collection($fh:COL || '/articles')/tei:TEI[.//tei:author]
        order by $doc//tei:publicationStmt/tei:date/@when descending
        return $doc
    return
        <ul class="hsg-list-group">
            {
                for $doc in subsequence($articles, 1, 3)
                let $id := replace(util:document-name($doc), '\.xml$', '')
                let $date := $doc//tei:publicationStmt/tei:date
                return
                    <li class="hsg-list-group-item">
                        <a href="{$context?context-path}{$fh:ROUTE}/research/{$id}">{fh:tidy-space(fh:inline(($doc//tei:title[@type = 'short'])[1]/node()))}</a> ({$date/string()})
                    </li>
            }
            <li class="hsg-list-group-item">
                <a href="{$context?context-path}{$fh:ROUTE}/research">... All Articles</a> ({count($articles)})
            </li>
        </ul>
};

(:~
 : Reference parity with fhh:most-recent-events: an "Upcoming Events" block
 : (soonest first) when any event is today or later, then a "Recent Events"
 : block with the 3 most recent past events, each a teaser + date, and the
 : "... All events (N)" link. All 13 events in the package are past
 : (2011-2014), so in practice only the Recent block renders.
 :
 : Deliberate divergence: hsg-shell's Recent Events heading links the
 : page-relative "./frus-history/events", which only resolves correctly
 : from /historicaldocuments itself -- a long-standing reference bug. Linked
 : through the context path like every other internal link instead.
 :)
declare function fh:most-recent-events($context as map(*)) as element()* {
    let $events := collection($fh:COL || '/events')/event
    let $events-url := $context?context-path || $fh:ROUTE || '/events'
    let $all-events-item :=
        <li class="hsg-list-group-item">
            <a href="{$events-url}">... All events ({count($events)})</a>
        </li>
    let $upcoming := $events[xs:date(event-date) ge current-date()]
    let $recent := $events[xs:date(event-date) lt current-date()]
    return (
        if ($upcoming) then (
            <h3 class="hsg-sidebar-title-second-level">
                <a href="{$events-url}">Upcoming Events</a>
            </h3>,
            <ul class="hsg-list-group">{
                for $event in $upcoming
                order by xs:date($event/event-date) ascending
                return fh:event-sidebar-item($event),
                if ($recent) then () else $all-events-item
            }</ul>
        ) else (),
        if ($recent) then (
            <h3 class="hsg-sidebar-title-second-level">
                <a href="{$events-url}">Recent Events</a>
            </h3>,
            <ul class="hsg-list-group">{
                let $ordered := (
                    for $event in $recent
                    order by xs:date($event/event-date) descending
                    return $event
                )
                for $item in subsequence($ordered, 1, 3)
                return fh:event-sidebar-item($item),
                $all-events-item
            }</ul>
        ) else ()
    )
};

declare %private function fh:event-sidebar-item($event as element(event)) as element(li) {
    <li class="hsg-list-group-item">
        {$event/teaser/node()} {fh:date-to-english($event/event-date/string())}
    </li>
};

(: ==================================================================
 : Monograph division (section) pages
 : ================================================================== :)

declare function fh:division($sectionId as xs:string) as element(tei:div)? {
    (fh:monograph()//tei:div[@xml:id = $sectionId])[1]
};

(:~
 : Every addressable division in reading order -- front, body, back, nested
 : chapters flattened between their parts -- the prev/next sequence (same
 : traversal as dh:monograph-divisions).
 :)
declare %private function fh:divisions() as element(tei:div)* {
    fh:monograph()//(tei:front | tei:body | tei:back)//tei:div[@xml:id]
};

(:~
 : The monograph title as the h2 shown above every division page's content,
 : reference parity with fhh:monograph-title / hsg-shell's navigation-title
 : chrome (same element hsg:navigation-title renders on volume interiors).
 :)
declare function fh:navigation-title($context as map(*)) as element(h2) {
    <h2 class="hsg-navigation-title" id="navigation-title">{fh:monograph-title($context)}</h2>
};

(:~
 : Home > Historical Documents > History of the FR Series > division head.
 : Flat like the live site's own breadcrumb: a chapter's trail does NOT
 : include its part (verified live on /frus-history/chapter-1).
 :)
declare function fh:section-breadcrumb($context as map(*)) as element(li)+ {
    hsg:section-breadcrumb($context, (
        map { "label": fh:frus-history-crumb(), "href": $fh:ROUTE },
        map { "label": fh:head-label(fh:division($context?section-id)) }
    ))
};

declare %private function fh:frus-history-crumb() as node()* {
    (text { "History of the " }, <em>Foreign Relations</em>, text { " Series" })
};

(:~
 : One division's complete page content. A container division (part-1 /
 : part-2, the only divisions with id-bearing children) renders as its head
 : plus a Contents list of links to its chapters -- the same "link out,
 : don't inline" treatment the reference's frus.odd document-list predicate
 : produces on the live /frus-history/part-1 page -- rather than inlining
 : five full chapters. A leaf division renders through the ODD (mode
 : "monograph-section", the same mode dh:monograph-section-content proved
 : out, which also forces the articles'/monograph's place-less notes to
 : footnote behaviour), with its footnotes consolidated after the body the
 : way the pb-view SSR path does, and an explicit h1 built from the head
 : (the ODD's own duplicate of that first head is hidden by the existing
 : ".usa-prose > .tei-div > :first-child.tei-head" rule in hsg-theme.css).
 : The division node is passed to page:transform still attached to its
 : source document (see the dh:monograph-section-content pitfall note).
 :)
declare function fh:section-content($context as map(*)) as element()+ {
    let $division := fh:division($context?section-id)
    return
        if ($division/tei:div[@xml:id]) then (
            <h1>{fh:head-label($division)}</h1>,
            for $p in $division/tei:p[not(preceding-sibling::tei:div)]
            return page:transform($p, map { "mode": "monograph-section" }),
            <h2>Contents</h2>,
            <ul class="usa-list">{
                for $child in $division/tei:div[@xml:id]
                return
                    <li>
                        <a href="{$context?context-path}{$fh:ROUTE}/{$child/@xml:id}">{fh:head-label($child)}</a>
                    </li>
            }</ul>
        )
        else (
            <h1>{fh:head-label($division)}</h1>,
            fh:consolidate-footnotes(page:transform($division, map { "mode": "monograph-section" }))
        )
};

(:~
 : Body + consolidated footnotes: strip the inline footnote apparatus out of
 : the transformed HTML and re-emit it collected after the content, exactly
 : the pages:process/nav:output-footnotes consolidation the pb-view SSR path
 : and dh:monograph-section-content already do.
 :)
declare %private function fh:consolidate-footnotes($transformed as node()*) as node()* {
    let $body := pages:clean-footnotes($transformed)
    let $footnotes :=
        for $fn in $transformed//*[@class = "footnote"]
        return element { node-name($fn) } { $fn/@*, pages:clean-footnotes($fn/node()) }
    return (
        $body,
        if ($footnotes) then nav:output-footnotes($footnotes) else ()
    )
};

declare function fh:section-pagination($context as map(*)) as element(nav)? {
    fh:pagination($context, $context?section-id)
};

(:~
 : Previous/next division among fh:divisions in reading order, as the
 : usa-pagination nav every other monograph section page in this app uses
 : (dh:monograph-section-pagination's shape). The appendix-a entry links to
 : the chart page -- the fixed /appendix-a route wins over {sectionId} --
 : which is exactly where the reference's own TOC/prev-next land too.
 :)
declare %private function fh:pagination($context as map(*), $current as xs:string) as element(nav)? {
    let $divisions := fh:divisions()
    let $pos := index-of($divisions/@xml:id/string(), $current)[1]
    let $prev := if ($pos gt 1) then $divisions[$pos - 1] else ()
    let $next := if ($pos lt count($divisions)) then $divisions[$pos + 1] else ()
    return
        if (empty($prev) and empty($next)) then ()
        else
            <nav aria-label="Pagination" class="usa-pagination">
                <ul class="usa-pagination__list">
                {
                    if (exists($prev)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}{$fh:ROUTE}/{$prev/@xml:id}" class="usa-pagination__link usa-pagination__previous-page">
                                <pb-i18n key="odd.previous">Previous</pb-i18n>
                            </a>
                        </li>
                    else (),
                    if (exists($next)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}{$fh:ROUTE}/{$next/@xml:id}" class="usa-pagination__link usa-pagination__next-page">
                                <pb-i18n key="odd.next">Next</pb-i18n>
                            </a>
                        </li>
                    else ()
                }
                </ul>
            </nav>
};

(:~
 : The monograph TOC as a sidebar nav with the current division highlighted
 : (nested usa-sidenav, chapters under their parts, same shape as
 : dh:monograph-toc). Mounted on the division pages and the appendix-a
 : chart page.
 :)
declare function fh:toc-sidebar($context as map(*)) as element(nav) {
    fh:toc-sidebar-for($context, $context?section-id)
};

declare function fh:appendix-a-toc-sidebar($context as map(*)) as element(nav) {
    fh:toc-sidebar-for($context, 'appendix-a')
};

declare %private function fh:toc-sidebar-for($context as map(*), $current as xs:string?) as element(nav) {
    <nav aria-label="Table of contents" class="toc">
        <h2><pb-i18n key="document.contents">Contents</pb-i18n></h2>
        {fh:toc-nav-level($context, fh:monograph()/tei:TEI/tei:text/(tei:front | tei:body | tei:back)/tei:div[@xml:id], $current, 'usa-sidenav')}
    </nav>
};

declare %private function fh:toc-nav-level($context as map(*), $divisions as element(tei:div)*, $current as xs:string?, $listClass as xs:string) as element(ul) {
    <ul class="{$listClass}">{
        for $division in $divisions
        let $id := $division/@xml:id/string()
        let $children := $division/tei:div[@xml:id]
        return
            <li class="usa-sidenav__item">
                <a href="{$context?context-path}{$fh:ROUTE}/{$id}">
                {
                    if ($id = $current) then (attribute class { 'usa-current' }, attribute aria-current { 'page' }) else (),
                    fh:head-label($division)
                }
                </a>
                {
                    if (exists($children)) then
                        fh:toc-nav-level($context, $children, $current, 'usa-sidenav__sublist')
                    else ()
                }
            </li>
    }</ul>
};

(: ==================================================================
 : Documents
 : ================================================================== :)

declare %private function fh:document-doc($documentId as xs:string) as document-node()? {
    let $path := $fh:COL || '/documents/' || $documentId || '.xml'
    return if (doc-available($path)) then doc($path) else ()
};

(:~
 : The sortable document list, reference parity with fhh:document-list
 : including its exact list shapes: ?sort-by=created renders the count line
 : and one flat ol by document date; the default (posted) renders the count
 : line and one ul per posting batch -- <strong> posted date over an ol of
 : that batch's documents by document date -- most recent batch first. The
 : toggle links swap the query parameter, relative to the page itself.
 :)
declare function fh:document-list($context as map(*)) as element()+ {
    let $documents := collection($fh:COL || '/documents')/tei:TEI
    let $sort-by := ($context?request?parameters?sort-by, 'posted')[1]
    return
        if ($sort-by = 'created') then (
            <p>{count($documents)} documents, sorted by document date.
                (<a href="?sort-by=posted">Sort by date posted.</a>)</p>,
            <ol>{
                for $doc in $documents
                let $created := $doc//tei:date[@type = 'created']/@when
                let $id := substring-before(util:document-name($doc), '.xml')
                order by $created, $id
                return
                    <li>
                        <a href="{$context?context-path}{$fh:ROUTE}/documents/{$id}">{($doc//tei:title[@type = 'complete'])[1]/string() => normalize-space()}</a>
                    </li>
            }</ol>
        )
        else (
            <p>{count($documents)} documents, sorted by date posted (most recent batch first).
                (<a href="?sort-by=created">Sort by document date.</a>)</p>,
            for $doc in $documents
            let $posted := ($doc//tei:date[@type = 'posted'])[1]
            group by $posted-when := $posted/@when/string()
            order by $posted-when descending
            return
                <ul>
                    <li>
                        <strong>{$posted[1]/string()}</strong>
                        <ol>{
                            for $each in $doc
                            let $created := $each//tei:date[@type = 'created']/@when
                            let $id := substring-before(util:document-name($each), '.xml')
                            order by $created, $id
                            return
                                <li>
                                    <a href="{$context?context-path}{$fh:ROUTE}/documents/{$id}">{($each//tei:title[@type = 'complete'])[1]/string() => normalize-space()}</a>
                                </li>
                        }</ol>
                    </li>
                </ul>
        )
};

declare function fh:document-breadcrumb($context as map(*)) as element(li)+ {
    let $doc := fh:document-doc($context?document-id)
    return
        hsg:section-breadcrumb($context, (
            map { "label": fh:frus-history-crumb(), "href": $fh:ROUTE },
            map { "label": "Documents", "href": $fh:ROUTE || "/documents" },
            map { "label": normalize-space(($doc//tei:title[@type = 'short'])[1]) }
        ))
};

(:~ The document's complete title, inline, for the view page's h1. :)
declare function fh:document-title($context as map(*)) as node()* {
    fh:tidy-space(fh:inline((fh:document-doc($context?document-id)//tei:title[@type = 'complete'])[1]/node()))
};

(:~
 : Reference parity with fhh:document-pdf: the sourceDesc note pointing at
 : the scanned original ("A scan of the original document is available for
 : download (PDF, ...)"), rendered through the ODD so the tei:ref becomes a
 : link.
 :)
declare function fh:document-source($context as map(*)) as node()* {
    page:transform(fh:document-doc($context?document-id)//tei:fileDesc/tei:sourceDesc/tei:p,
        map { "mode": "monograph-section" })
};

(:~
 : The document body through the ODD, footnotes consolidated. The nested
 : per-letter heads render at whatever level the ODD computes -- the
 : reference page has the same shape (its transcribed letters' own heads
 : are headings inside the body).
 :)
declare function fh:document-content($context as map(*)) as node()* {
    fh:consolidate-footnotes(
        page:transform(fh:document-doc($context?document-id)//tei:text/*, map { "mode": "monograph-section" }))
};

(:~
 : All 63 documents by document (created) date with the current one
 : highlighted -- reference parity with fhh:document-list-full, rendered as
 : this app's usa-sidenav sidebar convention instead of hsg-shell's
 : list-group panel.
 :)
declare function fh:document-sidebar($context as map(*)) as element(nav) {
    <nav aria-label="Side navigation" class="toc">
        <h2><em>FRUS</em> History Documents</h2>
        <ul class="usa-sidenav">{
            for $doc in collection($fh:COL || '/documents')/tei:TEI
            let $created := $doc//tei:date[@type = 'created']/@when
            let $id := substring-before(util:document-name($doc), '.xml')
            order by $created, $id
            return
                <li class="usa-sidenav__item">
                    <a href="{$context?context-path}{$fh:ROUTE}/documents/{$id}">
                    {
                        if ($id = $context?document-id) then (attribute class { 'usa-current' }, attribute aria-current { 'page' }) else (),
                        ($doc//tei:title[@type = 'short'])[1]/string()
                    }
                    </a>
                </li>
        }</ul>
    </nav>
};

(:~
 : Prev/next document by document (created) date, reference parity with
 : fhh:get-previous-doc / fhh:get-next-doc's ordering.
 :)
declare function fh:document-pagination($context as map(*)) as element(nav)? {
    let $ordered :=
        for $doc in collection($fh:COL || '/documents')/tei:TEI
        let $created := $doc//tei:date[@type = 'created']/@when
        let $id := substring-before(util:document-name($doc), '.xml')
        order by $created, $id
        return $id
    return
        fh:list-pagination($context, $ordered, $context?document-id, $fh:ROUTE || '/documents/')
};

declare %private function fh:list-pagination($context as map(*), $ordered as xs:string*, $current as xs:string, $route as xs:string) as element(nav)? {
    let $pos := index-of($ordered, $current)[1]
    let $prev := if ($pos gt 1) then $ordered[$pos - 1] else ()
    let $next := if ($pos lt count($ordered)) then $ordered[$pos + 1] else ()
    return
        if (empty($prev) and empty($next)) then ()
        else
            <nav aria-label="Pagination" class="usa-pagination">
                <ul class="usa-pagination__list">
                {
                    if (exists($prev)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}{$route}{$prev}" class="usa-pagination__link usa-pagination__previous-page">
                                <pb-i18n key="odd.previous">Previous</pb-i18n>
                            </a>
                        </li>
                    else (),
                    if (exists($next)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}{$route}{$next}" class="usa-pagination__link usa-pagination__next-page">
                                <pb-i18n key="odd.next">Next</pb-i18n>
                            </a>
                        </li>
                    else ()
                }
                </ul>
            </nav>
};

(: ==================================================================
 : Research articles
 : ================================================================== :)

declare %private function fh:articles() as element(tei:TEI)* {
    collection($fh:COL || '/articles')/tei:TEI[.//tei:author]
};

declare %private function fh:article-doc($articleId as xs:string) as document-node()? {
    let $path := $fh:COL || '/articles/' || $articleId || '.xml'
    return if (doc-available($path)) then doc($path) else ()
};

(:~
 : Reference parity with fhh:articles-list: one block per authored article,
 : publication date descending -- linked h3 title, "By {author}{date}" line
 : (the reference concatenates the date element's text straight after the
 : author, no separator; kept, in a span instead of a raw tei:date element
 : leaking into the HTML the way the live page does), then the first
 : paragraph of the body as a teaser. Footnote apparatus is stripped from
 : the teaser (the reference left itself a TODO for exactly that).
 :)
declare function fh:articles-list($context as map(*)) as element(div)* {
    for $article in fh:articles()
    let $date := $article//tei:publicationStmt/tei:date
    let $id := replace(util:document-name($article), '\.xml$', '')
    order by xs:date($date/@when) descending
    return
        <div class="article-container">
            <h3>
                <a href="{$context?context-path}{$fh:ROUTE}/research/{$id}">{fh:tidy-space(fh:inline(($article//tei:title[@type = 'complete'])[1]/node()))}</a>
            </h3>
            <p>By {$article//tei:author/string()}<span class="hsg-article-date">{$date/string()}</span></p>
            {
                fh:strip-note-apparatus(
                    page:transform($article//tei:body/tei:div[1]/tei:p[1], map { "mode": "monograph-section" }))
            }
        </div>
};

(:~
 : Remove the whole footnote apparatus from a transformed fragment: the
 : collected-footnote elements (class "footnote"), the in-text markers
 : (class "note") and any popover/tooltip companions. Teaser-only cleanup;
 : full pages keep their notes via fh:consolidate-footnotes.
 :)
declare %private function fh:strip-note-apparatus($nodes as node()*) as node()* {
    for $node in $nodes
    return
        typeswitch ($node)
            case element() return
                if ($node/@class = ('footnote', 'note') or local-name($node) = ('pb-popover', 'paper-tooltip')) then
                    ()
                else if ($node//a[@class = 'note'] or $node//*[@class = 'footnote']) then
                    element { node-name($node) } { $node/@*, fh:strip-note-apparatus($node/node()) }
                else
                    $node
            default return $node
};

declare function fh:article-breadcrumb($context as map(*)) as element(li)+ {
    let $article := fh:article-doc($context?article-id)
    return
        hsg:section-breadcrumb($context, (
            map { "label": fh:frus-history-crumb(), "href": $fh:ROUTE },
            map { "label": "Research", "href": $fh:ROUTE || "/research" },
            map { "label": fh:tidy-space(fh:inline(($article//tei:title[@type = 'short'])[1]/node())) }
        ))
};

declare function fh:article-title($context as map(*)) as node()* {
    fh:tidy-space(fh:inline((fh:article-doc($context?article-id)//tei:title[@type = 'complete'])[1]/node()))
};

(:~
 : Reference parity with fhh:article-author: "By {author} / {affiliation}"
 : (h3) when an author exists, and "Released {date}" (h4), with the same
 : schema.org itemprops (author, sourceOrganization, datePublished) -- the
 : page template carries the itemscope/itemtype on the content wrapper.
 :)
declare function fh:article-byline($context as map(*)) as element()* {
    let $article := fh:article-doc($context?article-id)
    let $author := $article//tei:author/text()
    let $affiliation := $article//tei:sponsor/text()
    let $date := $article//tei:publicationStmt/tei:date/text()
    return (
        if ($author) then
            <h3>By <span itemprop="author">{$author}</span><br/>
                <span itemprop="sourceOrganization">{$affiliation}</span></h3>
        else (),
        <h4>Released <span itemprop="datePublished">{$date}</span></h4>
    )
};

(:~
 : Reference parity with fhh:article-description: the sourceDesc paragraph
 : (often empty in the data; renders as nothing visible then).
 :)
declare function fh:article-description($context as map(*)) as node()* {
    page:transform(fh:article-doc($context?article-id)//tei:fileDesc/tei:sourceDesc/tei:p,
        map { "mode": "monograph-section" })
};

(:~
 : The article body through the ODD (mode "monograph-section" also forces
 : the articles' place-less tei:note elements into footnote behaviour,
 : which is how the reference renders them), footnotes consolidated after
 : the content.
 :
 : Image resolution: article graphics are bare filenames served from
 : static.history.state.gov/frus150/ (verified live). This app's ODD
 : resolves bare-filename graphics per collection and falls back to the
 : countries/ prefix for collections it does not know -- frus-history is
 : not (yet) among its models, and the ODD is outside this ticket's file
 : set, so the equivalent rewrite happens here on the transformed HTML:
 : swap the fallback countries/ prefix for frus150/ on every img src.
 :)
declare function fh:article-content($context as map(*)) as node()* {
    fh:consolidate-footnotes(
        fh:fix-article-images(
            page:transform(fh:article-doc($context?article-id)//tei:text/*, map { "mode": "monograph-section" })))
};

declare %private function fh:fix-article-images($nodes as node()*) as node()* {
    for $node in $nodes
    return
        typeswitch ($node)
            case element(img) return
                element img {
                    $node/@* except $node/@src,
                    attribute src { replace($node/@src, '^' || $fh:STATIC || '/countries/', $fh:STATIC || '/frus150/') },
                    fh:fix-article-images($node/node())
                }
            case element() return
                element { node-name($node) } { $node/@*, fh:fix-article-images($node/node()) }
            default return $node
};

(:~
 : All authored articles, publication date descending, current highlighted --
 : reference parity with fhh:article-list-sidebar (which orders the same
 : way), as a usa-sidenav.
 :)
declare function fh:article-sidebar($context as map(*)) as element(nav) {
    <nav aria-label="Side navigation" class="toc">
        <h2><em>FRUS</em> Sesquicentennial Research</h2>
        <ul class="usa-sidenav">{
            for $article in fh:articles()
            let $date := $article//tei:publicationStmt/tei:date
            let $id := replace(util:document-name($article), '\.xml$', '')
            order by $date/@when descending
            return
                <li class="usa-sidenav__item">
                    <a href="{$context?context-path}{$fh:ROUTE}/research/{$id}">
                    {
                        if ($id = $context?article-id) then (attribute class { 'usa-current' }, attribute aria-current { 'page' }) else (),
                        fh:tidy-space(fh:inline(($article//tei:title[@type = 'short'])[1]/node())),
                        ' (' || $date/string() || ')'
                    }
                    </a>
                </li>
        }</ul>
    </nav>
};

(:~
 : Prev/next article by publication date ascending, reference parity with
 : fhh:get-previous-article / fhh:get-next-article ("next" moves toward the
 : more recent article).
 :)
declare function fh:article-pagination($context as map(*)) as element(nav)? {
    let $ordered :=
        for $article in collection($fh:COL || '/articles')/tei:TEI
        let $date := $article//tei:publicationStmt/tei:date/@when
        let $id := replace(util:document-name($article), '\.xml$', '')
        order by $date, $id
        return $id
    return
        fh:list-pagination($context, $ordered, $context?article-id, $fh:ROUTE || '/research/')
};

(: ==================================================================
 : Events
 : ================================================================== :)

(:~
 : Reference parity with fhh:events: an "Upcoming Events" heading and
 : blocks (soonest first) only when any event is today or later, then
 : "Recent Events" (most recent first), each event's stored full-description
 : fragment rendered as-is (the records are XHTML fragments, no ODD), with
 : an hr between events. Each fragment is additionally wrapped in a
 : div.frus-history-event -- presentation-neutral, keeps the stored
 : fragments' own ids/anchors intact, and gives the page (and its tests) a
 : countable per-event element the bare reference markup lacks.
 :)
declare function fh:events($context as map(*)) as element(div) {
    let $events := collection($fh:COL || '/events')/event
    let $upcoming := $events[xs:date(event-date) ge current-date()]
    let $recent := $events[xs:date(event-date) lt current-date()]
    return
        <div>
            {
                if ($upcoming) then (
                    <h1>Upcoming Events</h1>,
                    let $ordered := (
                        for $event in $upcoming
                        order by xs:date($event/event-date) ascending
                        return $event
                    )
                    return fh:event-blocks($ordered)
                ) else ()
            }
            <h1>Recent Events</h1>
            {
                let $ordered := (
                    for $event in $recent
                    order by xs:date($event/event-date) descending
                    return $event
                )
                return fh:event-blocks($ordered)
            }
        </div>
};

declare %private function fh:event-blocks($events as element(event)*) as element()* {
    for $event at $pos in $events
    return (
        <div class="frus-history-event">{$event/full-description/node()}</div>,
        if ($pos lt count($events)) then <hr/> else ()
    )
};

(: ==================================================================
 : Appendix A production/timeliness chart
 : ================================================================== :)

declare function fh:appendix-a-breadcrumb($context as map(*)) as element(li)+ {
    hsg:section-breadcrumb($context, (
        map { "label": fh:frus-history-crumb(), "href": $fh:ROUTE },
        map { "label": fh:head-label(fh:division('appendix-a')) }
    ))
};

declare function fh:appendix-a-pagination($context as map(*)) as element(nav)? {
    fh:pagination($context, 'appendix-a')
};

(:~
 : Reference parity with fhh:appendix-a-chart-intro: the explanatory prose
 : maintained as a standalone XHTML document inside the data package.
 :)
declare function fh:appendix-a-chart-intro($context as map(*)) as element()? {
    doc($fh:COL || '/frus-production-chart/frus-production-chart-intro.html')/*
};

(:~
 : Reference parity with fhh:appendix-a-chart-data: inline script feeding
 : the two JSON binaries from the data package straight into the Dygraph
 : constructor, plus the change() handler the fieldset checkboxes call.
 : Requires dygraph-combined.js to have been loaded first -- the page
 : template puts its script tag immediately before this one, same ordering
 : as the reference page.
 :)
declare function fh:appendix-a-chart-data($context as map(*)) as element(script) {
    let $chart-data := util:binary-to-string(util:binary-doc($fh:COL || '/frus-production-chart/frus-production-chart-data.json'))
    let $chart-parameters := util:binary-to-string(util:binary-doc($fh:COL || '/frus-production-chart/frus-production-chart-parameters.json'))
    return
        <script type="text/javascript">{ text {
            'const g = window.g = new Dygraph(document.getElementById("graph"), ',
            $chart-data,
            ', ',
            $chart-parameters,
            '); function change(el) { g.setVisibility(parseInt(el.id), el.checked); }'
        } }</script>
};
