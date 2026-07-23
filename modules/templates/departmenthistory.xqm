xquery version "3.1";

module namespace dh="https://history.state.gov/ns/templates/departmenthistory";

import module namespace page="http://teipublisher.com/ns/templates/page" at "page.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : Short History and Buildings (#1134/#1135) are single-file TEI monographs --
 : unlike FRUS volumes, which xinclude-split each division into its own
 : physical file -- so, unlike hsgapi:view-interior, a division cannot be
 : addressed by resolving to its own document via document-uri(root(...)).
 : Every chapter/subchapter lives in the one file; dhapi:monograph-section
 : locates the division by @xml:id and hands the div node itself straight to
 : page:transform, bypassing vapi:view's whole-document resolution.
 :)
declare variable $dh:OP_COL := "/db/apps/other-publications";

declare function dh:monograph-doc($publication as xs:string) as document-node() {
    doc($dh:OP_COL || "/" || $publication || "/" || $publication || ".xml")
};

declare function dh:monograph-title($doc as document-node()) as xs:string {
    normalize-space(($doc//tei:titleStmt/tei:title[@type='complete'])[1])
};

declare function dh:monograph-short-title($doc as document-node()) as xs:string {
    normalize-space(($doc//tei:titleStmt/tei:title[@type='short'])[1])
};

(:~
 : Shared Brightcove embed for the four diplomatic-courier films (#1146). All
 : four hsg-shell pages pasted the same account/player script tag with only
 : the video-id differing -- one partial, video-id as data, instead of four
 : copies of the embed markup (and its <script src> CSP liability).
 :)
declare function dh:courier-video($videoId as xs:string) as element(div) {
    <div class="video-wrapper">
        <video class="video-js" controls="controls" data-account="1705665025" data-application-id="" data-embed="default" data-player="HJ8lQG1Eg" data-video-id="{$videoId}"/>
        <script src="https://players.brightcove.net/1705665025/HJ8lQG1Eg_default/index.min.js"/>
    </div>
};

(:~
 : Resolve a division by @xml:id -- the one lookup dhapi:monograph-section's
 : 404 guard and dh:current-section's template-side re-resolution must agree
 : on exactly. Returns however many elements actually match (0, 1, or more,
 : the last from a malformed document with a duplicate id); callers check
 : count() themselves rather than this function silencing a duplicate down to
 : one candidate.
 :)
declare function dh:monograph-division($doc as document-node(), $sectionId as xs:string) as element(tei:div)* {
    $doc//tei:div[@xml:id = $sectionId]
};

(:~
 : Every division carrying an @xml:id, in document order -- the addressable
 : divisions. Not restricted by @type: short-history nests two levels deep
 : (chapter > subchapter) while buildings is one flat level (section), so the
 : traversal follows actual DOM nesting rather than assumed type values.
 :
 : An un-id'd division (short-history's lead-in subchapters, the old app's
 : hardcoded "intro" section-id for buildings -- ticket #1134's rework note)
 : is skipped rather than special-cased: it has no id to link to, and its
 : content still reaches the reader because it is nested inside its
 : addressable ancestor's div, which page:transform renders in full.
 :)
declare function dh:monograph-divisions($doc as document-node()) as element(tei:div)* {
    $doc//tei:body//tei:div[@xml:id]
};

(:~
 : Table of contents: top-level divisions as items, their own id-bearing
 : child divisions nested beneath (any depth, though in practice only
 : short-history's chapter > subchapter goes two levels -- buildings is
 : flat). Reused as both the TOC page's main content (#1134) and the section
 : page's left sidebar (#1135, marks $current) -- one traversal, two
 : placements, same reasoning as hsg:volume-toc.
 :)
declare function dh:monograph-toc($context as map(*), $doc as document-node(), $route as xs:string, $current as xs:string?) as element(ul) {
    dh:monograph-toc-level($context, $doc/tei:TEI/tei:text/tei:body/tei:div, $route, $current, "usa-sidenav")
};

declare %private function dh:monograph-toc-level($context as map(*), $divisions as element(tei:div)*, $route as xs:string, $current as xs:string?, $listClass as xs:string) as element(ul) {
    <ul class="{$listClass}">
    {
        for $division in $divisions[@xml:id]
        let $id := $division/@xml:id/string()
        let $children := $division/tei:div[@xml:id]
        return
            <li class="usa-sidenav__item">
                <a href="{$context?context-path}/departmenthistory/{$route}/{$id}">
                {
                    if ($id = $current) then (attribute class {"usa-current"}, attribute aria-current {"page"}) else (),
                    normalize-space($division/tei:head[1])
                }
                </a>
                {if (exists($children)) then dh:monograph-toc-level($context, $children, $route, $current, "usa-sidenav__sublist") else ()}
            </li>
    }
    </ul>
};

(:~
 : Previous/next division among dh:monograph-divisions, in document order --
 : flattens chapters and their nested subchapters into one reading sequence.
 :)
declare function dh:monograph-prev-next($doc as document-node(), $current as xs:string) as map(*) {
    let $divisions := dh:monograph-divisions($doc)
    let $pos := index-of($divisions/@xml:id/string(), $current)[1]
    return map {
        "prev": if ($pos > 1) then $divisions[$pos - 1] else (),
        "next": if ($pos < count($divisions)) then $divisions[$pos + 1] else ()
    }
};

(:~
 : Section-page breadcrumb: Home > Department History > <monograph short
 : title> > [chapter title, if $division is one of its subchapters] >
 : current division title. Delegates to dh:breadcrumb for the shared prefix
 : and current-crumb rendering.
 :)
declare function dh:monograph-breadcrumb($context as map(*), $doc as document-node(), $route as xs:string, $division as element(tei:div)) as element(li)+ {
    let $parent-division := $division/parent::tei:div[@xml:id]
    let $trail := (
        map { "label": dh:monograph-short-title($doc), "href": "/departmenthistory/" || $route },
        if (exists($parent-division)) then
            map { "label": normalize-space($parent-division/tei:head[1]), "href": "/departmenthistory/" || $route || "/" || $parent-division/@xml:id }
        else (),
        map { "label": normalize-space($division/tei:head[1]) }
    )
    return dh:breadcrumb($context, $trail)
};

(:~
 : Static section breadcrumb: Home > Department History > $trail. $trail is a
 : sequence of maps { "label": ..., "href": ... }; the last entry renders as
 : the current page (no link). $href is app-relative, e.g.
 : "/departmenthistory/people".
 :
 : Maps, not arrays: a trailing array literal ends in a literal "]]", which
 : collides with this templating engine's "[[ ... ]]" expression delimiter --
 : it closes the interpolation at the first "]]" it scans, truncating the
 : expression. Maps close on "}", so they cannot produce that collision.
 :
 : The section's hub and static-article pages have no backing document, so
 : there is nothing for an ODD-driven breadcrumb (hsg:collection-breadcrumbs's
 : approach on historicaldocuments) to walk -- the trail is fixed per page
 : instead. Mirrors that function's <li> shape so both breadcrumbs nest
 : identically inside the layout's shared wrapper.
 :)
declare function dh:breadcrumb($context as map(*), $trail as map(*)*) as element(li)+ {
    (
        <li>
            <a href="{$context?context-path}/">
                <pb-i18n key="breadcrumb.home">Home</pb-i18n>
            </a>
        </li>,
        if (empty($trail)) then
            <li aria-current="page">
                <pb-i18n key="breadcrumb.departmenthistory">Department History</pb-i18n>
            </li>
        else
            <li>
                <a href="{$context?context-path}/departmenthistory">
                    <pb-i18n key="breadcrumb.departmenthistory">Department History</pb-i18n>
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
 : Title + table of contents for a monograph's TOC page (#1134). One function
 : call per template interpolation site, same style as hsg:volume-list on
 : historicaldocuments.html.
 :)
declare function dh:monograph-toc-page($context as map(*), $publication as xs:string) as element()+ {
    let $doc := dh:monograph-doc($publication)
    return (
        <h1>{dh:monograph-title($doc)}</h1>,
        dh:monograph-toc($context, $doc, $publication, ())
    )
};

declare function dh:monograph-toc-breadcrumb($context as map(*), $publication as xs:string) as element(li)+ {
    let $doc := dh:monograph-doc($publication)
    return dh:breadcrumb($context, (map { "label": dh:monograph-short-title($doc), "href": "/departmenthistory/" || $publication }))
};

(:~
 : Resolves the requesting publication/section from the request parameters
 : dhapi:monograph-section threaded through vapi:html. Each of the section
 : page's four independent [[ ]] interpolation sites (breadcrumb, sidebar,
 : content, pagination) calls this and re-resolves rather than sharing state
 : -- there is no way to share a `let` binding across separate template
 : blocks, and doc()/id() lookups are cheap against an in-memory eXist
 : collection.
 :)
declare %private function dh:current-section($context as map(*)) as map(*) {
    let $publication := $context?request?parameters?publication
    let $sectionId := $context?request?parameters?sectionId
    let $doc := dh:monograph-doc($publication)
    let $division := dh:monograph-division($doc, $sectionId)
    return map { "publication": $publication, "doc": $doc, "division": $division }
};

declare function dh:monograph-section-breadcrumb($context as map(*)) as element(li)+ {
    let $s := dh:current-section($context)
    return dh:monograph-breadcrumb($context, $s?doc, $s?publication, $s?division)
};

declare function dh:monograph-section-sidebar($context as map(*)) as element(nav) {
    let $s := dh:current-section($context)
    return
        <nav aria-label="Side navigation" class="toc">
            <h2><pb-i18n key="document.contents">Contents</pb-i18n></h2>
            {dh:monograph-toc($context, $s?doc, $s?publication, $s?division/@xml:id/string())}
        </nav>
};

(:~
 : Body of the requested division, rendered through the base ODD's
 : unmatched-mode fallback (div elementSpec's predicate-less
 : behaviour="block") rather than a dedicated ODD mode: passing a plain-TEI
 : div node with no frus-* markers needs no more than that default wrapping,
 : and head/p/graphic/hi already fall through to teipublisher.odd with no
 : override in this app's ODD.
 :
 : No separate <h1> here: teipublisher.odd already renders the division's own
 : <head> as the top heading of whatever subtree it's handed (confirmed live
 : -- passing $division re-bases heading levels from that node, not from its
 : absolute depth in the full document), so adding one here just duplicated
 : it.
 :
 : Known gap: graphics carry bare filenames (e.g. "sh-jmonroe.jpg") with no
 : base URI fix yet -- tracked as data-transformation rework (#1147), not
 : fixed here.
 :)
declare function dh:monograph-section-content($context as map(*)) as element()+ {
    let $s := dh:current-section($context)
    return page:transform($s?division, map { "mode": "monograph-section" })
};

declare function dh:monograph-section-pagination($context as map(*)) as element(nav)? {
    let $s := dh:current-section($context)
    let $nav := dh:monograph-prev-next($s?doc, $s?division/@xml:id/string())
    return
        if (empty($nav?prev) and empty($nav?next)) then ()
        else
            <nav aria-label="Pagination" class="usa-pagination">
                <ul class="usa-pagination__list">
                {
                    if (exists($nav?prev)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}/departmenthistory/{$s?publication}/{$nav?prev/@xml:id}" class="usa-pagination__link usa-pagination__previous-page">
                                <pb-i18n key="odd.previous">Previous</pb-i18n>
                            </a>
                        </li>
                    else (),
                    if (exists($nav?next)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}/departmenthistory/{$s?publication}/{$nav?next/@xml:id}" class="usa-pagination__link usa-pagination__next-page">
                                <pb-i18n key="odd.next">Next</pb-i18n>
                            </a>
                        </li>
                    else ()
                }
                </ul>
            </nav>
};
