xquery version "3.1";

module namespace conf="https://history.state.gov/ns/templates/conferences";

import module namespace page="http://teipublisher.com/ns/templates/page" at "page.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : Five frozen conference-proceedings documents (last addition 2012), one
 : file per conference -- unlike FRUS volumes, which xinclude-split each
 : division into its own physical file, every division of a conference
 : lives in the one document. So, like departmenthistory's monographs
 : (dh:monograph-*) and unlike hsgapi:view-interior, a division cannot be
 : addressed by resolving to its own document via document-uri(root(...)).
 : confapi:view / confapi:view-section locate the conference/division by id
 : and hand plain request parameters to vapi:html; the templates call back
 : into this module (dh's own pattern) rather than going through vapi:view's
 : whole-document doc.content resolution.
 :)
declare variable $conf:CONFERENCES_COL := "/db/apps/conferences/data";

declare function conf:conference-doc($conferenceId as xs:string) as document-node()? {
    let $path := $conf:CONFERENCES_COL || "/" || $conferenceId || ".xml"
    return
        if (doc-available($path)) then doc($path) else ()
};

declare function conf:conference-title($doc as document-node()) as xs:string {
    normalize-space(($doc//tei:titleStmt/tei:title)[1])
};

declare %private function conf:conference-date-sortkey($doc as document-node()) as xs:string? {
    let $date := (($doc//tei:sourceDesc/tei:scriptStmt/tei:bibl)[1]/tei:date)[1]
    return ($date/@when/string(), $date/@from/string())[1]
};

(:~
 : Reference-site parity (hsg-shell's pages/conferences/index.xml, the
 : hand-authored landing-page list): teiHeader's sourceDesc/scriptStmt/bibl/
 : date is the only structured date available, and it disagrees with the
 : reference's own display text for 3 of the 5 conferences -- a plain hyphen
 : where the reference uses an en dash (2006, 2010), and a single day
 : (2007-10-22) where the reference's own text is a two-day range
 : ("October 22-23, 2007"). Curated per conference here rather than derived,
 : so the rendered text matches the reference exactly; falls back to the
 : header's own date text for any future (uncurated) conference.
 :)
declare variable $conf:LANDING_DATE_OVERRIDE := map {
    "2012-national-security-policy-salt": "March 2-3, 2012",
    "2011-foreign-economic-policy": "March 7, 2011",
    "2010-southeast-asia": "September 29–30, 2010",
    "2007-detente": "October 22–23, 2007",
    "2006-china-cold-war": "September 25–27, 2006"
};

(:~
 : The FRUS "Special Conference Series" note: not data anywhere (teiHeader
 : has no such field), only prose on the reference landing page, and only
 : for these 2 of the 5 conferences. Curated here for the same reason as
 : $conf:LANDING_DATE_OVERRIDE.
 :)
declare variable $conf:LANDING_SERIES_NOTE := (
    "2012-national-security-policy-salt",
    "2011-foreign-economic-policy"
);

declare function conf:conference-date-label($doc as document-node(), $id as xs:string) as xs:string {
    (
        map:get($conf:LANDING_DATE_OVERRIDE, $id),
        normalize-space((($doc//tei:sourceDesc/tei:scriptStmt/tei:bibl)[1]/tei:date)[1])
    )[1]
};

(:~
 : All 5 conferences, most recent first -- matching the reference landing
 : page's order exactly (2012, 2011, 2010, 2007, 2006) -- one data source
 : shared by the landing page's body list and both sidebars, so a new
 : conference appears everywhere without a template edit (#1111's rework
 : goal), landing at the top by date without needing its own curation.
 :)
declare function conf:conferences() as map(*)* {
    for $name in xmldb:get-child-resources($conf:CONFERENCES_COL)
    where ends-with($name, ".xml")
    let $id := substring-before($name, ".xml")
    let $doc := doc($conf:CONFERENCES_COL || "/" || $name)
    order by conf:conference-date-sortkey($doc) descending
    return map {
        "id": $id,
        "title": conf:conference-title($doc),
        "date": conf:conference-date-label($doc, $id),
        "series": $id = $conf:LANDING_SERIES_NOTE
    }
};

(:~
 : The reference's own list (hsg-shell's pages/conferences/index.xml) is a
 : numbered <ol>. USWDS's usa-collection component strips list markers
 : unconditionally regardless of tag name (unstyled-list mixin on
 : .usa-collection__item), so numbering is restored for this list only, via
 : the conf-conference-list class (resources/css/hsg-theme.css) -- every
 : other usa-collection use in the app (dh:*, modules/templates/
 : departmenthistory.xqm) is an unordered <ul> and must stay unaffected.
 :)
declare function conf:conference-list($context as map(*)) as element(ol) {
    <ol class="usa-collection conf-conference-list">
    {
        for $c in conf:conferences()
        return
            <li class="usa-collection__item">
                <div class="usa-collection__body">
                    <h3 class="usa-collection__heading">
                        <a href="{$context?context-path}/conferences/{$c?id}" class="usa-link">{$c?title}</a>
                    </h3>
                    <div class="usa-collection__meta">
                        {
                            if ($c?series) then
                                <span class="usa-collection__meta-item">
                                    <em>Foreign Relations of the United States</em> Special Conference Series
                                </span>
                            else ()
                        }
                        <span class="usa-collection__meta-item">{$c?date}</span>
                    </div>
                </div>
            </li>
    }
    </ol>
};

(:~
 : Same conference list as conf:conference-list, rendered as a usa-sidenav --
 : hsg-shell's document view shows both the TOC and this list side by side
 : (conference/index.xml), so it is a separate nav rather than conf:toc's.
 :)
declare function conf:conference-sidebar-list($context as map(*)) as element(nav) {
    <nav aria-label="Side navigation" class="toc">
        <h2><pb-i18n key="conferences.title">Conferences</pb-i18n></h2>
        <ul class="usa-sidenav">
        {
            for $c in conf:conferences()
            return
                <li class="usa-sidenav__item">
                    <a href="{$context?context-path}/conferences/{$c?id}">{$c?title}</a>
                </li>
        }
        </ul>
    </nav>
};

(:~
 : Every division carrying an @xml:id, in document order -- not restricted
 : by @type or depth: the 5 documents mix section/subchapter/chapter at
 : inconsistent nesting (verified live), so the traversal follows actual DOM
 : structure rather than an assumed vocabulary, same reasoning as
 : dh:monograph-divisions.
 :)
declare function conf:divisions($doc as document-node()) as element(tei:div)* {
    $doc//tei:div[@xml:id]
};

declare function conf:division($doc as document-node(), $sectionId as xs:string) as element(tei:div)* {
    $doc//tei:div[@xml:id = $sectionId]
};

(:~
 : Table of contents: top-level divisions as items, their own id-bearing
 : child divisions nested beneath at any depth. Rendered as usa-sidenav, same
 : as historicaldocuments' hsg:volume-toc -- not usa-in-page-nav as #1112/
 : #1113's rough mapping first suggested. Verified live in a real browser
 : (Cypress caught it, not a code read): USWDS's usa-in-page-nav ships its own
 : JS that discards any hand-authored list and rebuilds it from <main>'s own
 : h2/h3 headings via IntersectionObserver, expecting every link to be a
 : same-page "#anchor" scroll target. Conferences' divisions are separate
 : pages (like historicaldocuments' divisions, unlike an in-page-nav's
 : intended use), so its JS throws (null.offsetParent) the moment it runs
 : against this markup. usa-sidenav has no such expectation -- it is a plain
 : nav tree, exactly what a cross-page division TOC needs.
 :
 : Reused on both the document view (no $current) and the section view
 : (marks $current), same reasoning as dh:monograph-toc / hsg:volume-toc.
 :)
declare function conf:toc($context as map(*), $doc as document-node(), $conferenceId as xs:string, $current as xs:string?) as element(nav) {
    <nav aria-label="Table of contents" class="toc">
        <h2><pb-i18n key="document.contents">Contents</pb-i18n></h2>
        <ul class="usa-sidenav">
        { conf:toc-level($context, $doc/tei:TEI/tei:text/tei:body/tei:div, $conferenceId, $current) }
        </ul>
    </nav>
};

declare %private function conf:toc-level($context as map(*), $divisions as element(tei:div)*, $conferenceId as xs:string, $current as xs:string?) as element(li)* {
    for $division in $divisions[@xml:id]
    let $id := $division/@xml:id/string()
    let $children := $division/tei:div[@xml:id]
    return
        <li class="usa-sidenav__item">
            <a href="{$context?context-path}/conferences/{$conferenceId}/{$id}">
            {
                if ($id = $current) then (attribute class {"usa-current"}, attribute aria-current {"page"}) else (),
                normalize-space($division/tei:head[1])
            }
            </a>
            {
                if (exists($children)) then
                    <ul class="usa-sidenav__sublist">
                    { conf:toc-level($context, $children, $conferenceId, $current) }
                    </ul>
                else ()
            }
        </li>
};

(:~
 : Resolves the requesting conference/section from the request parameters
 : confapi:view-section threaded through vapi:html. Each of the section
 : page's independent [[ ]] interpolation sites re-resolves rather than
 : sharing state, same reasoning as dh:current-section.
 :)
declare %private function conf:current-section($context as map(*)) as map(*) {
    let $conferenceId := $context?request?parameters?conferenceId
    let $sectionId := $context?request?parameters?sectionId
    let $doc := conf:conference-doc($conferenceId)
    let $division := conf:division($doc, $sectionId)
    return map { "conferenceId": $conferenceId, "doc": $doc, "division": $division }
};

declare function conf:document-breadcrumb($context as map(*)) as element(li)+ {
    let $conferenceId := $context?request?parameters?conferenceId
    let $doc := conf:conference-doc($conferenceId)
    return conf:breadcrumb($context, (map { "label": conf:conference-title($doc) }))
};

declare function conf:section-breadcrumb($context as map(*)) as element(li)+ {
    let $s := conf:current-section($context)
    return conf:breadcrumb($context, (
        map { "label": conf:conference-title($s?doc), "href": "/conferences/" || $s?conferenceId },
        map { "label": normalize-space($s?division/tei:head[1]) }
    ))
};

(:~
 : Static section breadcrumb: Home > Conferences > $trail. $trail is a
 : sequence of maps { "label": ..., "href": ... }; the last entry renders as
 : the current page (no link). $href is app-relative. Maps, not arrays: a
 : trailing array literal ends in a literal "]]", which collides with this
 : templating engine's "[[ ... ]]" delimiter -- same reasoning as
 : dh:breadcrumb, whose <li> shape this mirrors so both nest identically
 : inside the layout's shared wrapper.
 :)
declare function conf:breadcrumb($context as map(*), $trail as map(*)*) as element(li)+ {
    (
        <li>
            <a href="{$context?context-path}/">
                <pb-i18n key="breadcrumb.home">Home</pb-i18n>
            </a>
        </li>,
        if (empty($trail)) then
            <li aria-current="page">
                <pb-i18n key="breadcrumb.conferences">Conferences</pb-i18n>
            </li>
        else
            <li>
                <a href="{$context?context-path}/conferences">
                    <pb-i18n key="breadcrumb.conferences">Conferences</pb-i18n>
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
 : Full document content (equivalent of hsg-shell's conference/index.xml
 : with no section-id: pages:load-xml's default view renders the whole
 : tei:body, not a summary). No footnote consolidation needed -- none of the
 : 5 documents contain tei:note (verified live).
 :)
declare function conf:document-content($context as map(*)) as element()+ {
    let $conferenceId := $context?request?parameters?conferenceId
    let $doc := conf:conference-doc($conferenceId)
    return (
        <h1>{conf:conference-title($doc)}</h1>,
        page:transform($doc/tei:TEI/tei:text/tei:body, map { "mode": "conf-content" })
    )
};

declare function conf:document-sidebar($context as map(*)) as element()+ {
    let $conferenceId := $context?request?parameters?conferenceId
    let $doc := conf:conference-doc($conferenceId)
    return (
        conf:toc($context, $doc, $conferenceId, ()),
        conf:conference-sidebar-list($context)
    )
};

(:~
 : Body of the requested division. Passed to page:transform still attached
 : to its source document (needed for base-uri()-dependent rendering, e.g.
 : the graphic/@url resolution model) -- never detach/reconstruct it, same
 : pitfall documented at dh:monograph-section-content.
 :)
declare function conf:section-content($context as map(*)) as element()+ {
    let $s := conf:current-section($context)
    return (
        <h1>{normalize-space($s?division/tei:head[1])}</h1>,
        page:transform($s?division, map { "mode": "conf-content" })
    )
};

declare function conf:section-sidebar($context as map(*)) as element(nav) {
    let $s := conf:current-section($context)
    return conf:toc($context, $s?doc, $s?conferenceId, $s?division/@xml:id/string())
};

(:~
 : Previous/next division among conf:divisions, in document order.
 :)
declare function conf:prev-next($doc as document-node(), $current as xs:string) as map(*) {
    let $divisions := conf:divisions($doc)
    let $pos := index-of($divisions/@xml:id/string(), $current)[1]
    return map {
        "prev": if ($pos > 1) then $divisions[$pos - 1] else (),
        "next": if ($pos < count($divisions)) then $divisions[$pos + 1] else ()
    }
};

declare function conf:section-pagination($context as map(*)) as element(nav)? {
    let $s := conf:current-section($context)
    let $nav := conf:prev-next($s?doc, $s?division/@xml:id/string())
    return
        if (empty($nav?prev) and empty($nav?next)) then ()
        else
            <nav aria-label="Pagination" class="usa-pagination">
                <ul class="usa-pagination__list">
                {
                    if (exists($nav?prev)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}/conferences/{$s?conferenceId}/{$nav?prev/@xml:id}" class="usa-pagination__link usa-pagination__previous-page">
                                <pb-i18n key="odd.previous">Previous</pb-i18n>
                            </a>
                        </li>
                    else (),
                    if (exists($nav?next)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}/conferences/{$s?conferenceId}/{$nav?next/@xml:id}" class="usa-pagination__link usa-pagination__next-page">
                                <pb-i18n key="odd.next">Next</pb-i18n>
                            </a>
                        </li>
                    else ()
                }
                </ul>
            </nav>
};
