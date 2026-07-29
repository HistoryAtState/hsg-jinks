xquery version "3.1";

module namespace ms="https://history.state.gov/ns/templates/milestones";

import module namespace page="http://teipublisher.com/ns/templates/page" at "page.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : "Milestones in the History of U.S. Foreign Relations" (OP#1098): a RETIRED
 : publication (2017 notice, frozen content since 2018). Structurally one TEI
 : document per historical era -- front-matter intro div (xml:id "foreword")
 : plus a sequence of body-div articles -- much closer to departmenthistory's
 : single-file-monograph shape (modules/templates/departmenthistory.xqm,
 : dh:monograph-*) than to historicaldocuments' one-file-per-division volumes,
 : since every article in an era lives in the era's own one file. Unlike
 : departmenthistory's two fixed monograph names, eras are a discoverable,
 : ordered collection (19 documents, "{startYear}-{endYear}.xml", already in
 : correct chronological order as a plain string sort -- verified against the
 : live reference site's own era ordering).
 :)
declare variable $ms:CHAPTERS_COL := "/db/apps/milestones/chapters";

declare function ms:era-doc($eraId as xs:string) as document-node()? {
    let $path := $ms:CHAPTERS_COL || "/" || $eraId || ".xml"
    return
        if (doc-available($path)) then doc($path) else ()
};

(:~
 : Every addressable division in an era doc, in document order: the
 : front-matter "foreword" intro plus every body-div article. Confirmed flat
 : (no nested subchapters, unlike departmenthistory's short-history) on the
 : one era fully inspected (1914-1920.xml) and consistent with every era's
 : sidebar-visible article count matching its body-div count; walks with "//"
 : rather than assuming a fixed nesting depth, same defensive reasoning as
 : dh:monograph-divisions.
 :)
declare function ms:era-divisions($doc as document-node()?) as element(tei:div)* {
    $doc//(tei:front | tei:body)//tei:div[@xml:id]
};

(:~
 : Body-div articles only, excluding the front-matter "foreword" -- the shape
 : /milestones/all's per-era grouped listing needs (verified live against the
 : reference site: the foreword is never linked from that listing, only real
 : articles are).
 :)
declare function ms:era-articles($doc as document-node()?) as element(tei:div)* {
    $doc//tei:body//tei:div[@xml:id]
};

declare function ms:era-short-title($doc as document-node()) as xs:string {
    normalize-space(($doc//tei:titleStmt/tei:title[@type='short'])[1])
};

(:~
 : The era's own descriptive label, e.g. "1750–1775: Diplomatic Struggles in
 : the Colonial Period" -- the foreword division's own <head> (date range +
 : description), used as the heading on /milestones/all's per-era groups.
 :)
declare function ms:era-full-title($doc as document-node()) as xs:string {
    normalize-space($doc//tei:front//tei:div[@xml:id='foreword']/tei:head[1])
};

(:~
 : Every era, in chronological order, as a map exposing what the index
 : dropdown, the cross-era sidebar, and the all-listing all need. Backs all
 : three so a 20th era added to the data collection appears everywhere with no
 : template change -- replacing hsg-shell's hand-authored, staleness-prone
 : static 19-item lists (#1160/#1161's own rework note).
 :
 : Ordered by plain string sort of the era id: verified live that this
 : already matches full chronological order for all 19 real ids (every start
 : year is exactly 4 digits, so lexicographic and numeric order coincide) --
 : the same convention the data collection's own filenames encode. #1164
 : suggests eventually sourcing the date range from structured teiHeader
 : metadata instead of the filename; the upstream HistoryAtState/milestones
 : package does not carry that yet, so filename-derived ordering is used here,
 : same situation as the era id itself.
 :)
declare function ms:eras() as map(*)* {
    for $name in xmldb:get-child-resources($ms:CHAPTERS_COL)
    where ends-with($name, '.xml')
    let $eraId := substring-before($name, '.xml')
    order by $eraId
    return
        let $doc := ms:era-doc($eraId)
        return map {
            "id": $eraId,
            "title": ms:era-short-title($doc),
            "label": ms:era-full-title($doc)
        }
};

(:~
 : Cross-era navigation aside shown on the index, all-listing, and era-landing
 : pages -- NOT on the article page, which shows the current era's own TOC
 : (ms:era-toc) instead (matches hsg-shell's own article-page behaviour: no
 : separate 19-era picker once you're already inside one).
 :)
(:~
 : Reference site markup carries this in a second, separate
 : `<aside id="sections">` below the era-list aside (a single "All" link,
 : no other entries) -- folded into the one sidebar list here instead,
 : same "one sidebar slot, merge in what a second reference aside would
 : show" convention departmenthistory's own sidebar.html already
 : established (see its own doc comment on `aside#sections`).
 :)
declare function ms:era-sidebar($context as map(*)) as element(nav) {
    let $current := $context?request?parameters?eraId
    return
        <nav aria-label="Side navigation" class="toc">
            <h2><pb-i18n key="milestones.title">Milestones</pb-i18n></h2>
            <ul class="usa-sidenav">
            {
                for $era in ms:eras()
                return
                    <li class="usa-sidenav__item">
                        <a href="{$context?context-path}/milestones/{$era?id}">
                        {
                            if ($era?id = $current) then (attribute class {"usa-current"}, attribute aria-current {"page"}) else (),
                            $era?title
                        }
                        </a>
                    </li>,
                <li class="usa-sidenav__item">
                    <a href="{$context?context-path}/milestones/all">All</a>
                </li>
            }
            </ul>
        </nav>
};

declare function ms:era-select($context as map(*)) as element(select) {
    <select id="milestones-era-select" class="usa-select" name="era" onchange="location = this.options[this.selectedIndex].value;">
        <option value="#"><pb-i18n key="milestones.select-period">Select a period</pb-i18n></option>
        {
            for $era in ms:eras()
            return
                <option value="{$context?context-path}/milestones/{$era?id}">{$era?title}</option>
        }
    </select>
};

(:~
 : Table of contents for one era: the foreword intro plus every article, in
 : document order. Shared between the era-landing page (main content, no
 : current item -- there is nothing to highlight there) and the article
 : page's sidebar ($current set to the article being viewed) -- one
 : traversal, two placements, same reasoning as dh:monograph-toc /
 : hsg:volume-toc.
 :)
declare function ms:era-toc($context as map(*), $doc as document-node(), $eraId as xs:string, $current as xs:string?) as element(ul) {
    <ul class="usa-sidenav">
    {
        for $division in ms:era-divisions($doc)
        let $id := $division/@xml:id/string()
        return
            <li class="usa-sidenav__item">
                <a href="{$context?context-path}/milestones/{$eraId}/{$id}">
                {
                    if ($id = $current) then (attribute class {"usa-current"}, attribute aria-current {"page"}) else (),
                    normalize-space($division/tei:head[1])
                }
                </a>
            </li>
    }
    </ul>
};

(:~
 : Previous/next division among ms:era-divisions, in document order -- the
 : foreword counts as a real, navigable stop (verified live: the reference
 : site's first body article's "previous" link points at the foreword).
 :)
declare function ms:era-prev-next($doc as document-node(), $current as xs:string) as map(*) {
    let $divisions := ms:era-divisions($doc)
    let $pos := index-of($divisions/@xml:id/string(), $current)[1]
    return map {
        "prev": if ($pos > 1) then $divisions[$pos - 1] else (),
        "next": if ($pos < count($divisions)) then $divisions[$pos + 1] else ()
    }
};

(:~
 : Shared breadcrumb builder: Home > Milestones > $trail, mirroring
 : dh:breadcrumb's shape (maps, not arrays -- a trailing array literal ends in
 : a literal "]]" which collides with this templating engine's "[[ ... ]]"
 : delimiter).
 :)
declare function ms:breadcrumb($context as map(*), $trail as map(*)*) as element(li)+ {
    (
        <li>
            <a href="{$context?context-path}/">
                <pb-i18n key="breadcrumb.home">Home</pb-i18n>
            </a>
        </li>,
        if (empty($trail)) then
            <li aria-current="page">
                <pb-i18n key="milestones.title">Milestones</pb-i18n>
            </li>
        else
            <li>
                <a href="{$context?context-path}/milestones">
                    <pb-i18n key="milestones.title">Milestones</pb-i18n>
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

declare function ms:all-breadcrumb($context as map(*)) as element(li)+ {
    ms:breadcrumb($context, (map { "label": "All" }))
};

declare function ms:era-breadcrumb($context as map(*)) as element(li)+ {
    let $eraId := $context?request?parameters?eraId
    let $doc := ms:era-doc($eraId)
    return ms:breadcrumb($context, (map { "label": ms:era-short-title($doc) }))
};

(:~
 : Resolves the requested era/article from the request parameters
 : milapi:view-section threaded through vapi:html. Each of the article page's
 : independent [[ ]] interpolation sites (breadcrumb, sidebar, content,
 : pagination) calls this and re-resolves rather than sharing state -- same
 : reasoning as dh:current-section.
 :)
declare %private function ms:current-article($context as map(*)) as map(*) {
    let $eraId := $context?request?parameters?eraId
    let $articleId := $context?request?parameters?articleId
    let $doc := ms:era-doc($eraId)
    let $division := ms:era-divisions($doc)[@xml:id = $articleId]
    return map { "eraId": $eraId, "doc": $doc, "division": $division }
};

declare function ms:article-breadcrumb($context as map(*)) as element(li)+ {
    let $a := ms:current-article($context)
    return ms:breadcrumb($context, (
        map { "label": ms:era-short-title($a?doc), "href": "/milestones/" || $a?eraId },
        map { "label": normalize-space($a?division/tei:head[1]) }
    ))
};

declare function ms:article-sidebar($context as map(*)) as element(nav) {
    let $a := ms:current-article($context)
    return
        <nav aria-label="Side navigation" class="toc">
            <h2><pb-i18n key="document.contents">Contents</pb-i18n></h2>
            {ms:era-toc($context, $a?doc, $a?eraId, $a?division/@xml:id/string())}
        </nav>
};

(:~
 : Article body, rendered through the base ODD's unmatched-mode fallback
 : behaviour (same reasoning as dh:monograph-section-content): the content
 : model here (head/p/persName/placeName/date/ref/hi/figure/graphic, no
 : notes/tables) needs no dedicated ODD mode. A distinct mode name is passed
 : anyway ("milestones-section", not departmenthistory's "monograph-section")
 : to keep this section's rendering concern isolated from departmenthistory's
 : -- confirmed none of hsg-jinks.odd's mode-predicated customisations
 : (date's document-view/breadcrumb/title checks, note's monograph-section
 : check) fire for it, so every element falls through to its ordinary
 : default. $division is passed to page:transform unmodified, still attached
 : to its source document -- an earlier #1096 fix found that detaching a
 : division before transforming it breaks base-uri()-dependent rendering
 : entirely; the explicit <h1> is built from the head's text only, without
 : altering the node handed to page:transform.
 :)
declare function ms:article-content($context as map(*)) as element()+ {
    let $a := ms:current-article($context)
    let $division := $a?division
    return (
        <h1>{normalize-space($division/tei:head[1])}</h1>,
        page:transform($division, map { "mode": "milestones-section" })
    )
};

declare function ms:article-pagination($context as map(*)) as element(nav)? {
    let $a := ms:current-article($context)
    let $nav := ms:era-prev-next($a?doc, $a?division/@xml:id/string())
    return
        if (empty($nav?prev) and empty($nav?next)) then ()
        else
            <nav aria-label="Pagination" class="usa-pagination">
                <ul class="usa-pagination__list">
                {
                    if (exists($nav?prev)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}/milestones/{$a?eraId}/{$nav?prev/@xml:id}" class="usa-pagination__link usa-pagination__previous-page">
                                <pb-i18n key="odd.previous">Previous</pb-i18n>
                            </a>
                        </li>
                    else (),
                    if (exists($nav?next)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}/milestones/{$a?eraId}/{$nav?next/@xml:id}" class="usa-pagination__link usa-pagination__next-page">
                                <pb-i18n key="odd.next">Next</pb-i18n>
                            </a>
                        </li>
                    else ()
                }
                </ul>
            </nav>
};

(:~
 : /milestones/all's grouped listing: every era in chronological order, its
 : own full title heading linking to the era-landing page, followed by a list
 : of its articles (foreword excluded, matching the reference site).
 :)
declare function ms:all-groups($context as map(*)) as element(div)* {
    for $era in ms:eras()
    let $doc := ms:era-doc($era?id)
    return
        <div class="milestones-era-group">
            <h3>
                <a href="{$context?context-path}/milestones/{$era?id}">{$era?label}</a>
            </h3>
            <ul class="usa-list">
            {
                for $article in ms:era-articles($doc)
                return
                    <li>
                        <a href="{$context?context-path}/milestones/{$era?id}/{$article/@xml:id}">{normalize-space($article/tei:head[1])}</a>
                    </li>
            }
            </ul>
        </div>
};
