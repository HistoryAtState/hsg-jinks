xquery version "3.1";

module namespace dh="https://history.state.gov/ns/templates/departmenthistory";

import module namespace page="http://teipublisher.com/ns/templates/page" at "page.xqm";
import module namespace pages="http://www.tei-c.org/tei-simple/pages" at "../lib/pages.xql";
import module namespace nav="http://www.tei-c.org/tei-simple/navigation" at "../navigation.xql";

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
 : Walks front/body/back, not body alone: buildings has front matter
 : (intro, foreword -- both carry a real @xml:id, contrary to this
 : function's first version, which assumed the old app's hardcoded "intro"
 : section-id meant the division had none) and back matter (a numbered
 : section continuing body's own sequence). Found live, the hard way: a
 : Cypress acceptance spec (#1149) clicking through the TOC never reached
 : "intro" because the traversal stopped at body, even though
 : /buildings/intro itself resolved fine (dh:monograph-division searches the
 : whole document, not body-scoped) -- the section existed and rendered, but
 : nothing linked to it. short-history has no front/back (confirmed:
 : grepping its source for those elements finds none), so this is a no-op
 : widening for that document.
 :
 : An un-id'd division (short-history's lead-in subchapters) is skipped
 : rather than special-cased: it has no id to link to, and its content still
 : reaches the reader because it is nested inside its addressable ancestor's
 : div, which page:transform renders in full.
 :)
declare function dh:monograph-divisions($doc as document-node()) as element(tei:div)* {
    $doc//(tei:front | tei:body | tei:back)//tei:div[@xml:id]
};

(:~
 : Table of contents: top-level divisions as items, their own id-bearing
 : child divisions nested beneath (any depth, though in practice only
 : short-history's chapter > subchapter goes two levels -- buildings is
 : flat). Reused as both the TOC page's main content (#1134) and the section
 : page's left sidebar (#1135, marks $current) -- one traversal, two
 : placements, same reasoning as hsg:volume-toc. Walks front/body/back's
 : own top-level divisions, same reasoning as dh:monograph-divisions above.
 :)
declare function dh:monograph-toc($context as map(*), $doc as document-node(), $route as xs:string, $current as xs:string?) as element(ul) {
    dh:monograph-toc-level($context, $doc/tei:TEI/tei:text/(tei:front | tei:body | tei:back)/tei:div, $route, $current, "usa-sidenav")
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
 : and head/p/graphic/hi already fall through to teipublisher.odd (or this
 : app's own hsg-jinks.odd overrides) with $division passed through
 : unmodified.
 :
 : $division is passed to page:transform as-is, still attached to its
 : source document -- an earlier version reconstructed a detached copy
 : (stripping the division's own <head> via a computed element
 : constructor) to solve the heading-level problem below, which silently
 : broke page:transform for the *entire* subtree: teipublisher's rendering
 : depends on base-uri()/document context that a freestanding in-memory
 : fragment doesn't have, so every section page rendered an empty content
 : div (found via a PR review comparing against the reference site, not by
 : any test -- the existing Cypress spec only asserted the <h1> was
 : present, which the old version still produced).
 :
 : Explicit <h1> from the division's own <head> text, WITHOUT stripping
 : that <head> from what's handed to page:transform -- the ODD still
 : renders it too, as part of the division's normal content (confirmed:
 : customizing the "head" elementSpec itself, scoped to the division's own
 : top-level head via a "sectionId" parameter, compiles and evaluates
 : correctly in isolation but never actually fires live -- teipublisher's
 : "section"/"block" behaviour implementations for div appear to extract
 : and render a div's own immediate head directly, without re-dispatching
 : it back through the elementSpec model-matching machinery, so an
 : elementSpec-level override can't reach it). The ODD's own rendering of
 : that same head is hidden via CSS instead (resources/css/hsg-theme.css,
 : ".tei-div > :first-child.tei-head"), scoped to only the division's own
 : *first* child -- nested subchapter heads (seen when a chapter's page
 : renders its subchapters' content inline) are never a div's first child
 : at the top level and remain visible, at whatever level the ODD assigns
 : them, which is correct there.
 :
 : Buildings' 357 footnotes (place="foot", forced in hsg-jinks.odd's own
 : "note" elementSpec override since the source carries no @place at all)
 : render inline via tei-publisher-lib's own "note" behaviour: a small
 : in-text marker, a <dl class="footnote"> with the full text right where
 : the note occurred, and a <pb-popover> with its own independent copy for
 : hover/click. A first attempt just hid the <dl> with CSS (display: none)
 : -- functional (the popover still works), but not what the reference
 : site does, which collects every note into a single <div class="footnotes">
 : after the main content, with a border-top divider (#1096, PR follow-up
 : screenshot comparison). pages:process-content (modules/lib/pages.xql,
 : used elsewhere in this app by page:content for the pb-view SSR path)
 : already implements exactly that consolidation step -- reused its own
 : two building blocks (pages:clean-footnotes to strip class="footnote"
 : elements out of the transformed body, nav:output-footnotes to re-emit
 : them collected, separating any pb-popover elements into their own
 : sibling <div class="popovers"> so hover/click still works alongside the
 : now-visible bottom list) rather than reimplementing the same walk.
 :)
declare function dh:monograph-section-content($context as map(*)) as element()+ {
    let $s := dh:current-section($context)
    let $division := $s?division
    let $transformed := page:transform($division, map { "mode": "monograph-section" })
    let $body := pages:clean-footnotes($transformed)
    let $footnotes :=
        for $fn in $transformed//*[@class = "footnote"]
        return element { node-name($fn) } { $fn/@*, pages:clean-footnotes($fn/node()) }
    return (
        <h1>{normalize-space($division/tei:head[1])}</h1>,
        $body,
        if ($footnotes) then nav:output-footnotes($footnotes) else ()
    )
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
 : Generic across every positions-principals record (#1139 reuses this for
 : every role, not just Secretary), not just secretary.xml.
 :)
declare %private function dh:principal-chain-end($principal as element(principal), $following as element(principal)*) as element(principal) {
    if (exists($following) and $following[1]/@treatAsConsecutive = 'yes') then
        dh:principal-chain-end($following[1], subsequence($following, 2))
    else
        $principal
};

(:~
 : Chronological officeholder list for one principal-position record, each
 : entry's year range computed via dh:principal-chain-end -- consecutive
 : terms merge into one entry, non-consecutive re-appointments (several
 : Secretaries served non-adjacent terms without the flag) each get their
 : own. No end date (still serving) renders as "-present". Shared by #1136
 : (secretary.xml specifically) and #1139 (every principal-position role).
 :)
declare function dh:principal-position-officeholders($context as map(*), $position as element(principal-position)) as element(ol) {
    let $principals := $position/principals/principal
    return
        <ol class="usa-prose">
        {
            for $p at $pos in $principals
            where not($p/@treatAsConsecutive = 'yes')
            let $following := subsequence($principals, $pos + 1)
            let $chain-end := dh:principal-chain-end($p, $following)
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

declare function dh:secretaries($context as map(*)) as element(ol) {
    dh:principal-position-officeholders($context, doc($dh:POCOM_COL || "/positions-principals/secretary.xml")/principal-position)
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
 : #1140's gsh join, closing the placeholder #1141 originally left here: the
 : countries-old collection (confirmed reachable directly, no need to import
 : the foreign gsh.xqm module for a plain id-to-label lookup) resolves a
 : territory id to its display name. Falls back to a bare title-case of the
 : id itself (still used directly by nothing now, but kept as insurance
 : against a territory id with no countries-old entry -- verified there
 : isn't one today: missions-countries' 199 territory-ids and
 : countries-old's 199 non-suppressed ids are exactly the same set, see
 : dh:chiefs-by-country-list).
 :)
declare variable $dh:GSH_COUNTRIES_COL := "/db/apps/gsh/data/countries-old";

declare function dh:country-label($territoryId as xs:string) as xs:string {
    let $label := normalize-space(collection($dh:GSH_COUNTRIES_COL)/country[id = $territoryId]/label)
    return if ($label != '') then $label else dh:territory-label($territoryId)
};

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
            "title": normalize-space($role-title) || " to " || dh:country-label($mission/territory-id),
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
    dh:person-service-record($personId, ())
};

(:~
 : $highlightYear marks whichever role(s) were active in that year (#1138's
 : by-year listing) with a semantic class -- the ticket's own rework note,
 : replacing hsg-shell's bold-inline-style highlighting. () for #1137's
 : by-name listing and #1141's person page, which don't highlight anything;
 : the 1-arg overload above is their entry point, so neither call site
 : changed when this parameter was added.
 :)
declare function dh:person-service-record($personId as xs:string, $highlightYear as xs:integer?) as element(ul) {
    <ul class="usa-collection">
    {
        for $role in dh:person-roles($personId)
        let $start-year := if (normalize-space($role?start) != '') then substring($role?start, 1, 4) else '?'
        let $end-year := if (normalize-space($role?end) != '') then substring($role?end, 1, 4) else 'present'
        let $is-current :=
            exists($highlightYear)
            and $start-year castable as xs:integer and xs:integer($start-year) <= $highlightYear
            and ($end-year = 'present' or (xs:integer($end-year) >= $highlightYear))
        return
            <li class="usa-collection__item{if ($is-current) then ' usa-collection__item--current' else ()}">
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
    dh:people-list($context, $people, ())
};

declare function dh:people-list($context as map(*), $people as element(person)*, $highlightYear as xs:integer?) as element(ul) {
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
                    {dh:person-service-record($person/id/string(), $highlightYear)}
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

(:~
 : #1138. Range fixed at 1778-present per the ticket's own stated range,
 : rather than min()/max() over every date in POCOM: the ticket notes this
 : computation "needs range indexes on the pocom collection to perform" --
 : indexes this app doesn't own (pocom is a foreign collection, its
 : collection.xconf isn't this app's to change) -- and 1778 is already the
 : documented start of the record. Cheaper and no less correct.
 :)
declare variable $dh:PEOPLE_BY_YEAR_MIN := 1778;

declare function dh:people-by-year-max() as xs:integer {
    year-from-date(current-date())
};

(:~
 : Whether $role (a <principal> or <chief>) was active during $year: started
 : by that year and either still ongoing (no end date) or ended no earlier
 : than that year.
 :)
declare %private function dh:role-active-in-year($role as element(), $year as xs:integer) as xs:boolean {
    let $start := normalize-space($role/started/date)
    let $end := normalize-space($role/ended/date)
    return
        $start != '' and xs:integer(substring($start, 1, 4)) <= $year
        and ($end = '' or xs:integer(substring($end, 1, 4)) >= $year)
};

(:~
 : Every person holding a role -- any of the three POCOM position families
 : -- active during $year. Three full collection scans per request (no
 : index to narrow by date range, see dh:PEOPLE_BY_YEAR_MIN); acceptable for
 : now at POCOM's size, revisit if this page's latency becomes a problem.
 :)
declare function dh:people-active-in-year($year as xs:integer) as element(person)* {
    let $personIds := distinct-values((
        for $position in collection($dh:POCOM_COL || "/positions-principals")/principal-position
        for $principal in $position/principals/principal
        where dh:role-active-in-year($principal, $year)
        return $principal/person-id,

        for $mission in collection($dh:POCOM_COL || "/missions-countries")/country-mission
        for $chief in $mission/chiefs/chief
        where dh:role-active-in-year($chief, $year)
        return $chief/person-id,

        for $org in collection($dh:POCOM_COL || "/missions-orgs")/org-mission
        for $chief in $org/chiefs/chief
        where dh:role-active-in-year($chief, $year)
        return $chief/person-id
    ))
    for $id in $personIds
    let $person := dh:person-doc($id)
    where exists($person)
    order by $person/persName/surname, $person/persName/forename
    return $person
};

(:~
 : Year links for the by-year index, grouped by decade (#1138's "decade-
 : grouped year links"). One <section> per decade rather than hsg-shell's
 : 3-column split, a presentational detail skipped for this pass.
 :)
declare function dh:people-by-year-nav($context as map(*)) as element(div) {
    <div class="people-by-year-nav">
    {
        for $year in $dh:PEOPLE_BY_YEAR_MIN to dh:people-by-year-max()
        let $decade := $year idiv 10 * 10
        group by $decade
        order by $decade
        return
            <section>
                <h2>{$decade}s</h2>
                <ul class="usa-list usa-list--unstyled">
                {
                    for $y in $year
                    order by $y
                    return
                        <li><a href="{$context?context-path}/departmenthistory/people/by-year/{$y}">{$y}</a></li>
                }
                </ul>
            </section>
    }
    </div>
};

declare function dh:people-by-year-prev-next($context as map(*), $year as xs:integer) as element(nav)? {
    let $prev := if ($year > $dh:PEOPLE_BY_YEAR_MIN) then $year - 1 else ()
    let $next := if ($year < dh:people-by-year-max()) then $year + 1 else ()
    return
        if (empty($prev) and empty($next)) then ()
        else
            <nav aria-label="Pagination" class="usa-pagination">
                <ul class="usa-pagination__list">
                {
                    if (exists($prev)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}/departmenthistory/people/by-year/{$prev}" class="usa-pagination__link usa-pagination__previous-page">
                                <pb-i18n key="odd.previous">Previous</pb-i18n> ({$prev})
                            </a>
                        </li>
                    else (),
                    if (exists($next)) then
                        <li class="usa-pagination__item usa-pagination__arrow">
                            <a href="{$context?context-path}/departmenthistory/people/by-year/{$next}" class="usa-pagination__link usa-pagination__next-page">
                                <pb-i18n key="odd.next">Next</pb-i18n> ({$next})
                            </a>
                        </li>
                    else ()
                }
                </ul>
            </nav>
};

declare function dh:people-by-year-breadcrumb($context as map(*), $year as xs:integer?) as element(li)+ {
    let $trail := (
        map { "label": "People", "href": "/departmenthistory/people" },
        map { "label": "By Year", "href": "/departmenthistory/people/by-year" }
    )
    return
        if (empty($year)) then
            dh:breadcrumb($context, $trail)
        else
            dh:breadcrumb($context, ($trail, map { "label": xs:string($year) }))
};

(:~
 : #1139. Positions grouped by the role-category code table, in the code
 : table's own order (Secretaries, Assistant Secretaries, Deputy
 : Secretaries, Under Secretaries, Ambassadors at Large, ... Discontinued);
 : "country" and "international-organization" categories excluded per the
 : ticket -- those are #1140's chiefs-of-mission roles, confirmed by
 : checking role-category-codes.xml directly (11 categories total, these
 : two are the only ones missions-countries/missions-orgs data uses).
 :)
declare function dh:principal-officers-index($context as map(*)) as element(div) {
    let $categories := doc($dh:POCOM_COL || "/code-tables/role-category-codes.xml")//item[not(value = ('country', 'international-organization'))]
    return
        <div class="principal-officers-index">
        {
            for $cat in $categories
            let $positions :=
                for $pp in collection($dh:POCOM_COL || "/positions-principals")/principal-position[category = $cat/value]
                order by $pp/names/plural
                return $pp
            where exists($positions)
            return
                <section>
                    <h2>{normalize-space($cat/label)}</h2>
                    <ul class="usa-list">
                    {
                        for $pp in $positions
                        return
                            <li>
                                <a href="{$context?context-path}/departmenthistory/people/principalofficers/{$pp/id}">{normalize-space($pp/names/plural)}</a>
                            </li>
                    }
                    </ul>
                </section>
        }
        </div>
};

declare function dh:principal-position-doc($roleId as xs:string) as element(principal-position)? {
    let $path := $dh:POCOM_COL || "/positions-principals/" || $roleId || ".xml"
    return if (doc-available($path)) then doc($path)/principal-position else ()
};

(:~
 : A record's <description> is quasi-rich-text (div/p/hi only, confirmed by
 : scanning every positions-principals description's element vocabulary) --
 : not TEI, so no ODD applies, but structured enough to walk directly rather
 : than treat as opaque. hi -> em is the only element with no direct HTML
 : equivalent; div/p pass through unchanged.
 :)
declare function dh:render-record-richtext($nodes as node()*) as node()* {
    for $n in $nodes
    return
        typeswitch($n)
            case element(div) return <div>{dh:render-record-richtext($n/node())}</div>
            case element(p) return <p>{dh:render-record-richtext($n/node())}</p>
            case element(hi) return <em>{dh:render-record-richtext($n/node())}</em>
            case text() return $n
            default return dh:render-record-richtext($n/node())
};

declare function dh:principal-officers-role-content($context as map(*)) as element()+ {
    let $roleId := $context?request?parameters?roleId
    let $position := dh:principal-position-doc($roleId)
    return (
        <h1>{normalize-space($position/names/plural)}</h1>,
        dh:render-record-richtext($position/description/div),
        dh:principal-position-officeholders($context, $position)
    )
};

declare function dh:principal-officers-breadcrumb($context as map(*)) as element(li)+ {
    let $roleId := $context?request?parameters?roleId
    let $trail := (map { "label": "People", "href": "/departmenthistory/people" }, map { "label": "Principal Officers", "href": "/departmenthistory/people/principalofficers" })
    return
        if (empty($roleId)) then
            dh:breadcrumb($context, $trail)
        else
            dh:breadcrumb($context, ($trail, map { "label": normalize-space(dh:principal-position-doc($roleId)/names/plural) }))
};

(:~
 : #1140. By-country index driven directly by missions-countries' own
 : territory-ids, not by porting hsg-shell's countries-old ISO2 suppression
 : list (aw/bm/bt/ky/xa/cw/hk/kp/kr/xj/qr/tw/xd/us/an/ps) -- verified live
 : that the two approaches produce the exact same 199-country set (a set
 : comparison both ways came back empty), so driving from the collection
 : that actually has mission data is equivalent and doesn't require carrying
 : forward an unexplained magic list. Two-column split by letter (not by
 : item count), same "kludgy, reference-parity" technique as feat/1095's
 : countries-all.html.
 :)
declare function dh:chiefs-by-country-list($context as map(*)) as element(div) {
    let $countries :=
        for $mission in collection($dh:POCOM_COL || "/missions-countries")/country-mission
        let $label := dh:country-label($mission/territory-id)
        order by $label
        return map { "id": $mission/territory-id/string(), "label": $label }
    let $letters := distinct-values($countries ! upper-case(substring(?label, 1, 1)))
    let $sorted-letters := for $l in $letters order by $l return $l
    let $half := ceiling(count($sorted-letters) div 2)
    return
        <div class="grid-row grid-gap">
        {
            for $col in (1, 2)
            let $column-letters := if ($col = 1) then subsequence($sorted-letters, 1, $half) else subsequence($sorted-letters, $half + 1)
            return
                <div class="tablet:grid-col-6">
                {
                    for $letter in $column-letters
                    return
                        <div>
                            <h3>{$letter}</h3>
                            <ul class="usa-list usa-list--unstyled">
                            {
                                for $country in $countries[upper-case(substring(?label, 1, 1)) = $letter]
                                return
                                    <li><a href="{$context?context-path}/departmenthistory/people/chiefsofmission/{$country?id}">{$country?label}</a></li>
                            }
                            </ul>
                        </div>
                }
                </div>
        }
        </div>
};

declare function dh:chiefs-by-organization-list($context as map(*)) as element(ul) {
    <ul class="usa-list">
    {
        for $org in collection($dh:POCOM_COL || "/missions-orgs")/org-mission
        order by $org/names/plural
        return
            <li><a href="{$context?context-path}/departmenthistory/people/chiefsofmission/{$org/id}">{normalize-space($org/names/plural)}</a></li>
    }
    </ul>
};

declare function dh:chiefs-country-doc($id as xs:string) as element(country-mission)? {
    let $path := $dh:POCOM_COL || "/missions-countries/" || $id || ".xml"
    return if (doc-available($path)) then doc($path)/country-mission else ()
};

declare function dh:chiefs-org-doc($id as xs:string) as element(org-mission)? {
    let $path := $dh:POCOM_COL || "/missions-orgs/" || $id || ".xml"
    return if (doc-available($path)) then doc($path)/org-mission else ()
};

(:~
 : A country-mission chief's role-title-id points into roles-country-chiefs
 : (e.g. "ambassador", "minister-resident"); an org-mission chief's
 : role-title-id is self-referential -- it's the org-mission's own id (e.g.
 : "representative-to-un" for a UN chief), confirmed live: the first lookup
 : alone left every org-mission chief's position label blank. Checking both
 : sources makes this one function usable from dh:mission-chiefs-list for
 : either mission type.
 :)
declare function dh:chief-role-label($roleTitleId as xs:string) as xs:string {
    let $country-role := normalize-space(collection($dh:POCOM_COL || "/roles-country-chiefs")/role[id = $roleTitleId]/names/singular)
    return
        if ($country-role != '') then $country-role
        else normalize-space(collection($dh:POCOM_COL || "/missions-orgs")/org-mission[id = $roleTitleId]/names/singular)
};

(:~
 : Chiefs list for a country-mission or org-mission -- both use the same
 : <chiefs><chief|mission-note>*</chiefs> shape (confirmed for missions-orgs
 : too, not just missions-countries). Document order is preserved
 : deliberately, per the ticket's explicit warning: it is curation, not an
 : accidental omission of a sort. A mission-note interleaved between chiefs
 : renders as a slim info alert in place, not sorted to the end.
 :
 : $currentTerritoryId is empty for an org-mission (no territory to
 : annotate against); for a country-mission, a chief's own
 : contemporary-territory-id is only shown when it differs from the
 : mission's, flagging a historical-territory rename.
 :)
declare function dh:mission-chiefs-list($context as map(*), $chiefsAndNotes as element()*, $currentTerritoryId as xs:string?) as element(ul) {
    <ul class="usa-collection">
    {
        for $entry in $chiefsAndNotes
        return
            if ($entry/self::chief) then
                let $chief := $entry
                let $person := dh:person-doc($chief/person-id)
                let $position-label := dh:chief-role-label($chief/role-title-id)
                let $start-date := ($chief/started/date, $chief/arrived/date, $chief/appointed/date)[normalize-space(.) != ''][1]
                let $end-date := normalize-space($chief/ended/date)
                let $contemporary-territory := normalize-space($chief/contemporary-territory-id)
                let $territory-note :=
                    if ($contemporary-territory != '' and $contemporary-territory != $currentTerritoryId) then
                        ', ' || dh:country-label($contemporary-territory)
                    else ()
                return
                    <li class="usa-collection__item">
                        <div class="usa-collection__body">
                            <h3 class="usa-collection__heading">
                                <a href="{$context?context-path}/departmenthistory/people/{$chief/person-id}">{dh:person-name-birth-death($person)}</a>
                            </h3>
                            <p class="usa-collection__meta">
                                {$position-label}{$territory-note}, {substring(normalize-space($start-date), 1, 4)}&#8211;{if ($end-date != '') then substring($end-date, 1, 4) else 'present'}
                            </p>
                        </div>
                    </li>
            else
                <li class="usa-collection__item">
                    <div class="usa-alert usa-alert--info usa-alert--slim">
                        <div class="usa-alert__body">
                            <p class="usa-alert__text">{normalize-space($entry/text)}</p>
                        </div>
                    </div>
                </li>
    }
    </ul>
};

(:~
 : "Other Nominees" (country-mission) / "Other Appointees" (org-mission) --
 : same shape, different element name, hence the $label parameter rather
 : than two near-identical functions.
 :)
declare function dh:mission-other-list($context as map(*), $others as element(chief)*, $label as xs:string) as element(div) {
    <div>
        <h2>{$label}</h2>
        {
            if (empty($others)) then
                <p><em>None</em></p>
            else
                <ul class="usa-collection">
                {
                    for $chief in $others
                    let $person := dh:person-doc($chief/person-id)
                    let $position-label := dh:chief-role-label($chief/role-title-id)
                    let $note := normalize-space($chief/note)
                    return
                        <li class="usa-collection__item">
                            <div class="usa-collection__body">
                                <h3 class="usa-collection__heading">
                                    <a href="{$context?context-path}/departmenthistory/people/{$chief/person-id}">{dh:person-name-birth-death($person)}</a>
                                </h3>
                                <p class="usa-collection__meta">{$position-label}{if ($note != '') then ': ' || $note else ()}</p>
                            </div>
                        </li>
                }
                </ul>
        }
    </div>
};

(:~
 : The polymorphic {roleOrCountryId} page (#1140's ticket text: "org-mission,
 : principal-position or country"). org-mission and country are this
 : ticket's own two real targets; a positions-principals id falling through
 : to here is an old-URL-compatibility case (verified: hsg-shell's
 : chiefs-by-role-or-country-id resolves any collection(pocom)//id match,
 : which includes principal-position's own <id>) -- rather than duplicate
 : #1139's rendering, dhapi:chiefs-listing 302s that case to the canonical
 : /principalofficers/{roleId} URL.
 :)
declare function dh:chiefs-listing-content($context as map(*)) as element()+ {
    let $id := $context?request?parameters?roleOrCountryId
    let $org := dh:chiefs-org-doc($id)
    return
        if (exists($org)) then (
            <h1>{normalize-space($org/names/plural)}</h1>,
            dh:render-record-richtext($org/description/div),
            dh:mission-chiefs-list($context, $org/chiefs/*, ()),
            dh:mission-other-list($context, $org/other-appointees/chief, "Other Appointees")
        )
        else
            let $mission := dh:chiefs-country-doc($id)
            return (
                <h1>{dh:country-label($mission/territory-id)}</h1>,
                dh:mission-chiefs-list($context, $mission/chiefs/*, $mission/territory-id/string()),
                dh:mission-other-list($context, $mission/other-nominees/chief, "Other Nominees")
            )
};

declare function dh:chiefs-listing-title($context as map(*)) as xs:string {
    let $id := $context?request?parameters?roleOrCountryId
    let $org := dh:chiefs-org-doc($id)
    return
        if (exists($org)) then normalize-space($org/names/plural)
        else dh:country-label(dh:chiefs-country-doc($id)/territory-id)
};

(:~
 : Shared prefix for all three new #1140 pages: People > Chiefs of Mission
 : (linking back to #1132's existing hub page at /chiefsofmission).
 :)
declare %private function dh:chiefs-trail() as map(*)+ {
    (map { "label": "People", "href": "/departmenthistory/people" }, map { "label": "Chiefs of Mission", "href": "/departmenthistory/people/chiefsofmission" })
};

(:~
 : Shared by both by-country and by-organization (#1096 optimization pass,
 : one template for both): $kind is "country" or "organization", matching
 : the "kind" request parameter dhapi:chiefs-by-kind synthesizes.
 :)
declare function dh:chiefs-by-kind-breadcrumb($context as map(*), $kind as xs:string) as element(li)+ {
    dh:breadcrumb($context, (dh:chiefs-trail(), map { "label": "By " || (if ($kind = 'country') then "Country" else "Organization") }))
};

declare function dh:chiefs-listing-breadcrumb($context as map(*)) as element(li)+ {
    dh:breadcrumb($context, (dh:chiefs-trail(), map { "label": dh:chiefs-listing-title($context) }))
};

(:~
 : #1142/#1143. Travels and visits are the epic's second, smaller no-ODD
 : record family (21 president-travel files + 34 secretary-travel files +
 : 16 decade-bucketed visit files) -- same "no-ODD" architecture as POCOM,
 : reusing dh:breadcrumb and (for the secretary route's old-id 302)
 : dh:person-canonical-id-for-old-id, but its own, simpler collections:
 : travel person-ids share POCOM's people namespace (confirmed:
 : secretary-travels' filenames match POCOM person-ids exactly, e.g.
 : kerry-john-forbes) but the trip/visit data itself lives outside POCOM.
 :)
declare variable $dh:TRAVELS_COL := "/db/apps/travels";
declare variable $dh:VISITS_COL := "/db/apps/visits/data";

declare function dh:travels-collection($role as xs:string) as xs:string {
    $dh:TRAVELS_COL || "/" || $role || "-travels"
};

declare function dh:travels-president-doc() as document-node() {
    doc($dh:TRAVELS_COL || "/presidents/presidents.xml")
};

(:~
 : Office-holders (of the given role) who actually traveled, in term order,
 : each linking to their own listing page. President term years come from
 : the presidents.xml code table; Secretary term years reuse
 : dh:principal-chain-end against secretary.xml (#1136's own merging logic
 : applied here too, for the same reason: a re-appointment marked
 : @treatAsConsecutive should not restart the year range).
 :)
declare function dh:travels-president-office-holders($context as map(*)) as element(ul) {
    let $traveledIds := distinct-values(collection(dh:travels-collection('president'))//trip/@who)
    return
        <ul class="usa-collection">
        {
            for $president in dh:travels-president-doc()/presidents/president[id = $traveledIds]
            let $start-year := year-from-date(xs:date($president/took-office-date))
            let $end-date := normalize-space($president/left-office-date)
            order by $start-year
            return
                <li class="usa-collection__item">
                    <div class="usa-collection__body">
                        <h3 class="usa-collection__heading">
                            <a href="{$context?context-path}/departmenthistory/travels/president/{$president/id}">{normalize-space($president/name)}</a>
                        </h3>
                        <p class="usa-collection__meta">{$start-year}&#8211;{if ($end-date != '') then year-from-date(xs:date($end-date)) else 'present'}</p>
                    </div>
                </li>
        }
        </ul>
};

declare function dh:travels-secretary-office-holders($context as map(*)) as element(ul) {
    let $traveledIds := for $r in xmldb:get-child-resources(dh:travels-collection('secretary')) return replace($r, '\.xml$', '')
    let $secretaryDoc := doc($dh:POCOM_COL || "/positions-principals/secretary.xml")
    return
        <ul class="usa-collection">
        {
            for $personId in $traveledIds
            let $principal := $secretaryDoc//principals/principal[person-id = $personId][1]
            let $person := dh:person-doc($personId)
            let $chain-end := if (exists($principal)) then dh:principal-chain-end($principal, $principal/following-sibling::principal) else ()
            let $start-year := if (exists($principal)) then substring($principal/started/date, 1, 4) else '?'
            let $end-date := if (exists($chain-end)) then normalize-space($chain-end/ended/date) else ''
            order by $start-year
            return
                <li class="usa-collection__item">
                    <div class="usa-collection__body">
                        <h3 class="usa-collection__heading">
                            <a href="{$context?context-path}/departmenthistory/travels/secretary/{$personId}">{dh:person-name($person)}</a>
                        </h3>
                        <p class="usa-collection__meta">{$start-year}&#8211;{if ($end-date != '') then substring($end-date, 1, 4) else 'present'}</p>
                    </div>
                </li>
        }
        </ul>
};

declare function dh:travels-destinations($context as map(*), $role as xs:string) as element(ul) {
    let $countries := collection(dh:travels-collection($role))//country
    let $ids := distinct-values($countries/@id)
    return
        <ul class="usa-collection">
        {
            for $id in $ids
            let $label := normalize-space(($countries[@id = $id])[1])
            order by $label
            return
                <li class="usa-collection__item"><a href="{$context?context-path}/departmenthistory/travels/{$role}/{$id}">{$label}</a></li>
        }
        </ul>
};

declare function dh:travels-index-breadcrumb($context as map(*), $role as xs:string) as element(li)+ {
    dh:breadcrumb($context, (
        map { "label": "Travels", "href": "/departmenthistory/travels" },
        map { "label": if ($role = 'president') then "Travels of the President" else "Travels of the Secretary of State" }
    ))
};

(:~
 : #1143. Shared by travels and visits tables (#1144/#1145 reuse this
 : directly): same-day / same-month / same-year / cross-year date-range
 : formatting, ported from hsg-shell's identical logic in both
 : travels-html.xqm's travels-to-table and visits-html.xqm's visits-table --
 : one function instead of two copies.
 :)
declare function dh:humanize-date-range($startDate as xs:string, $endDate as xs:string) as xs:string {
    if (not($startDate castable as xs:date)) then
        'date error'
    else
        let $start := xs:date($startDate)
        return
            if ($startDate = $endDate or not($endDate castable as xs:date)) then
                format-date($start, '[MNn] [D], [Y0001]', 'en', (), 'US')
            else
                let $end := xs:date($endDate)
                return
                    if (year-from-date($start) = year-from-date($end) and month-from-date($start) = month-from-date($end)) then
                        format-date($start, '[MNn] [D]', 'en', (), 'US') || '&#8211;' || format-date($end, '[D], [Y0001]', 'en', (), 'US')
                    else if (year-from-date($start) = year-from-date($end)) then
                        format-date($start, '[MNn] [D]', 'en', (), 'US') || '&#8211;' || format-date($end, '[MNn] [D], [Y0001]', 'en', (), 'US')
                    else
                        format-date($start, '[MNn] [D], [Y0001]', 'en', (), 'US') || '&#8211;' || format-date($end, '[MNn] [D], [Y0001]', 'en', (), 'US')
};

(:~
 : Whether $id resolves as a person (a president in presidents.xml, or a
 : secretary with their own secretary-travels file) rather than a
 : destination-country id -- the polymorphic key #1143's route resolves in
 : this order, person first.
 :)
declare function dh:travels-is-person($role as xs:string, $id as xs:string) as xs:boolean {
    if ($role = 'president') then
        exists(dh:travels-president-doc()/presidents/president[id = $id])
    else
        doc-available(dh:travels-collection('secretary') || "/" || $id || ".xml")
};

declare function dh:travels-trips-by-person($role as xs:string, $id as xs:string) as element(trip)* {
    for $trip in collection(dh:travels-collection($role))//trip[@who = $id]
    order by $trip/start-date
    return $trip
};

declare function dh:travels-trips-by-country($role as xs:string, $countryId as xs:string) as element(trip)* {
    for $trip in collection(dh:travels-collection($role))//trip[country/@id = $countryId]
    order by $trip/start-date
    return $trip
};

(:~
 : Person view suppresses the Name column (redundant with the page title);
 : country view suppresses Country. Matches hsg-shell's travels-to-table
 : $suppress convention exactly -- by-person passed "name", by-country
 : passed "country".
 :)
declare function dh:travels-table($trips as element(trip)*, $suppress as xs:string) as element(table) {
    <table class="usa-table usa-table--striped usa-table--stacked">
        <thead>
            <tr>
                {if ($suppress = 'name') then () else <th scope="col">Name</th>}
                {if ($suppress = 'country') then () else <th scope="col">Country</th>}
                <th scope="col">Locale</th>
                <th scope="col">Remarks</th>
                <th scope="col">Date</th>
            </tr>
        </thead>
        <tbody>
        {
            for $trip in $trips
            return
                <tr>
                    {if ($suppress = 'name') then () else <td data-label="Name">{if (normalize-space($trip/name) != '') then normalize-space($trip/name) else dh:person-name(dh:person-doc($trip/@who))}</td>}
                    {if ($suppress = 'country') then () else <td data-label="Country">{normalize-space($trip/country)}</td>}
                    <td data-label="Locale">{normalize-space($trip/locale)}</td>
                    <td data-label="Remarks">{normalize-space($trip/remarks)}</td>
                    <td data-label="Date">{dh:humanize-date-range(normalize-space($trip/start-date), normalize-space($trip/end-date))}</td>
                </tr>
        }
        </tbody>
    </table>
};

declare function dh:travels-listing-title($role as xs:string, $id as xs:string) as xs:string {
    if (dh:travels-is-person($role, $id)) then
        if ($role = 'president') then
            normalize-space(dh:travels-president-doc()/presidents/president[id = $id]/name)
        else
            dh:person-name(dh:person-doc($id))
    else
        normalize-space(dh:travels-trips-by-country($role, $id)[last()]/country)
};

(:~
 : $role's own hiatus is only meaningful for president (#1142's ticket
 : text; the secretary hiatus notice is a static line on the index page,
 : not a per-listing one). Shown on every by-country listing plus the
 : current administration's own by-person listing, matching hsg-shell's
 : request:set-attribute("show-travels-hiatus-notice", ...) condition
 : (exists($current-country-name) or $person-or-country-id = current admin).
 :)
declare function dh:travels-show-president-hiatus($id as xs:string) as xs:boolean {
    not(dh:travels-is-person('president', $id)) or $id = 'trump-donald-j'
};

(:~
 : No <h1> + notice + table in one function, unlike most other dh:*-content
 : functions: the hiatus notice is a template partial ([% include %]), which
 : can only be pulled in from the template itself (see dh:person-has-bio /
 : #1141 for the same split), so the template checks
 : dh:travels-show-president-hiatus between calling dh:travels-listing-title
 : (for the <h1>) and dh:travels-listing-table (for the trips).
 :)
declare function dh:travels-listing-table($context as map(*), $role as xs:string) as element(table) {
    let $id := $context?request?parameters?personOrCountryId
    return
        if (dh:travels-is-person($role, $id)) then
            dh:travels-table(dh:travels-trips-by-person($role, $id), 'name')
        else
            dh:travels-table(dh:travels-trips-by-country($role, $id), 'country')
};

declare function dh:travels-listing-breadcrumb($context as map(*), $role as xs:string) as element(li)+ {
    let $id := $context?request?parameters?personOrCountryId
    return dh:breadcrumb($context, (
        map { "label": "Travels", "href": "/departmenthistory/travels" },
        map { "label": if ($role = 'president') then "Travels of the President" else "Travels of the Secretary of State", "href": "/departmenthistory/travels/" || $role },
        map { "label": dh:travels-listing-title($role, $id) }
    ))
};

(:~
 : #1144/#1145. Visits data is decade-bucketed (16 files, visits/data/1870.xml
 : .. 2020.xml, each covering ten years -- confirmed live: 1970.xml holds
 : dates from 1970 through 1979), unlike travels' one-file-per-person.
 : Reuses dh:humanize-date-range unchanged.
 :)
declare function dh:visits-decade-file($year as xs:integer) as xs:string {
    $dh:VISITS_COL || "/" || (($year idiv 10) * 10) || ".xml"
};

declare function dh:visits-is-year($key as xs:string) as xs:boolean {
    matches($key, '^\d{4}')
};

(:~
 : "Last updated" derived from the data (#1144's rework note -- hsg-shell
 : hand-edited this line): the latest last-modified-datetime across every
 : visit record. A handful of records have an empty last-modified-datetime
 : (confirmed live -- casting the raw sequence to xs:dateTime throws
 : FORG0001), filtered out rather than erroring the whole page.
 :)
declare function dh:visits-last-updated() as xs:string {
    let $latest := max(
        for $d in collection($dh:VISITS_COL)/visits/visit/last-modified-datetime
        where normalize-space($d) castable as xs:dateTime
        return xs:dateTime($d)
    )
    return format-dateTime($latest, '[MNn] [Y0001]', 'en', (), 'US')
};

declare function dh:visits-years($context as map(*)) as element(ul) {
    let $years := distinct-values(
        for $date in collection($dh:VISITS_COL)//(start-date | end-date)
        where normalize-space($date) castable as xs:date
        return year-from-date(xs:date($date))
    )
    return
        <ul class="usa-collection">
        {
            for $year in $years
            order by $year
            return
                <li class="usa-collection__item"><a href="{$context?context-path}/departmenthistory/visits/{$year}">{$year}</a></li>
        }
        </ul>
};

(:~
 : Distinct visitor-origin labels, each linking to its @id -- or, when a
 : record's <from> carries no @id (none in the current data, but the
 : ticket calls this case out explicitly), marked with a trailing "*"
 : instead of a link, matching hsg-shell's visits:countries exactly.
 :)
declare function dh:visits-countries($context as map(*)) as element(ul) {
    let $allFrom := collection($dh:VISITS_COL)/visits/visit/from
    let $labels := distinct-values($allFrom)
    return
        <ul class="usa-collection">
        {
            for $label in $labels
            let $id := normalize-space(($allFrom[. = $label])[1]/@id)
            order by $label
            return
                <li class="usa-collection__item">
                {
                    if ($id != '') then
                        <a href="{$context?context-path}/departmenthistory/visits/{$id}">{$label}</a>
                    else
                        ($label, ' *')
                }
                </li>
        }
        </ul>
};

declare function dh:visits-by-year($year as xs:integer) as element(visit)* {
    for $visit in doc(dh:visits-decade-file($year))/visits/visit[year-from-date(xs:date(start-date)) = $year]
    order by $visit/start-date
    return $visit
};

declare function dh:visits-by-country($countryId as xs:string) as element(visit)* {
    for $visit in collection($dh:VISITS_COL)/visits/visit[from/@id = $countryId]
    order by $visit/start-date
    return $visit
};

declare function dh:visits-table($visits as element(visit)*, $suppressFrom as xs:boolean) as element(table) {
    <table class="usa-table usa-table--striped usa-table--stacked">
        <thead>
            <tr>
                <th scope="col">Visitor</th>
                {if ($suppressFrom) then () else <th scope="col">From</th>}
                <th scope="col">Description</th>
                <th scope="col">Date</th>
            </tr>
        </thead>
        <tbody>
        {
            for $visit in $visits
            return
                <tr>
                    <td data-label="Visitor">{normalize-space($visit/visitor)}</td>
                    {if ($suppressFrom) then () else <td data-label="From">{normalize-space($visit/from)}</td>}
                    <td data-label="Description">{normalize-space($visit/description)}</td>
                    <td data-label="Date">{dh:humanize-date-range(normalize-space($visit/start-date), normalize-space($visit/end-date))}</td>
                </tr>
        }
        </tbody>
    </table>
};

declare function dh:visits-listing-title($key as xs:string) as xs:string {
    if (dh:visits-is-year($key)) then
        "Visits By Foreign Leaders in " || $key
    else
        "Visits By Foreign Leaders of " || normalize-space(dh:visits-by-country($key)[last()]/from)
};

declare function dh:visits-listing-table($key as xs:string) as element(table) {
    if (dh:visits-is-year($key)) then
        dh:visits-table(dh:visits-by-year(xs:integer($key)), false())
    else
        dh:visits-table(dh:visits-by-country($key), true())
};

declare function dh:visits-index-breadcrumb($context as map(*)) as element(li)+ {
    dh:breadcrumb($context, (map { "label": "Visits by Foreign Leaders" }))
};

declare function dh:visits-listing-breadcrumb($context as map(*)) as element(li)+ {
    let $key := $context?request?parameters?countryOrYear
    return dh:breadcrumb($context, (
        map { "label": "Visits by Foreign Leaders", "href": "/departmenthistory/visits" },
        map { "label": dh:visits-listing-title($key) }
    ))
};
