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

(:~
 : POCOM (Principal Officers & Chiefs of Mission) is the epic's "no-ODD"
 : record-rendering concern (#1147's data-transformation decision): plain,
 : unnamespaced custom XML -- not TEI -- with thousands of small records
 : joined by id, not a document tree the ODD can transform. Every POCOM page
 : is server-side XQuery computing HTML directly, the same way
 : hsg:volume-list computes historicaldocuments' section-landing list, just
 : with joins instead of a single traversal.
 :
 : #1136 (Secretaries) is this concern's pilot, per the ticket's own text --
 : the simplest record-backed page, one file
 : (positions-principals/secretary.xml), no cross-collection joins yet
 : (principal officers/chiefs of mission add code-table and
 : concurrent-appointments joins; by-name/by-year add range queries across
 : the whole 4,261-person collection).
 :)
declare variable $dh:POCOM_COL := "/db/apps/pocom";

(:~
 : A person record by id. Unindexed collection scan across 4,261 files --
 : same technique hsg-shell's pocom-html.xqm used (collection(...)/person[id
 : = $id]) -- acceptable for a pilot; worth an index if per-page latency
 : becomes a problem once by-name/by-year (#1137/#1138) are querying this
 : collection on every request instead of a handful of times per secretaries
 : list.
 :)
declare function dh:person-doc($personId as xs:string) as element(person)? {
    collection($dh:POCOM_COL || "/people")/person[id = $personId]
};

(:~
 : Display name, forename before surname -- same order as hsg-shell's
 : pocom:person-name-by-id. genName (e.g. "Jr.") appended when present.
 :)
declare function dh:person-name($person as element(person)?) as xs:string {
    if (empty($person)) then
        ()
    else
        string-join(
            ($person/persName/forename, $person/persName/surname, $person/persName/genName)
                ! normalize-space(.)[. != ''],
            ' '
        )
};

(:~
 : Walks forward through immediately-following @treatAsConsecutive siblings
 : to find the principal whose <ended> date is the term-chain's real end.
 : Confirmed against the live data: of secretary.xml's 72 <principal>
 : entries, exactly one (James Monroe's second term, 1815) carries
 : @treatAsConsecutive="yes" -- the two entries have a real gap between them
 : (1814-09-30 to 1815-02-28) but are displayed as one continuous term.
 : Recursion depth is bounded by how many consecutive entries chain
 : together, which in the observed data is never more than two.
 :)
declare %private function dh:secretary-chain-end($principal as element(principal), $following as element(principal)*) as element(principal) {
    if (exists($following) and $following[1]/@treatAsConsecutive = 'yes') then
        dh:secretary-chain-end($following[1], subsequence($following, 2))
    else
        $principal
};

(:~
 : Ordered list of Secretaries of State (#1136), each entry's year range
 : computed via dh:secretary-chain-end -- consecutive terms merge into one
 : entry, non-consecutive re-appointments (several Secretaries served
 : non-adjacent terms without the flag) each get their own. No end date
 : (@current) renders as "-present".
 :)
declare function dh:secretaries($context as map(*)) as element(ol) {
    let $doc := doc($dh:POCOM_COL || "/positions-principals/secretary.xml")
    let $principals := $doc//principals/principal
    return
        <ol class="usa-prose">
        {
            for $p at $pos in $principals
            where not($p/@treatAsConsecutive = 'yes')
            let $following := subsequence($principals, $pos + 1)
            let $chain-end := dh:secretary-chain-end($p, $following)
            let $person := dh:person-doc($p/person-id)
            let $start-year := substring($p/started/date, 1, 4)
            let $end-date := normalize-space($chain-end/ended/date)
            let $end-year := if ($end-date != '') then substring($end-date, 1, 4) else 'present'
            return
                <li>
                    <a href="{$context?context-path}/departmenthistory/people/{$p/person-id/string()}">{dh:person-name($person)}</a>
                    <span> ({$start-year}&#8211;{$end-year})</span>
                </li>
        }
        </ol>
};

(:~
 : #1141, the section's most complex page and its only TEI/record hybrid.
 :
 : Deliberately simplified against hsg-shell's pocom-html.xqm
 : (format-roles/format-role/sort-roles, ~250 lines): every role this person
 : held renders as its own chronological entry with a plain start-end year
 : range, rather than grouping concurrent appointments into one entry with an
 : auto-generated cross-accreditation summary, and country/org role dates use
 : a single started/ended range rather than the full
 : Appointed/Entry-on-Duty/Assumed-Charge/Presentation-of-Credentials/
 : Termination label set that varies by role class. Both are real gaps versus
 : the reference site, tracked here rather than silently matched -- fixing
 : them needs concurrent-appointments joins and the role-class date-label
 : rules, deferred rather than guessed at for this first pass.
 :)

(:~
 : Bare-title-case display for a territory id ("united-kingdom" ->
 : "United Kingdom"). A placeholder for the proper lookup #1140 needs (the
 : gsh countries-old dataset resolves historical vs. contemporary territory
 : names, e.g. a mission's territory-id may differ from its
 : contemporary-territory-id) -- good enough to make a role entry readable
 : without that dependency.
 :)
declare %private function dh:territory-label($territoryId as xs:string) as xs:string {
    string-join(
        for $word in tokenize($territoryId, '-')
        return upper-case(substring($word, 1, 1)) || substring($word, 2),
        ' '
    )
};

(:~
 : Every role a person held, across all three POCOM position collections,
 : in chronological order. Three collection scans per person page -- fine at
 : POCOM's size (83 principal positions + 199 country missions + 16 org
 : missions, none large) but revisit if this page's latency becomes a
 : problem.
 :)
declare function dh:person-roles($personId as xs:string) as map(*)* {
    let $principal-roles :=
        for $position in collection($dh:POCOM_COL || "/positions-principals")/principal-position
        for $principal in $position/principals/principal[person-id = $personId]
        return map {
            "title": normalize-space($position/names/singular),
            "start": $principal/started/date/string(),
            "end": $principal/ended/date/string()
        }
    let $country-roles :=
        for $mission in collection($dh:POCOM_COL || "/missions-countries")/country-mission
        for $chief in $mission/chiefs/chief[person-id = $personId]
        let $role-title := collection($dh:POCOM_COL || "/roles-country-chiefs")/role[id = $chief/role-title-id]/names/singular
        return map {
            "title": normalize-space($role-title) || " to " || dh:territory-label($mission/territory-id),
            "start": $chief/started/date/string(),
            "end": $chief/ended/date/string()
        }
    let $org-roles :=
        for $org in collection($dh:POCOM_COL || "/missions-orgs")/org-mission
        for $chief in $org/chiefs/chief[person-id = $personId]
        return map {
            "title": normalize-space($org/names/singular),
            "start": $chief/started/date/string(),
            "end": $chief/ended/date/string()
        }
    for $role in ($principal-roles, $country-roles, $org-roles)
    order by $role?start
    return $role
};

declare function dh:person-service-record($personId as xs:string) as element(ul) {
    <ul class="usa-collection">
    {
        for $role in dh:person-roles($personId)
        let $start-year := if (normalize-space($role?start) != '') then substring($role?start, 1, 4) else '?'
        let $end-year := if (normalize-space($role?end) != '') then substring($role?end, 1, 4) else 'present'
        return
            <li class="usa-collection__item">
                <div class="usa-collection__body">
                    <h3 class="usa-collection__heading">{$role?title}</h3>
                    <p class="usa-collection__meta">{$start-year}&#8211;{$end-year}</p>
                </div>
            </li>
    }
    </ul>
};

declare function dh:person-name-birth-death($person as element(person)?) as xs:string {
    let $birth := normalize-space($person/birth)
    let $death := normalize-space($person/death)
    return dh:person-name($person)
        || ' (' || (if ($birth != '') then $birth else '?')
        || '&#8211;' || (if ($death != '') then $death else '?') || ')'
};

(:~
 : Canonical id for a superseded old-id (#1141's 63-old-id 302 requirement),
 : e.g. verveer-melanne's recorded old-id verveer-mellane. Same collection
 : scan technique as dh:person-doc.
 :)
declare function dh:person-canonical-id-for-old-id($oldId as xs:string) as xs:string? {
    collection($dh:POCOM_COL || "/people")/person[old-ids/old-id = $oldId][1]/id/string()
};

(:~
 : Whether the person has a secretary-bios TEI biography (69 of them,
 : filename = person-id). Drives the template's choice between the
 : biography-as-main-content layout and the record-only layout with the
 : hiatus notice -- kept in the template ([% if %] can't call into a
 : template partial from XQuery) rather than folded into
 : dh:person-page-content below.
 :)
declare function dh:person-has-bio($personId as xs:string) as xs:boolean {
    doc-available($dh:OP_COL || "/secretary-bios/" || $personId || ".xml")
};

declare function dh:person-breadcrumb($context as map(*)) as element(li)+ {
    let $personId := $context?request?parameters?personId
    let $person := dh:person-doc($personId)
    return dh:breadcrumb($context, (
        map { "label": "People", "href": "/departmenthistory/people" },
        map { "label": dh:person-name($person) }
    ))
};

(:~
 : Main content: the TEI biography (rendered through the base ODD's
 : mode='division' pass-through, same technique as historicaldocuments'
 : back-matter divisions -- a single-document, single-page article needs no
 : new ODD work) plus the POCOM record as a sidebar summary when a biography
 : exists; the POCOM record alone, as the page's main content, otherwise.
 : dh:person-has-bio in the template decides which -- this function only
 : renders whichever main-content body was asked for.
 :)
(:~
 : Split from the body (below) so the template can insert the hiatus notice
 : between the heading and the body on the no-bio branch, matching
 : hsg-shell's layout -- name heading, then the notice, then the record.
 :)
declare function dh:person-heading($context as map(*)) as element(h1) {
    let $personId := $context?request?parameters?personId
    let $person := dh:person-doc($personId)
    return
        if (dh:person-has-bio($personId)) then
            <h1>Biographies of the Secretaries of State: {dh:person-name-birth-death($person)}</h1>
        else
            <h1>{dh:person-name-birth-death($person)}</h1>
};

declare function dh:person-body($context as map(*)) as element()+ {
    let $personId := $context?request?parameters?personId
    return
        if (dh:person-has-bio($personId)) then
            let $bio := doc($dh:OP_COL || "/secretary-bios/" || $personId || ".xml")
            return (
                page:transform($bio/tei:TEI, map { "mode": "division" }),
                <aside class="usa-card">
                    <div class="usa-card__container">
                        <div class="usa-card__header">
                            <h2 class="usa-card__heading">From Principal Officers and Chiefs of Mission</h2>
                        </div>
                        <div class="usa-card__body">
                            {dh:person-service-record($personId)}
                        </div>
                    </div>
                </aside>
            )
        else
            dh:person-service-record($personId)
};

(:~
 : #1137/#1138 share this: the A-Z browse (surname-initial subcollections)
 : and the chronological browse (all role date ranges) both list people with
 : the same per-person nested role summary. dh:person-service-record, built
 : for #1141's own page, is that one shared formatter -- the ticket's own
 : "extract one formatter" instruction, done by reuse rather than a new
 : function.
 :)

(:~
 : People are stored in per-surname-initial subcollections
 : (pocom/people/{a..z}), one eXist collection listing rather than
 : hsg-shell's distinct-values() scan over every surname in the 4,260-person
 : collection -- same result (confirmed: 25 letters present, no "x"), cheaper
 : to compute.
 :)
declare function dh:people-letters() as xs:string* {
    for $letter in xmldb:get-child-collections($dh:POCOM_COL || "/people")
    order by $letter
    return $letter
};

declare function dh:people-by-letter($letter as xs:string) as element(person)* {
    for $person in collection($dh:POCOM_COL || "/people/" || $letter)/person
    order by $person/id
    return $person
};

(:~
 : Career-officer marker (career-type = 'career' or 'both'), a plain "*"
 : prefix matching hsg-shell's pocom:format-index. Shared by the by-name and
 : by-year listings.
 :)
declare function dh:people-list($context as map(*), $people as element(person)*) as element(ul) {
    <ul class="usa-collection">
    {
        for $person in $people
        let $marker := if ($person/career-type = ('career', 'both')) then '* ' else ()
        return
            <li class="usa-collection__item">
                <div class="usa-collection__body">
                    <h3 class="usa-collection__heading">
                        <a href="{$context?context-path}/departmenthistory/people/{$person/id}">{$marker}{dh:person-name-birth-death($person)}</a>
                    </h3>
                    {dh:person-service-record($person/id/string())}
                </div>
            </li>
    }
    </ul>
};

(:~
 : Letter pills for the by-name index and every listing page's own
 : navigation -- only letters with people, not a fixed A-Z run (matches
 : hsg-shell's pocom:letters; #1140's country/org index pages have their own
 : separate concerns and don't reuse this).
 :)
declare function dh:people-by-name-nav($context as map(*), $current as xs:string?) as element(ul) {
    <ul class="usa-button-group">
    {
        for $letter in dh:people-letters()
        return
            <li class="usa-button-group__item">
                <a class="usa-button usa-button--outline{if ($letter = $current) then ' usa-current' else ()}" href="{$context?context-path}/departmenthistory/people/by-name/{$letter}">{upper-case($letter)}</a>
            </li>
    }
    </ul>
};

declare function dh:people-by-name-prev-next($context as map(*), $letter as xs:string) as element(nav)? {
    let $letters := dh:people-letters()
    let $pos := index-of($letters, $letter)[1]
    let $prev := if ($pos > 1) then $letters[$pos - 1] else ()
    let $next := if ($pos < count($letters)) then $letters[$pos + 1] else ()
    return
        if (empty($prev) and empty($next)) then ()
        else
            <nav aria-label="Pagination" class="usa-pagination">
                <ul class="usa-pagination__list">
                {
                    if (exists($prev)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}/departmenthistory/people/by-name/{$prev}" class="usa-pagination__link usa-pagination__previous-page">
                                <pb-i18n key="odd.previous">Previous</pb-i18n> ({upper-case($prev)})
                            </a>
                        </li>
                    else (),
                    if (exists($next)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}/departmenthistory/people/by-name/{$next}" class="usa-pagination__link usa-pagination__next-page">
                                <pb-i18n key="odd.next">Next</pb-i18n> ({upper-case($next)})
                            </a>
                        </li>
                    else ()
                }
                </ul>
            </nav>
};

declare function dh:people-by-name-breadcrumb($context as map(*), $letter as xs:string?) as element(li)+ {
    let $trail := (
        map { "label": "People", "href": "/departmenthistory/people" },
        map { "label": "By Name", "href": "/departmenthistory/people/by-name" }
    )
    return
        if (empty($letter)) then
            dh:breadcrumb($context, $trail)
        else
            dh:breadcrumb($context, ($trail, map { "label": "Starting with " || upper-case($letter) }))
};
