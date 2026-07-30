xquery version "3.1";

module namespace about="https://history.state.gov/ns/templates/about";

import module namespace page="http://teipublisher.com/ns/templates/page" at "page.xqm";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "../config.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : FAQ and HAC (#1153/#1154) are single-file TEI monographs, each the only
 : document in its own publication -- so, unlike hsgapi:view-interior, a
 : division cannot be addressed by resolving to its own document via
 : document-uri(root(...)); every division lives in the one file. Mirrors
 : departmenthistory.xqm's dh:monograph-* functions (built for Short
 : History/Buildings, the same single-file shape), except the two
 : publications live in different collections rather than a shared parent
 : (FAQ under other-publications, HAC in its own top-level app), so the
 : lookup is a map, not a path formula.
 :)
declare function about:monograph-doc($publication as xs:string) as document-node() {
    switch ($publication)
        case "faq" return doc("/db/apps/other-publications/faq/faq.xml")
        case "hac" return doc("/db/apps/hac/hac.xml")
        default return error(xs:QName("about:UNKNOWN_PUBLICATION"), "no about publication " || $publication)
};

(:~
 : Display title per publication -- hardcoded, not read from the TEI
 : document's own titleStmt: hsg-shell's $config:PUBLICATIONS map carries its
 : own fixed "title" string per publication ("FAQ - About Us", "Historical
 : Advisory Committee - About Us") independent of the TEI, and the two do
 : genuinely differ here -- HAC's own titleStmt/title is the legal-document
 : name "Advisory Committee on Historical Diplomatic Documentation", not the
 : common name the reference site displays as the page heading.
 :)
declare function about:monograph-title($publication as xs:string) as xs:string {
    switch ($publication)
        case "faq" return "Frequently Asked Questions"
        case "hac" return "Historical Advisory Committee"
        default return $publication
};

(:~
 : Resolve a division by @xml:id -- the one lookup aboutapi:monograph-section's
 : 404 guard and about:current-section's template-side re-resolution must
 : agree on exactly. Returns however many elements actually match (0, 1, or
 : more); callers check count() themselves rather than this function
 : silencing a duplicate down to one candidate. HAC's meeting-notes
 : subchapter ids are inconsistently cased in the live data ('March-2025' vs
 : 'december-1996') -- exact string match only, no casing normalization.
 :)
declare function about:monograph-division($doc as document-node(), $sectionId as xs:string) as element(tei:div)* {
    $doc//tei:div[@xml:id = $sectionId]
};

(:~
 : Every division carrying an @xml:id, in document order -- the addressable
 : divisions, used to flatten chapters and their nested subchapters into one
 : reading sequence for prev/next. Not restricted by @type: HAC nests two
 : levels deep (the meeting-notes chapter's subchapters) while FAQ is one
 : flat level of sections.
 :)
declare function about:monograph-divisions($doc as document-node()) as element(tei:div)* {
    $doc//(tei:front | tei:body | tei:back)//tei:div[@xml:id]
};

(:~
 : Table of contents: top-level divisions as items, their own id-bearing
 : child divisions nested beneath (any depth -- in practice only HAC's
 : meeting-notes chapter > subchapter goes two levels; FAQ is flat). Reused
 : as both the TOC page's main content and the section page's sidebar
 : (marks $current), same reasoning as dh:monograph-toc.
 :)
declare function about:monograph-toc($context as map(*), $doc as document-node(), $route as xs:string, $current as xs:string?) as element(ul) {
    about:monograph-toc-level($context, $doc/tei:TEI/tei:text/(tei:front | tei:body | tei:back)/tei:div, $route, $current, "usa-sidenav")
};

declare %private function about:monograph-toc-level($context as map(*), $divisions as element(tei:div)*, $route as xs:string, $current as xs:string?, $listClass as xs:string) as element(ul) {
    <ul class="{$listClass}">
    {
        for $division in $divisions[@xml:id]
        let $id := $division/@xml:id/string()
        let $children := $division/tei:div[@xml:id]
        return
            <li class="usa-sidenav__item">
                <a href="{$context?context-path}/about/{$route}/{$id}">
                {
                    if ($id = $current) then (attribute class {"usa-current"}, attribute aria-current {"page"}) else (),
                    normalize-space($division/tei:head[1])
                }
                </a>
                {if (exists($children)) then about:monograph-toc-level($context, $children, $route, $current, "usa-sidenav__sublist") else ()}
            </li>
    }
    </ul>
};

(:~
 : Previous/next division among about:monograph-divisions, in document
 : order -- flattens chapters and their nested subchapters into one reading
 : sequence.
 :)
declare function about:monograph-prev-next($doc as document-node(), $current as xs:string) as map(*) {
    let $divisions := about:monograph-divisions($doc)
    let $pos := index-of($divisions/@xml:id/string(), $current)[1]
    return map {
        "prev": if ($pos > 1) then $divisions[$pos - 1] else (),
        "next": if ($pos < count($divisions)) then $divisions[$pos + 1] else ()
    }
};

(:~
 : Shared breadcrumb: Home > About Us > $trail. $trail is a sequence of maps
 : { "label": ..., "href": ... }; the last entry renders as the current page
 : (no link). $href is app-relative, e.g. "/about/faq". Mirrors
 : dh:breadcrumb's shape (maps, not arrays -- a trailing array literal ends
 : in a literal "]]", which collides with this templating engine's own
 : "[[ ... ]]" delimiter) so both breadcrumbs nest identically inside the
 : layout's shared wrapper.
 :)
declare function about:breadcrumb($context as map(*), $trail as map(*)*) as element(li)+ {
    (
        <li>
            <a href="{$context?context-path}/">
                <pb-i18n key="breadcrumb.home">Home</pb-i18n>
            </a>
        </li>,
        if (empty($trail)) then
            <li aria-current="page">
                <pb-i18n key="breadcrumb.about">About Us</pb-i18n>
            </li>
        else
            <li>
                <a href="{$context?context-path}/about">
                    <pb-i18n key="breadcrumb.about">About Us</pb-i18n>
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

declare function about:monograph-toc-breadcrumb($context as map(*), $publication as xs:string) as element(li)+ {
    about:breadcrumb($context, (map { "label": about:monograph-title($publication), "href": "/about/" || $publication }))
};

(:~
 : Resolves the requesting publication/section from the request parameters
 : aboutapi:monograph-section threaded through vapi:html. Each of the
 : section page's independent [[ ]] interpolation sites (breadcrumb,
 : sidebar, content, pagination) calls this and re-resolves rather than
 : sharing state -- same reasoning as dh:current-section.
 :)
declare %private function about:current-section($context as map(*)) as map(*) {
    let $publication := $context?request?parameters?publication
    let $sectionId := $context?request?parameters?sectionId
    let $doc := about:monograph-doc($publication)
    let $division := about:monograph-division($doc, $sectionId)
    return map { "publication": $publication, "doc": $doc, "division": $division }
};

declare function about:monograph-section-breadcrumb($context as map(*)) as element(li)+ {
    let $s := about:current-section($context)
    let $parent-division := $s?division/parent::tei:div[@xml:id]
    let $trail := (
        map { "label": about:monograph-title($s?publication), "href": "/about/" || $s?publication },
        if (exists($parent-division)) then
            map { "label": normalize-space($parent-division/tei:head[1]), "href": "/about/" || $s?publication || "/" || $parent-division/@xml:id }
        else (),
        map { "label": normalize-space($s?division/tei:head[1]) }
    )
    return about:breadcrumb($context, $trail)
};

declare function about:monograph-section-sidebar($context as map(*)) as element(nav) {
    let $s := about:current-section($context)
    return
        <nav aria-label="Side navigation" class="toc">
            <h2><pb-i18n key="document.contents">Contents</pb-i18n></h2>
            {about:monograph-toc($context, $s?doc, $s?publication, $s?division/@xml:id/string())}
        </nav>
};

(:~
 : Body of the requested division, rendered through the global ODD's
 : unmatched-mode fallback -- same technique as dh:monograph-section-content
 : (a plain-TEI div with no frus-* markers needs no dedicated ODD mode).
 : $division is passed to page:transform as-is, still attached to its
 : source document (see dh:monograph-section-content's own note on why a
 : detached copy silently breaks page:transform).
 :)
declare function about:monograph-section-content($context as map(*)) as element()+ {
    let $s := about:current-section($context)
    let $division := $s?division
    return (
        <h1>{normalize-space($division/tei:head[1])}</h1>,
        page:transform($division, map { "mode": "monograph-section" })
    )
};

declare function about:monograph-section-pagination($context as map(*)) as element(nav)? {
    let $s := about:current-section($context)
    let $nav := about:monograph-prev-next($s?doc, $s?division/@xml:id/string())
    return
        if (empty($nav?prev) and empty($nav?next)) then ()
        else
            <nav aria-label="Pagination" class="usa-pagination">
                <ul class="usa-pagination__list">
                {
                    if (exists($nav?prev)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}/about/{$s?publication}/{$nav?prev/@xml:id}" class="usa-pagination__link usa-pagination__previous-page">
                                <pb-i18n key="odd.previous">Previous</pb-i18n>
                            </a>
                        </li>
                    else (),
                    if (exists($nav?next)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}/about/{$s?publication}/{$nav?next/@xml:id}" class="usa-pagination__link usa-pagination__next-page">
                                <pb-i18n key="odd.next">Next</pb-i18n>
                            </a>
                        </li>
                    else ()
                }
                </ul>
            </nav>
};

(:~
 : #1156. Not actually static despite hsg-shell's publication-id "app": lists
 : FRUS volumes published in the current or prior year, grouped by year
 : descending -- reaches into the historicaldocuments/FRUS collection from
 : inside the about section, the one bespoke data function in this module.
 : Enumerates volume collections directly (mirrors hsg:volume-list) rather
 : than collection()-scanning $config:data-default: each volume's folder
 : also holds its xincluded division files, which a plain collection() scan
 : would pull in unnecessarily just to read one header-level tei:change.
 :)
declare function about:recent-publications($context as map(*)) as element(section)* {
    let $minYear := year-from-date(current-date()) - 1
    let $volumes :=
        for $volumeId in xmldb:get-child-collections($config:data-default)
        let $path := $config:data-default || "/" || $volumeId || "/" || $volumeId || ".xml"
        return
            if (not(doc-available($path))) then ()
            else
                let $doc := doc($path)
                let $change := $doc//tei:revisionDesc/tei:change[@status = 'published'][1]
                return
                    if (empty($change) or not($change/@when castable as xs:date)) then ()
                    else
                        let $year := year-from-date(xs:date($change/@when))
                        return
                            if ($year < $minYear) then ()
                            else
                                let $title := normalize-space(($doc//tei:titleStmt/tei:title)[1])
                                let $title := replace($title, '^Foreign Relations of the United States,\s*', '')
                                return map { "volumeId": $volumeId, "year": $year, "title": $title }
    for $volume in $volumes
    group by $year := $volume?year
    order by $year descending
    return
        <section>
            <h2>{$year}</h2>
            <ul class="usa-collection">
            {
                for $v in $volume
                order by $v?title
                return
                    <li class="usa-collection__item">
                        <div class="usa-collection__body">
                            <h3 class="usa-collection__heading">
                                <a href="{$context?context-path}/historicaldocuments/{$v?volumeId}">{$v?title}</a>
                            </h3>
                        </div>
                    </li>
            }
            </ul>
        </section>
};
