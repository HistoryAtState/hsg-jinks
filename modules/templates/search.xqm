xquery version "3.1";

(:~
 : Cross-collection full-text search (OP#1102): the Lucene query/facet
 : pipeline, sort, cache, pagination, and per-type result rendering ported
 : from hsg-shell's modules/search.xqm, adapted to this app's plain-XQuery
 : template-function style (no eXist html-templating %templates:* annotations
 : -- jinks templates call these directly as [[ srch:whatever($context) ]]).
 :
 : FRUS is queried from /db/apps/frus-data-jinks (this app's own, currently
 : one-volume, frozen data baseline -- see doc/epic-1102-search-plan.md §3),
 : NOT hsg-shell's full /db/apps/frus/volumes: hsg-jinks's own
 : historicaldocuments routes only ever render frus-data-jinks, so a FRUS hit
 : must point somewhere this app can actually serve. When the real multi-volume
 : data replaces the sample baseline (same repo, same frozen-baseline
 : mechanism), search picks it up automatically -- the collection path below
 : is a single named constant, not repeated per query site.
 :
 : Known, deliberate simplifications versus hsg-shell (documented rather than
 : silently dropped, matching this repo's established practice -- see
 : doc/epic-1096-departmenthistory-plan.md for the same pattern):
 :  - tei:div hit TITLES use the division's own head text only, not hsg-shell's
 :    richer "Section Heading (Document Heading)" built from $config:PUBLICATIONS
 :    -- that per-publication select-section/select-document map has no
 :    equivalent in hsg-jinks yet (each section owns its own narrow slice, see
 :    doc/epic-1102-search-plan.md §3's finding on hsg-url).
 :  - tei:div/tei:body hit HREFs trust the already-indexed hsg-url Lucene
 :    field directly (confirmed live to already target the current hsg-jinks
 :    URL scheme for every non-FRUS section -- see the coordination doc)
 :    instead of hsg-shell's per-publication html-href() call.
 :  - KWIC summaries are not first trimmed to N matches before summarizing
 :    (hsg-shell's search:trim-matches/milestone-chunk) -- a heavily-matched
 :    hit may show a slightly longer snippet.
 :  - hsg-shell's unused MAX_HITS_SHOWN cap/message, the hardcoded facet-count
 :    badge, and the frus DISPLAY entry's dead absolute-URL branch are not
 :    ported (dead code in the source, not a feature).
 :)
module namespace srch = "https://history.state.gov/ns/templates/search";

import module namespace kwic = "http://exist-db.org/xquery/kwic";
import module namespace cache = "http://exist-db.org/xquery/cache" at "java:org.exist.xquery.modules.cache.CacheModule";
import module namespace page = "http://teipublisher.com/ns/templates/page" at "page.xqm";
import module namespace fd = "http://history.state.gov/ns/site/hsg/frus-dates" at "../frus-dates.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

(:~ FRUS data collection this app actually renders -- see module doc above. :)
declare variable $srch:FRUS_COL as xs:string := "/db/apps/frus-data-jinks";

declare variable $srch:ft-query-options as map(*) := map {
    "default-operator": "and",
    "phrase-slop": 0,
    "leading-wildcard": "no",
    "filter-rewrite": "yes"
};

(:~ Lucene chars not exposed as search features -- escaped so they search
 : literally rather than altering the query or raising a parse error. The
 : documented operators (" + - ( ) * ? ~, AND/OR/NOT) are intentionally absent. :)
declare variable $srch:UNSUPPORTED-LUCENE-CHARS as xs:string := "[/\\!:\^\[\]{}]";

(:~ Maps a search-scope checkbox id to hsg-publication facet value(s). :)
declare variable $srch:SECTIONS as map(*) := map {
    "documents": "frus",
    "department": ("short-history", "people", "buildings", "views-from-the-embassy", "pocom", "visits", "travels"),
    "retired": ("milestones", "education"),
    "countries": ("countries-articles", "archives"),
    "conferences": "conferences",
    "frus-history": ("frus-history-articles", "frus-history-documents", "frus-history-monograph"),
    "about": ("hac", "faq")
};

(:~ The 7 landing-page / filter-sidebar section checkboxes. :)
declare function srch:sections() as map(*)* {
    (
        map { "id": "documents", "label": "Historical Documents" },
        map { "id": "department", "label": "Department History" },
        map { "id": "countries", "label": "Countries" },
        map { "id": "conferences", "label": "Conferences" },
        map { "id": "frus-history", "label": "History of the Foreign Relations Series" },
        map { "id": "about", "label": "About (FAQ, Advisory Committee Minutes)" },
        map { "id": "retired", "label": "Retired Resources (Milestones)" }
    )
};

(: ============== query construction ============== :)

declare %private function srch:escape-unsupported-characters($query as xs:string?) as xs:string? {
    if (exists($query)) then
        replace($query, "(" || $srch:UNSUPPORTED-LUCENE-CHARS || ")", "\\$1")
    else
        ()
};

(:~
 : Whether Lucene can parse the fulltext query this module would build from
 : the user's q (OP#1273): malformed syntax the escaping does not cover (an
 : unbalanced quote, a dangling boolean operator) used to be swallowed by the
 : catch around srch:query-sections into silent zero results; the route now
 : rejects it up front as HTTP 400. The probe runs the exact query string
 : srch:prepare-query builds against a single indexed node (the conferences
 : package is a required install and its content is frozen), so only the
 : parse is exercised; with the probe node absent the check passes and
 : behavior degrades to today's empty result, never a false rejection.
 :)
declare function srch:query-parses($query as xs:string?) as xs:boolean {
    if (empty($query) or normalize-space($query) = "") then
        true()
    else
        let $queryString := "hsg-fulltext:(" || srch:escape-unsupported-characters($query) || ")"
        let $probe := (collection("/db/apps/conferences")//tei:div)[1]
        return
            try {
                exists($probe[ft:query(., $queryString, map {})]) or true()
            } catch * {
                false()
            }
};

declare %private function srch:prepare-query($sections as xs:string*, $volumeIds as xs:string*,
        $query as xs:string?, $rangeStart as xs:dateTime?, $rangeEnd as xs:dateTime?) as map(*) {
    let $category := $sections[not(. = ("", "entire-site"))]
    let $publication :=
        for $section in $category
        return $srch:SECTIONS?($section)
    let $dateCapable := count($category) eq 1 and $category = "documents"
    let $fulltextQuery := if (exists($query)) then "hsg-fulltext:(" || srch:escape-unsupported-characters($query) || ") " else ()
    let $rangeStartStr := translate(string($rangeStart), ':-', '')
    let $rangeEndStr := translate(string($rangeEnd), ':-', '')
    let $dateQuery :=
        if (exists($rangeStart)) then
            "frus-search-date-min:[" || $rangeStartStr || " TO " || $rangeEndStr || "] AND frus-search-date-max:[" || $rangeStartStr || " TO " || $rangeEndStr || "]"
        else
            ()
    let $queryString := if (exists($fulltextQuery) or exists($dateQuery)) then string-join(($fulltextQuery, $dateQuery), " AND ") else ()
    let $facets := map:merge((
        if (exists($category)) then map { "hsg-category": $category } else (),
        if (exists($publication)) then map { "hsg-publication": $publication } else (),
        if ($dateCapable and exists($volumeIds)) then map { "frus-volume-id": $volumeIds } else ()
    ))
    return map {
        "fields": map { "fields": ("hsg-date-min", "hsg-fulltext", "hsg-url") },
        "facets": map { "facets": $facets },
        "query-string": $queryString
    }
};

declare %private function srch:query-sections($queryConfig as map(*)) as element()* {
    let $queryString := $queryConfig?query-string
    let $queryOptions := map:merge(($srch:ft-query-options, $queryConfig?fields, $queryConfig?facets))
    (: frus omits ?fields, same limitation-driven exception hsg-shell carried for large result sets :)
    let $frusQueryOptions := map:merge(($srch:ft-query-options, $queryConfig?facets))
    return (
        collection("/db/apps/other-publications")//tei:div[ft:query(., $queryString, $queryOptions)],
        collection("/db/apps/other-publications")//tei:body[ft:query(., $queryString, $queryOptions)],
        collection("/db/apps/conferences")//tei:div[ft:query(., $queryString, $queryOptions)],
        collection("/db/apps/hac")//tei:div[ft:query(., $queryString, $queryOptions)],
        collection($srch:FRUS_COL)//tei:div[ft:query(., $queryString, $frusQueryOptions)],
        collection("/db/apps/frus-history/articles")//tei:body[ft:query(., $queryString, $queryOptions)],
        collection("/db/apps/frus-history/documents")//tei:body[ft:query(., $queryString, $queryOptions)],
        collection("/db/apps/frus-history/monograph")//tei:div[ft:query(., $queryString, $queryOptions)],
        collection("/db/apps/rdcr")//tei:body[ft:query(., $queryString, $queryOptions)],
        collection("/db/apps/wwdai")//tei:body[ft:query(., $queryString, $queryOptions)],
        collection("/db/apps/pocom/people")//persName[ft:query(., $queryString, $queryOptions)],
        collection("/db/apps/travels")//trips[ft:query(., $queryString, $queryOptions)],
        collection("/db/apps/visits")//visit[ft:query(., $queryString, $queryOptions)],
        collection("/db/apps/milestones")//tei:div[ft:query(., $queryString, $queryOptions)]
    )
};

declare %private function srch:sort($hits as element()*, $sortBy as xs:string) as element()* {
    switch ($sortBy)
        case "date-asc" return
            for $hit in $hits
            order by ft:binary-field($hit, "hsg-date-min", "xs:dateTime") ascending empty greatest, ft:score($hit) descending
            return $hit
        case "date-desc" return
            for $hit in $hits
            order by ft:binary-field($hit, "hsg-date-min", "xs:dateTime") descending empty least, ft:score($hit) descending
            return $hit
        default return
            for $hit in $hits
            order by ft:score($hit) descending
            return $hit
};

(:~ US Eastern, hard-coded -- see doc/epic-1102-search-plan.md / frus-dates.xqm. :)
declare %private function srch:date-range($startDate as xs:string?, $endDate as xs:string?,
        $startTime as xs:string?, $endTime as xs:string?) as map(*) {
    let $timezone := xs:dayTimeDuration("-PT5H")
    let $rangeStart :=
        if ($startDate) then fd:normalize-low($startDate || (if ($startTime) then ("T" || $startTime) else ()), $timezone) else ()
    let $rangeEnd :=
        if ($endDate) then fd:normalize-high($endDate || (if ($endTime) then ("T" || $endTime) else ()), $timezone)
        else if ($startDate) then fd:normalize-high($startDate, $timezone)
        else ()
    return map { "start": $rangeStart, "end": $rangeEnd }
};

(: ============== cached hit computation ============== :)

declare %private function srch:read-params($context as map(*)) as map(*) {
    let $q := normalize-space(page:parameter($context, "q", ()))[. ne ""]
    let $within := request:get-parameter("within", ())
    let $volumeId := request:get-parameter("volume-id", ())
    let $startDate := page:parameter($context, "start-date", ())
    let $endDate := page:parameter($context, "end-date", ())
    let $startTime := page:parameter($context, "start-time", ())
    let $endTime := page:parameter($context, "end-time", ())
    let $sortByParam := page:parameter($context, "sort-by", ())
    let $orderBy := page:parameter($context, "order-by", ())
    let $start := xs:integer((page:parameter($context, "start", "1"), "1")[1])
    let $perPage := xs:integer((page:parameter($context, "per-page", "10"), "10")[1])
    let $sortBy :=
        if (not($q) and $sortByParam eq "relevance") then "date-asc"
        else if ($orderBy eq "date") then "date-asc"
        else if (not($sortByParam)) then "relevance"
        else $sortByParam
    let $section :=
        if (empty($within)) then
            if ($startDate or $volumeId) then "documents" else "entire-site"
        else
            $within
    return map {
        "q": $q, "within": $section, "volume-id": $volumeId,
        "start-date": $startDate, "end-date": $endDate,
        "start-time": $startTime, "end-time": $endTime,
        "sort-by": $sortBy, "start": $start, "per-page": $perPage
    }
};

(:~
 : Full hit computation, cached ~5 min in-memory keyed by a hash of the
 : normalized parameter set (same technique as hsg-shell). Safe to call from
 : several independent template functions in the same request -- the cache
 : absorbs repeat lookups after the first.
 :)
declare %private function srch:results($context as map(*)) as map(*) {
    let $p := srch:read-params($context)
    let $normalized := string-join(
        let $params := map { "q": $p?q, "within": $p?within, "volume-id": $p?("volume-id"), "start-date": $p?("start-date"), "end-date": $p?("end-date"), "start-time": $p?("start-time"), "end-time": $p?("end-time"), "sort-by": $p?("sort-by") }
        for $key in map:keys($params)
        let $val := $params($key) ! normalize-space(.)[. ne ""]
        order by $key
        return $key || "=" || string-join(sort($val), ";"),
        "&amp;"
    )
    let $queryId := util:hash($normalized, "sha1")
    let $cacheName := "hsg-search"
    let $cacheKey := "queries"
    let $cache := cache:get($cacheName, $cacheKey)
    let $cache := if ($cache instance of map(*)) then $cache else map { "created": current-dateTime(), "purged": current-dateTime(), "queries": map {} }
    let $cached := if (map:contains($cache?queries, $queryId)) then map:get($cache?queries, $queryId) else ()
    let $results :=
        if (exists($cached)) then
            $cached
        else
            let $range := srch:date-range($p?("start-date"), $p?("end-date"), $p?("start-time"), $p?("end-time"))
            let $queryConf := srch:prepare-query($p?within, $p?("volume-id"), $p?q, $range?start, $range?end)
            let $hits :=
                try { srch:query-sections($queryConf) } catch * { () }
            let $sorted := srch:sort($hits, $p?("sort-by"))
            let $volIds := map:keys(ft:facets($hits, "frus-volume-id", ()))
            let $entry := map {
                "id": $queryId, "hits": $sorted, "results-vol-ids": $volIds,
                "range-start": $range?start, "range-end": $range?end, "created": current-dateTime()
            }
            let $store := cache:put($cacheName, $cacheKey, map { "created": $cache?created, "purged": $cache?purged, "queries": map:put($cache?queries, $queryId, $entry) })
            return $entry
    let $purgeAge := xs:dayTimeDuration("PT5M")
    let $purge := if (current-dateTime() - $cache?purged gt $purgeAge) then cache:clear($cacheName) else ()
    let $hitCount := count($results?hits)
    let $window := subsequence($results?hits, $p?start, $p?("per-page"))
    return map:merge((
        $p,
        map {
            "hits": $window,
            "hit-count": $hitCount,
            "end": $p?start + count($window) - 1,
            "results-vol-ids": $results?results-vol-ids,
            "range-start": $results?("range-start"),
            "range-end": $results?("range-end")
        }
    ))
};

(: ============== per-type result rendering registry ============== :)

(:~ Falls back to the division's own @xml:id when there's no tei:head to
 : extract a title from -- happens for front-matter divs (persons/preface/
 : sources) that the current frus-data-jinks index config includes
 : unconditionally alongside real documents (see doc/epic-1102-search-plan.md
 : Phase 4: the collection.xconf "if" attribute needed to restrict indexing to
 : document-type divs only turned out to silently break field storage
 : entirely -- a confirmed eXist limitation, not a logic bug -- so this is
 : handled defensively here instead). :)
declare %private function srch:frus-title($doc as element(tei:div)) as xs:string {
    let $heading := ($doc//tei:head)[1]
    let $headingString := if ($heading) then normalize-space(string-join($heading//text()[not(./ancestor::tei:note)])) else ()
    return
        if (not($headingString) or $headingString eq "") then
            string($doc/@xml:id)
        else if (matches($headingString, "^" || $doc/@n || "\.")) then
            replace($headingString, "^" || $doc/@n || "\.\s+(.+)$", "$1")
        else if (matches($headingString, "^No\. " || $doc/@n || "[^\d]")) then
            replace($headingString, "^No\. " || $doc/@n || "(.+)$", "$1")
        else
            $headingString
};

declare %private function srch:frus-summary($doc as element(tei:div)) as element(div) {
    let $docId := $doc/@xml:id
    let $volId := root($doc)/tei:TEI/@xml:id
    let $dateline := ($doc//tei:dateline[.//tei:date])[1]
    let $date := ($dateline//tei:date)[1]
    let $dateString := normalize-space(string-join($date//text()[not(./ancestor::tei:note)]))
    let $placeName := ($doc//tei:placeName)[1]
    let $placeNameString := normalize-space(string-join($placeName//text()[not(./ancestor::tei:note)]))
    let $highlighted := ft:highlight-field-matches($doc, "hsg-fulltext")
    let $kwic :=
        for $hit in subsequence($highlighted//exist:match, 1, 5)
        return kwic:get-summary($highlighted, $hit, <config width="40"/>)/*
    let $score := ft:score($doc)
    return
        <div class="usa-prose">
            <dl>
            {
                if ($doc/@subtype eq "historical-document") then (
                    <dt>Recorded Date</dt>, <dd>{($dateString, "(None)")[. ne ""][1]}</dd>,
                    <dt>Recorded Location</dt>, <dd>{($placeNameString, "(None)")[. ne ""][1]}</dd>
                ) else (),
                <dt>Resource ID</dt>, <dd>{$volId/string()}/{$docId/string()}</dd>,
                if (exists($kwic)) then (<dt>Keyword Results</dt>, <dd>{$kwic}</dd>) else (),
                if ($score) then (<dt>Keyword Relevance</dt>, <dd>{$score}</dd>) else ()
            }
            </dl>
        </div>
};

(:~ title/summary/href for one hit -- href trusts the hsg-url Lucene field
 : (module doc above) except for the two element types with no such field. :)
declare %private function srch:render-hit($hit as element()) as map(*) {
    typeswitch ($hit)
        case element(persName) return map {
            "title": string-join(($hit/forename, $hit/surname, $hit/genName), " "),
            "summary": (),
            "href": ft:field($hit, "hsg-url")
        }
        case element(visit) return map {
            "title": "Visits By Foreign Leaders: " || string-join($hit/visitor, ", "),
            "summary": (),
            "href": ft:field($hit, "hsg-url")
        }
        case element(trips) return
            let $expanded := util:expand($hit)
            let $count := count($expanded//exist:match/ancestor::trip)
            return map {
                "title": "Travels: " || string-join($hit/trip[1]/name, ", "),
                "summary": <p>{$count || " matching trip" || (if ($count gt 1) then "s" else ())}</p>,
                "href": ft:field($hit, "hsg-url")
            }
        case element(tei:div) return
            if (ft:field($hit, "hsg-publication") = "frus" or starts-with(base-uri($hit), $srch:FRUS_COL)) then
                map {
                    "title": srch:frus-title($hit),
                    "summary": srch:frus-summary($hit),
                    "href": ft:field($hit, "hsg-url")
                }
            else
                map {
                    "title": normalize-space(string-join(($hit/tei:head)[1]//text()[not(./ancestor::tei:note)])),
                    "summary": kwic:summarize(util:expand($hit), <config xmlns="" width="60"/>)/*,
                    "href": ft:field($hit, "hsg-url")
                }
        case element(tei:body) return map {
            "title": normalize-space(string-join(($hit/ancestor::tei:TEI//tei:titleStmt/tei:title)[1])),
            "summary": kwic:summarize(util:expand($hit), <config xmlns="" width="60"/>)/*,
            "href": ft:field($hit, "hsg-url")
        }
        default return map { "title": "Untitled result", "summary": (), "href": "#" }
};

(: ============== template-facing functions ============== :)

declare function srch:results-summary($context as map(*)) as element(p) {
    let $r := srch:results($context)
    return
        if ($r?("hit-count") gt 0) then
            <p class="usa-prose">
                Displaying {$r?start}&#8211;{$r?end} of <span class="search-count">{format-number($r?("hit-count"), "#,###")}</span> results
                {
                    string-join((
                        if (normalize-space($r?q) ne "") then ("for keyword &#8220;" || $r?q || "&#8221;") else (),
                        if ($r?within = "entire-site" or empty($r?within)) then "across the entire Office of the Historian website"
                        else "within " || string-join($r?within, ", "),
                        if (exists($r?("range-start")) and exists($r?("range-end"))) then
                            "between " || format-dateTime($r?("range-start"), "[MNn] [D], [Y]") || " and " || format-dateTime($r?("range-end"), "[MNn] [D], [Y]")
                        else ()
                    ), " ")
                    || ", sorted by " || (switch ($r?("sort-by")) case "date-asc" return "dates (oldest first)" case "date-desc" return "dates (most recent first)" default return "relevance")
                }.
            </p>
        else
            <p class="usa-prose">No results were found.</p>
};

declare function srch:results-list($context as map(*)) as element(ul) {
    let $r := srch:results($context)
    return
        <ul class="usa-collection">
        {
            for $hit in $r?hits
            let $rendered := srch:render-hit($hit)
            return
                <li class="usa-collection__item">
                    <div class="usa-collection__body">
                        <h3 class="usa-collection__heading"><a href="{$context?context-path}{$rendered?href}">{$rendered?title}</a></h3>
                        { if (exists($rendered?summary)) then <div class="usa-collection__description">{$rendered?summary}</div> else () }
                    </div>
                </li>
        }
        </ul>
};

declare %private function srch:pagination-query-string($r as map(*), $start as xs:integer) as xs:string {
    string-join((
        "start=" || $start,
        "per-page=" || $r?("per-page"),
        if (normalize-space($r?q) ne "") then "q=" || encode-for-uri($r?q) else (),
        $r?within[not(. = ("", "entire-site"))] ! ("within=" || encode-for-uri(.)),
        $r?("volume-id") ! ("volume-id=" || encode-for-uri(.)),
        $r?("start-date")[. ne ""] ! ("start-date=" || .),
        $r?("end-date")[. ne ""] ! ("end-date=" || .),
        $r?("start-time")[. ne ""] ! ("start-time=" || .),
        $r?("end-time")[. ne ""] ! ("end-time=" || .),
        "sort-by=" || $r?("sort-by")
    ), "&amp;")
};

declare function srch:pagination($context as map(*)) as element(nav)? {
    let $r := srch:results($context)
    let $perPage := $r?("per-page")
    let $pageCount := xs:integer(ceiling($r?("hit-count") div $perPage))
    return
        if ($pageCount le 1) then
            ()
        else
            let $currentPage := xs:integer(ceiling($r?start div $perPage))
            let $maxPages := 7
            let $lower := max((($currentPage - ($maxPages idiv 2)), 1))
            let $upper := min(($lower + $maxPages - 1, $pageCount))
            let $lower := max(($upper - $maxPages + 1, 1))
            return
                <nav aria-label="Search results pagination" class="usa-pagination">
                    <ul class="usa-pagination__list">
                    {
                        if ($currentPage gt 1) then
                            <li class="usa-pagination__item usa-pagination__arrow">
                                <a href="?{srch:pagination-query-string($r, ($currentPage - 2) * $perPage + 1)}" class="usa-pagination__link usa-pagination__previous-page">
                                    <pb-i18n key="odd.previous">Previous</pb-i18n>
                                </a>
                            </li>
                        else (),
                        for $i in $lower to $upper
                        return
                            if ($i eq $currentPage) then
                                <li class="usa-pagination__item usa-pagination__page-no">
                                    <a href="?{srch:pagination-query-string($r, ($i - 1) * $perPage + 1)}" class="usa-pagination__button usa-current" aria-current="page">{$i}</a>
                                </li>
                            else
                                <li class="usa-pagination__item usa-pagination__page-no">
                                    <a href="?{srch:pagination-query-string($r, ($i - 1) * $perPage + 1)}" class="usa-pagination__button">{$i}</a>
                                </li>,
                        if ($currentPage lt $pageCount) then
                            <li class="usa-pagination__item usa-pagination__arrow">
                                <a href="?{srch:pagination-query-string($r, $currentPage * $perPage + 1)}" class="usa-pagination__link usa-pagination__next-page">
                                    <pb-i18n key="odd.next">Next</pb-i18n>
                                </a>
                            </li>
                        else ()
                    }
                    </ul>
                </nav>
};

(:~ Reads the raw `within` parameter directly (not via srch:results) so the
 : landing page -- which has no query to run -- doesn't trigger one just to
 : render checkbox state. :)
declare function srch:filter-sections($context as map(*)) as element(fieldset) {
    let $selected := request:get-parameter("within", ())
    return
        <fieldset class="usa-fieldset">
            <legend class="usa-legend">Filter by Section</legend>
            {
                for $section in srch:sections()
                return
                    <div class="usa-checkbox">
                        <input class="usa-checkbox__input" type="checkbox" name="within" id="within-{$section?id}" value="{$section?id}">
                        { if ($section?id = $selected) then attribute checked { "checked" } else () }
                        </input>
                        <label class="usa-checkbox__label" for="within-{$section?id}">{$section?label}</label>
                    </div>
            }
        </fieldset>
};

declare function srch:filter-volumes($context as map(*)) as element(fieldset)? {
    let $r := srch:results($context)
    return
        if (empty($r?("results-vol-ids"))) then
            ()
        else
            <fieldset class="usa-fieldset">
                <legend class="usa-legend">Filter by Volume</legend>
                {
                    for $volId in $r?("results-vol-ids")
                    order by $volId
                    return
                        <div class="usa-checkbox">
                            <input class="usa-checkbox__input" type="checkbox" name="volume-id" id="volume-{$volId}" value="{$volId}">
                            { if ($volId = $r?("volume-id")) then attribute checked { "checked" } else () }
                            </input>
                            <label class="usa-checkbox__label" for="volume-{$volId}">{$volId}</label>
                        </div>
                }
            </fieldset>
};
