xquery version "3.1";

(:~
 : Cross-collection full-text search (OP#1102): the Lucene query/facet
 : pipeline, sort, cache, pagination, and per-type result rendering ported
 : from hsg-shell's modules/search.xqm, adapted to this app's plain-XQuery
 : template-function style (no eXist html-templating %templates:* annotations
 : -- jinks templates call these directly as [[ srch:whatever($context) ]]).
 :
 : FRUS is queried from /db/apps/frus-data-jinks (this app's own, currently
 : one-volume, frozen data baseline),
 : NOT hsg-shell's full /db/apps/frus/volumes: hsg-jinks's own
 : historicaldocuments routes only ever render frus-data-jinks, so a FRUS hit
 : must point somewhere this app can actually serve. When the real multi-volume
 : data replaces the sample baseline (same repo, same frozen-baseline
 : mechanism), search picks it up automatically -- the collection path below
 : is a single named constant, not repeated per query site.
 :
 : Known, deliberate simplifications versus hsg-shell (documented rather than
 : silently dropped):
 :  - tei:div hit TITLES use the division's own head text only, not hsg-shell's
 :    richer "Section Heading (Document Heading)" built from $config:PUBLICATIONS
 :    -- that per-publication select-section/select-document map has no
 :    equivalent in hsg-jinks yet (each section owns its own narrow slice).
 :  - tei:div/tei:body hit HREFs trust the already-indexed hsg-url Lucene
 :    field directly (confirmed live to already target the current hsg-jinks
 :    URL scheme for every non-FRUS section)
 :    instead of hsg-shell's per-publication html-href() call.
 :  - KWIC summaries are not first trimmed to N matches before summarizing
 :    (hsg-shell's search:trim-matches/milestone-chunk) -- a heavily-matched
 :    hit is summarized in full, then only the first five snippets are shown
 :    (OP#1420: each is held to one line on the result card).
 :  - hsg-shell's unused MAX_HITS_SHOWN cap/message, the hardcoded facet-count
 :    badge, and the frus DISPLAY entry's dead absolute-URL branch are not
 :    ported (dead code in the source, not a feature).
 :)
module namespace srch = "https://history.state.gov/ns/templates/search";

import module namespace kwic = "http://exist-db.org/xquery/kwic";
import module namespace cache = "http://exist-db.org/xquery/cache" at "java:org.exist.xquery.modules.cache.CacheModule";
import module namespace page = "http://teipublisher.com/ns/templates/page" at "page.xqm";
import module namespace fd = "http://history.state.gov/ns/site/hsg/frus-dates" at "../frus-dates.xqm";
import module namespace ext = "http://history.state.gov/ns/frus/odd-ext" at "../frus-ext.xqm";
import module namespace hsg = "https://history.state.gov/ns/templates/hsg" at "hsg.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace vector = "http://exist-db.org/xquery/vector";

(:~ FRUS data collection this app actually renders -- see module doc above. :)
declare variable $srch:FRUS_COL as xs:string := "/db/apps/frus-data-jinks";

(:~ Id of the one GET form (the keyword box) that the results sidebar's
 : controls and the Sort by select all belong to, so a new keyword search
 : keeps the filters and sort, and Apply filters keeps the keyword. :)
declare variable $srch:FORM_ID as xs:string := "hsg-search";

(:~ The cache of recent searches' results, one entry per search, each dropped
 : five minutes after it was last read. cache:create leaves a cache that
 : already exists as it is, so pre-install.xql destroys this one: the first
 : search after each install creates it with $srch:CACHE_CONFIG. :)
declare variable $srch:CACHE as xs:string := "hsg-search";

(:~ Request attribute with the time the request's first srch:results call took. :)
declare variable $srch:TOOK_ATTR as xs:string := "hsg-search-took";
declare variable $srch:CACHE_CONFIG as map(*) := map {
    "expireAfterAccess": 300000,
    "maximumSize": 1000
};

(:~ Hybrid / vector search (FRUS pilot). Local ONNX model shipped with
 : duncdrum/existdb:experimental. k = KNN pool size before RRF fuse. :)
declare variable $srch:EMBED_MODEL as xs:string := "all-MiniLM-L6-v2";
declare variable $srch:VECTOR_K as xs:integer := 50;
declare variable $srch:RRF_K as xs:integer := 60;

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
    (: lower-case: the index analyzer lower-cases the stored date strings
     : (the "T"), and eXist 7 dropped the AnalyzingQueryParser that used to
     : apply the same analysis to range endpoints on the query side; an
     : upper-case "T" in the endpoints silently matches nothing (OP#1316). :)
    let $rangeStartStr := lower-case(translate(string($rangeStart), ':-', ''))
    let $rangeEndStr := lower-case(translate(string($rangeEnd), ':-', ''))
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
        "query-string": $queryString,
        (: the date clause on its own, for the vector leg's filter-query :)
        "date-query": $dateQuery
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

(:~ US Eastern, hard-coded -- see frus-dates.xqm.
 : A time only narrows a full date (YYYY-MM-DD): appended to a year or a
 : year-month it makes an invalid dateTime and the whole date filter was
 : silently dropped, so it is ignored there (OP#1432). :)
declare %private function srch:date-range($startDate as xs:string?, $endDate as xs:string?,
        $startTime as xs:string?, $endTime as xs:string?) as map(*) {
    let $timezone := xs:dayTimeDuration("-PT5H")
    let $withTime := function($date as xs:string, $time as xs:string?) as xs:string {
        if ($time and matches($date, "^\d{4}-\d{2}-\d{2}$")) then $date || "T" || $time else $date
    }
    let $rangeStart :=
        if ($startDate) then fd:normalize-low($withTime($startDate, $startTime), $timezone) else ()
    let $rangeEnd :=
        if ($endDate) then fd:normalize-high($withTime($endDate, $endTime), $timezone)
        else if ($startDate) then fd:normalize-high($startDate, $timezone)
        else ()
    return map { "start": $rangeStart, "end": $rangeEnd }
};


(: ============== hybrid / vector ============== :)

(:~ Score is read inside the leg. A later ft:query-vector must not be the
 : thing that decides which nodes survive. :)
declare %private function srch:scored-vector-hits($nodes as element()*) as map(*)* {
    for $hit in $nodes
    return map { "node": $hit, "score": ft:score($hit), "id": generate-id($hit) }
};

(:~ KNN over collections that define hsg-embedding. Packages without the
 : vector-field contribute nothing (caught). The options map is the fourth
 : argument of ft:query-vector; this image atomizes a map passed as k and
 : the leg then fails. It also ignores numeric top-k and does not return
 : hits in score order, so each leg is scored explicitly, the legs are
 : merged by score, and the pool is cut to VECTOR_K. That keeps a later
 : collection from being dropped because an earlier one filled the pool,
 : and it keeps the nearest hit when it is not among the first VECTOR_K
 : nodes in document order.
 : A date range is passed as filter-query, which Lucene applies inside the
 : KNN search, so the VECTOR_K nearest hits are all within the range. Left
 : out, the vector leg ignored the range: a 1985-only search returned 50
 : nearest hits from any year. Collections without the frus-search-date
 : fields then contribute nothing, as on the keyword leg. :)
declare %private function srch:query-vector-sections($queryConf as map(*), $q as xs:string) as element()* {
    if (normalize-space($q) eq "") then
        ()
    else
        try {
            let $vec := vector:embed($q, $srch:EMBED_MODEL)
            let $dateFilter := $queryConf?("date-query")
            let $opts := map:merge((
                $srch:ft-query-options,
                $queryConf?facets,
                if (exists($dateFilter)) then map { "filter-query": $dateFilter } else ()
            ))
            let $scored := (
                try { srch:scored-vector-hits(collection("/db/apps/other-publications")//tei:div[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () },
                try { srch:scored-vector-hits(collection("/db/apps/other-publications")//tei:body[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () },
                try { srch:scored-vector-hits(collection("/db/apps/conferences")//tei:div[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () },
                try { srch:scored-vector-hits(collection("/db/apps/hac")//tei:div[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () },
                try { srch:scored-vector-hits(collection($srch:FRUS_COL)//tei:div[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () },
                try { srch:scored-vector-hits(collection("/db/apps/frus-history/articles")//tei:body[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () },
                try { srch:scored-vector-hits(collection("/db/apps/frus-history/documents")//tei:body[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () },
                try { srch:scored-vector-hits(collection("/db/apps/frus-history/monograph")//tei:div[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () },
                try { srch:scored-vector-hits(collection("/db/apps/rdcr")//tei:body[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () },
                try { srch:scored-vector-hits(collection("/db/apps/wwdai")//tei:body[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () },
                try { srch:scored-vector-hits(collection("/db/apps/pocom/people")//persName[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () },
                try { srch:scored-vector-hits(collection("/db/apps/travels")//trips[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () },
                try { srch:scored-vector-hits(collection("/db/apps/visits")//visit[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () },
                try { srch:scored-vector-hits(collection("/db/apps/milestones")//tei:div[ft:query-vector(., $vec, $srch:VECTOR_K, $opts)]) } catch * { () }
            )
            let $ranked :=
                for $row in $scored
                order by $row?score descending empty least, $row?id
                return $row?node
            return subsequence($ranked, 1, $srch:VECTOR_K)
        } catch * {
            ()
        }
};

(:~ Reciprocal Rank Fusion of two hit sequences (Lucene + vector). Both
 : must already be in relevance order: a hit's rank is its position. Ranks
 : and nodes are looked up in maps built once per call; the earlier version
 : rescanned both sequences for every hit, which took 13.9 s for 6,221
 : keyword hits (51 ms this way, same order). :)
declare %private function srch:fuse-rrf($lucene as element()*, $vector as element()*) as element()* {
    let $lRank := map:merge(for $hit at $i in $lucene return map:entry(generate-id($hit), $i), map { "duplicates": "use-first" })
    let $vRank := map:merge(for $hit at $i in $vector return map:entry(generate-id($hit), $i), map { "duplicates": "use-first" })
    let $nodes := map:merge(for $hit in ($lucene, $vector) return map:entry(generate-id($hit), $hit), map { "duplicates": "use-first" })
    for $id in distinct-values(($lucene, $vector) ! generate-id(.))
    let $score :=
        (if (map:contains($lRank, $id)) then 1 div ($srch:RRF_K + $lRank($id)) else 0)
        + (if (map:contains($vRank, $id)) then 1 div ($srch:RRF_K + $vRank($id)) else 0)
    order by $score descending
    return $nodes($id)
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
    let $modeParam := normalize-space(page:parameter($context, "mode", "keyword"))
    let $mode := if ($modeParam eq "hybrid") then "hybrid" else "keyword"
    return map {
        "q": $q, "within": $section, "volume-id": $volumeId,
        "start-date": $startDate, "end-date": $endDate,
        "start-time": $startTime, "end-time": $endTime,
        "sort-by": $sortBy, "start": $start, "per-page": $perPage,
        "mode": $mode
    }
};

(:~
 : The hits of a search in the order $sortBy asks for. Relevance for hybrid is
 : the RRF order: re-sorting by ft:score puts Lucene scores (about 5) ahead of
 : vector scores (about 1) and the fused order disappears.
 :)
declare %private function srch:order($hits as element()*, $sortBy as xs:string, $fused as xs:boolean) as element()* {
    if ($fused and $sortBy eq "relevance") then
        $hits
    else
        srch:sort($hits, $sortBy)
};

(:~
 : Full hit computation, cached in $srch:CACHE under a hash of the normalized
 : parameter set (same technique as hsg-shell). The sort order is not part of
 : the key: an entry keeps the hits as the search found them, plus each order
 : a page has asked for, so changing the sort only sorts again. Safe to call
 : from several independent template functions in the same request: the cache
 : absorbs repeat lookups after the first.
 :)
declare %private function srch:results($context as map(*)) as map(*) {
    (: as in hsg-shell, "took" is the time this request spent getting its
       results: the whole search, or only the cache lookup and any sort :)
    let $started := util:system-time()
    let $p := srch:read-params($context)
    let $sortBy := $p?("sort-by")
    let $normalized := string-join(
        let $params := map { "q": $p?q, "within": $p?within, "volume-id": $p?("volume-id"), "start-date": $p?("start-date"), "end-date": $p?("end-date"), "start-time": $p?("start-time"), "end-time": $p?("end-time"), "mode": $p?mode }
        for $key in map:keys($params)
        let $val := $params($key) ! normalize-space(.)[. ne ""]
        order by $key
        return $key || "=" || string-join(sort($val), ";"),
        "&amp;"
    )
    let $queryId := util:hash($normalized, "sha1")
    (: returns false, and changes nothing, once the cache exists :)
    let $create := cache:create($srch:CACHE, $srch:CACHE_CONFIG)
    let $cached := cache:get($srch:CACHE, $queryId)
    let $entry :=
        if (exists($cached)) then
            $cached
        else
            let $range := srch:date-range($p?("start-date"), $p?("end-date"), $p?("start-time"), $p?("end-time"))
            let $queryConf := srch:prepare-query($p?within, $p?("volume-id"), $p?q, $range?start, $range?end)
            let $luceneHits :=
                try { srch:query-sections($queryConf) } catch * { () }
            let $vectorHits :=
                if ($p?mode eq "hybrid" and exists($p?q)) then
                    srch:query-vector-sections($queryConf, $p?q)
                else
                    ()
            (: RRF ranks the keyword leg by position, so it goes in by
               ft:score. srch:query-sections returns hits collection by
               collection in document order: unsorted, the best keyword
               match for "famine relief" sat at position 199 of 465. :)
            let $fused :=
                if (exists($vectorHits)) then
                    srch:fuse-rrf(srch:sort($luceneHits, "relevance"), $vectorHits)
                else
                    $luceneHits
            let $volIds :=
                try { map:keys(ft:facets($luceneHits, "frus-volume-id", ())) }
                catch * { () }
            return map {
                "id": $queryId, "hits": $fused, "fused": exists($vectorHits), "orders": map {},
                "results-vol-ids": $volIds,
                "range-start": $range?start, "range-end": $range?end, "created": current-dateTime()
            }
    (: The entry comes from the cache, so its maps are read with the lookup
       operator: calling a cached map as a function ($orders($sortBy)) fails in
       eXist when another request uses it at the same time. :)
    let $sorted :=
        if (map:contains($entry?orders, $sortBy)) then
            $entry?orders?($sortBy)
        else
            srch:order($entry?hits, $sortBy, $entry?fused)
    (: store the search, or the order it gained, for the next request :)
    let $store :=
        if (map:contains($entry?orders, $sortBy)) then
            ()
        else
            cache:put($srch:CACHE, $queryId, map:put($entry, "orders", map:put($entry?orders, $sortBy, $sorted)))
    let $hitCount := count($sorted)
    let $window := subsequence($sorted, $p?start, $p?("per-page"))
    (: The page asks for its results several times, and the first call does
       the work: the sidebar's volume filter is rendered before the summary.
       So the first call keeps its time for the others to report. :)
    let $took := (
        request:get-attribute($srch:TOOK_ATTR),
        seconds-from-duration(util:system-time() - $started)
    )[1]
    let $keep := request:set-attribute($srch:TOOK_ATTR, $took)
    return map:merge((
        $p,
        map {
            "hits": $window,
            "hit-count": $hitCount,
            "end": $p?start + count($window) - 1,
            "results-vol-ids": $entry?results-vol-ids,
            "took": $took,
            "range-start": $entry?("range-start"),
            "range-end": $entry?("range-end")
        }
    ))
};

(: ============== per-type result rendering registry ============== :)

(:~ Falls back to the division's own @xml:id when there's no tei:head to
 : extract a title from -- happens for front-matter divs (persons/preface/
 : sources) that the current frus-data-jinks index config includes
 : unconditionally alongside real documents (the collection.xconf "if"
 : attribute needed to restrict indexing to document-type divs only silently
 : breaks field storage entirely -- an eXist limitation, not a logic bug --
 : so this is handled defensively here instead). :)
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

(:~ One label/value row of a result card's metadata list. :)
declare %private function srch:meta-row($label as xs:string, $value as item()*) as element()+ {
    <dt>{$label}</dt>,
    <dd>{$value}</dd>
};

(:~ The keyword-in-context snippets of a hit, at most five, each wrapped in
 : its own span so the card can hold every match to a single line. :)
declare %private function srch:snippets($summaries as element()*) as element(span)* {
    for $summary in subsequence($summaries, 1, 5)
    return <span class="hsg-snippet">{$summary/*}</span>
};

(:~ Metadata list of a card. :)
declare %private function srch:meta-list($rows as element()*) as element(dl)? {
    if (exists($rows)) then <dl class="hsg-result__meta">{$rows}</dl> else ()
};

(:~
 : Card content for a FRUS division: the place and date chips and the
 : recorded/encoded date rows (historical documents only), the resource id,
 : and the keyword snippets and score. No facsimile link: search results
 : don't offer one (OP#1432, a business decision; the reference site didn't
 : show it either).
 :)
declare %private function srch:frus-card($doc as element(tei:div)) as map(*) {
    let $docId := $doc/@xml:id
    let $volId := root($doc)/tei:TEI/@xml:id
    (: the division subtype is a teiHeader bibl in this data model, not an
       attribute on the div (see ext:get-division-subtype), so the rows and
       chips reserved for historical documents key off that :)
    let $historical := ext:get-division-subtype($doc) eq "historical-document"
    let $dateline := ($doc//tei:dateline[.//tei:date])[1]
    let $date := ($dateline//tei:date)[1]
    let $dateString := normalize-space(string-join($date//text()[not(./ancestor::tei:note)]))
    let $placeName := ($doc//tei:placeName)[1]
    let $placeNameString := normalize-space(string-join($placeName//text()[not(./ancestor::tei:note)]))
    let $highlighted := ft:highlight-field-matches($doc, "hsg-fulltext")
    let $snippets := srch:snippets(
        for $hit in subsequence($highlighted//exist:match, 1, 5)
        return kwic:get-summary($highlighted, $hit, <config width="40"/>)
    )
    let $score := ft:score($doc)
    return map {
        "tags": if ($historical) then ($placeNameString, $dateString)[. ne ""] else (),
        "summary": srch:meta-list((
            if ($historical) then (
                srch:meta-row("Recorded Date", ($dateString, "(None)")[. ne ""][1]),
                srch:meta-row("Recorded Location", ($placeNameString, "(None)")[. ne ""][1]),
                if ($date/@when) then srch:meta-row("Encoded Date", <code>when="{string($date/@when)}"</code>) else ()
            ) else (),
            srch:meta-row("Resource ID", $volId/string() || "/" || $docId/string()),
            if (exists($snippets)) then srch:meta-row("Keyword Results", $snippets) else (),
            if ($score) then srch:meta-row("Keyword Relevance", $score) else ()
        ))
    }
};

(:~
 : What one hit renders as: title and href for the card heading, plus
 : "tags" (chips above the title) and "summary" (the metadata list), both
 : empty where a hit type has nothing to show. The href trusts the hsg-url Lucene field (module doc
 : above) except for the two element types with no such field.
 :)
declare %private function srch:render-hit($hit as element()) as map(*) {
    let $href := ft:field($hit, "hsg-url")
    let $card := function($title as xs:string, $rows as element()*) as map(*) {
        map { "title": $title, "href": $href, "tags": (), "summary": srch:meta-list($rows) }
    }
    return
        typeswitch ($hit)
            case element(persName) return
                $card(string-join(($hit/forename, $hit/surname, $hit/genName), " "), ())
            case element(visit) return
                $card("Visits By Foreign Leaders: " || string-join($hit/visitor, ", "), ())
            case element(trips) return
                let $expanded := util:expand($hit)
                let $count := count($expanded//exist:match/ancestor::trip)
                return $card("Travels: " || string-join($hit/trip[1]/name, ", "), srch:meta-row("Matching Trips", $count))
            case element(tei:div) return
                if (ft:field($hit, "hsg-publication") = "frus" or starts-with(base-uri($hit), $srch:FRUS_COL)) then
                    map:merge((map { "title": srch:frus-title($hit), "href": $href }, srch:frus-card($hit)))
                else
                    $card(
                        normalize-space(string-join(($hit/tei:head)[1]//text()[not(./ancestor::tei:note)])),
                        srch:keyword-row(kwic:summarize(util:expand($hit), <config xmlns="" width="60"/>))
                    )
            case element(tei:body) return
                $card(
                    normalize-space(string-join(($hit/ancestor::tei:TEI//tei:titleStmt/tei:title)[1])),
                    srch:keyword-row(kwic:summarize(util:expand($hit), <config xmlns="" width="60"/>))
                )
            default return
                map { "title": "Untitled result", "href": "#", "tags": (), "summary": () }
};

(:~ The "Keyword Results" row of the non-FRUS hit types, from kwic:summarize. :)
declare %private function srch:keyword-row($summaries as element()*) as element()* {
    let $snippets := srch:snippets($summaries)
    return if (exists($snippets)) then srch:meta-row("Keyword Results", $snippets) else ()
};

(: ============== template-facing functions ============== :)

declare function srch:results-summary($context as map(*)) as element(p) {
    let $r := srch:results($context)
    return
        if ($r?("hit-count") gt 0) then
            <p class="usa-prose hsg-results-summary">
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
                { if (exists($r?took)) then " Search completed in " || format-number($r?took, "0.000") || "s." else () }
            </p>
        else
            <p class="usa-prose hsg-results-summary">No results were found.</p>
};

(:~ One card per hit: chips, title link, metadata list. The
 : list keeps USWDS's usa-collection semantics; the card look is the theme's
 : (resources/css/hsg-theme.css, "Search results page"). :)
declare function srch:results-list($context as map(*)) as element(ul) {
    let $r := srch:results($context)
    return
        <ul class="usa-collection hsg-results">
        {
            for $hit in $r?hits
            let $rendered := srch:render-hit($hit)
            return
                <li class="usa-collection__item">
                    <div class="usa-collection__body">
                        {
                            if (exists($rendered?tags)) then
                                <ul class="usa-collection__meta hsg-result__tags" aria-label="Place and date">
                                {
                                    for $tag in $rendered?tags
                                    return <li class="usa-collection__meta-item usa-tag">{$tag}</li>
                                }
                                </ul>
                            else
                                ()
                        }
                        <h3 class="usa-collection__heading"><a href="{$context?context-path}{$rendered?href}">{$rendered?title}</a></h3>
                        { $rendered?summary }
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
        "sort-by=" || $r?("sort-by"),
        if ($r?mode eq "hybrid") then "mode=hybrid" else ()
    ), "&amp;")
};

(:~ Previous/next link with its USWDS sprite arrow. :)
(:~ The Previous or Next link; without a $start it is hidden but keeps its
 : space (see hsg:pagination-arrow). :)
declare %private function srch:pagination-arrow($context as map(*), $r as map(*), $start as xs:integer?, $direction as xs:string) as element(li) {
    let $previous := $direction eq "previous"
    let $icon :=
        <svg class="usa-icon" aria-hidden="true" focusable="false" role="img">
            <use href="{$context?context-path}/resources/images/sprite.svg#{if ($previous) then 'navigate_before' else 'navigate_next'}"/>
        </svg>
    let $label := <span class="usa-pagination__link-text"><pb-i18n key="{if ($previous) then 'odd.previous' else 'odd.next'}">{if ($previous) then "Previous" else "Next"}</pb-i18n></span>
    let $content := if ($previous) then ($icon, $label) else ($label, $icon)
    return
        if (empty($start)) then
            <li class="usa-pagination__item usa-pagination__arrow hsg-pagination__placeholder" aria-hidden="true">
                <span class="usa-pagination__link usa-pagination__{$direction}-page">{$content}</span>
            </li>
        else
            <li class="usa-pagination__item usa-pagination__arrow">
                <a href="?{srch:pagination-query-string($r, $start)}" class="usa-pagination__link usa-pagination__{$direction}-page" aria-label="{if ($previous) then 'Previous' else 'Next'} page">
                    {$content}
                </a>
            </li>
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
            return
                <nav aria-label="Search results pagination" class="usa-pagination hsg-search-pagination">
                    <ul class="usa-pagination__list">
                    {
                        srch:pagination-arrow($context, $r, if ($currentPage le 1) then () else ($currentPage - 2) * $perPage + 1, "previous"),
                        for $item in hsg:page-window($currentPage, $pageCount)
                        return
                            if ($item instance of xs:string) then
                                <li class="usa-pagination__item usa-pagination__overflow" role="presentation"><span>{$item}</span></li>
                            else
                                <li class="usa-pagination__item usa-pagination__page-no">
                                    <a href="?{srch:pagination-query-string($r, ($item - 1) * $perPage + 1)}" class="usa-pagination__button{if ($item eq $currentPage) then ' usa-current' else ''}" aria-label="Page {$item}">
                                    { if ($item eq $currentPage) then attribute aria-current { "page" } else () }
                                    {$item}
                                    </a>
                                </li>,
                        srch:pagination-arrow($context, $r, if ($currentPage ge $pageCount) then () else $currentPage * $perPage + 1, "next")
                    }
                    </ul>
                </nav>
};

(:~ The search mode, one checkbox (OP#1473): ticked submits mode=hybrid,
 : unticked submits no mode, the keyword default. Keeps the choice across
 : landing and results. :)
declare function srch:mode-toggle($context as map(*)) as element(div) {
    let $hybrid := normalize-space(page:parameter($context, "mode", "keyword")) eq "hybrid"
    return
        <div class="usa-checkbox hsg-search-mode">
            <input class="usa-checkbox__input" id="mode-hybrid" type="checkbox" name="mode" value="hybrid" form="hsg-search">
            { if ($hybrid) then attribute checked { "checked" } else () }
            </input>
            <label class="usa-checkbox__label" for="mode-hybrid">Use the new hybrid mode with semantic search</label>
        </div>
};

(:~ The section checkboxes of the sidebar, on the landing and the results
 : page alike. $form names the form the boxes belong to (the sidebar sits
 : outside the search form's element).
 :
 : The first box, "Entire Office of the Historian Website", is ticked when no
 : section is chosen and is exclusive with the others
 : (resources/scripts/search-filters.js). It has no name: searching the whole
 : site is the absence of a within parameter, so URLs and legacy links stay
 : as they were. :)
declare %private function srch:section-checkboxes($form as xs:string?, $selected as xs:string*) as element(div)* {
    <div class="usa-checkbox">
        <input class="usa-checkbox__input" type="checkbox" id="within-entire-site" data-hsg-entire-site="">
        {
            if (exists($form)) then attribute form { $form } else (),
            if (empty($selected[not(. = ("", "entire-site"))])) then attribute checked { "checked" } else ()
        }
        </input>
        <label class="usa-checkbox__label" for="within-entire-site">Entire Office of the Historian Website</label>
    </div>,
    for $section in srch:sections()
    return
        <div class="usa-checkbox">
            <input class="usa-checkbox__input" type="checkbox" name="within" id="within-{$section?id}" value="{$section?id}">
            {
                if (exists($form)) then attribute form { $form } else (),
                if ($section?id = $selected) then attribute checked { "checked" } else ()
            }
            </input>
            <label class="usa-checkbox__label" for="within-{$section?id}">{$section?label}</label>
        </div>
};

(: ============== date filter (landing page and results sidebar) ============== :)

(:~ The date filter only applies to historical documents, so it is offered
 : only while that is the one section searched (reference parity: hsg-shell's
 : app.js shows it only when "Historical Documents" is the sole ticked box).
 : The volumes filter follows the same rule.
 : resources/scripts/search-filters.js keeps this in step as boxes change. :)
declare function srch:date-filter-active($within as xs:string*) as xs:boolean {
    deep-equal(distinct-values($within[. ne ""]), "documents")
};

(:~ The attributes of a filter group that only applies to historical
 : documents (the date filter and the volumes), marked for
 : resources/scripts/search-filters.js. Unless Historical Documents is the only
 : section, the group is disabled, so nothing in it is submitted, and with
 : $mode "hide" also hidden. The sidebar of both search pages shows its
 : groups disabled ("disable", OP#1440, OP#1436). :)
declare %private function srch:documents-only($within as xs:string*, $mode as xs:string) as attribute()+ {
    attribute data-hsg-documents-only { $mode },
    if (srch:date-filter-active($within)) then ()
    else (
        if ($mode eq "hide") then attribute hidden { "hidden" } else (),
        attribute disabled { "disabled" }
    )
};

(:~ "1985-06-12", "1985-06" or "1985" to its parts; absent parts are (). :)
declare %private function srch:date-parts($date as xs:string?) as map(*) {
    let $parts := tokenize(normalize-space($date), "-")[. ne ""]
    return map { "year": $parts[1], "month": $parts[2], "day": $parts[3] }
};

(:~ "13:05" to a 12-hour clock: hour 1, minute "05", pm. :)
declare %private function srch:time-parts($time as xs:string?) as map(*) {
    if (matches($time, "^\d{1,2}:\d{2}")) then
        let $hour := xs:integer(substring-before($time, ":"))
        return map {
            "hour": string(if ($hour eq 0) then 12 else if ($hour gt 12) then $hour - 12 else $hour),
            "minute": substring(substring-after($time, ":"), 1, 2),
            "pm": $hour ge 12
        }
    else
        map {}
};

(:~ One numeric part of a date or time. It has no name on purpose: only the
 : combined hidden field (srch:date-time-fields) is submitted. :)
declare %private function srch:part-field($id as xs:string, $label as xs:string, $value as xs:string?,
        $maxlength as xs:integer, $placeholder as xs:string, $hint as xs:string, $part as xs:string) as element(div) {
    <div class="usa-form-group usa-form-group--{if ($maxlength eq 4) then 'year' else 'month'}">
        <label class="usa-label" for="{$id}">{$label}</label>
        <input class="usa-input usa-input--inline usa-memorable-date__input" id="{$id}" type="text"
            inputmode="numeric" maxlength="{$maxlength}" pattern="[0-9]*" placeholder="{$placeholder}"
            aria-describedby="{$hint}" data-part="{$part}" value="{$value}"/>
    </div>
};

(:~
 : The start or end of the date filter, as on the reference site: month, day
 : and year, where a year alone or a month and year searches that whole year or
 : month, plus an optional hour and minute. resources/scripts/search-filters.js
 : combines the parts into the hidden start-date/end-date and
 : start-time/end-time fields on submit, so URLs keep the parameters the
 : backend and legacy deep links use; the parts are filled back from those
 : parameters here. $form names the search form when the fields sit outside it.
 :)
declare %private function srch:date-time-fields($context as map(*), $prefix as xs:string, $form as xs:string?) as element(div) {
    let $date := srch:date-parts(page:parameter($context, $prefix || "-date", ()))
    let $time := srch:time-parts(page:parameter($context, $prefix || "-time", ()))
    let $label := if ($prefix eq "start") then "Start" else "End"
    let $dateHint := $prefix || "-date-hint"
    let $timeHint := $prefix || "-time-hint"
    return
        <div class="hsg-date-time" data-date-prefix="{$prefix}">
            <fieldset class="usa-fieldset hsg-date-time__group">
                <legend class="usa-legend">{$label} date{if ($prefix eq "end") then <span class="usa-hint"> (optional)</span> else ()}</legend>
                <span class="usa-hint" id="{$dateHint}">{
                    if ($prefix eq "start") then
                        "For example: 12 07 1941. A year, or a month and year, on its own searches that whole period."
                    else
                        "For example: 08 15 1945. Leave blank to search only the start date or period."
                }</span>
                <div class="usa-memorable-date">
                    { srch:part-field($prefix || "-date-month", "Month", $date?month, 2, "MM", $dateHint, "month") }
                    { srch:part-field($prefix || "-date-day", "Day", $date?day, 2, "DD", $dateHint, "day") }
                    { srch:part-field($prefix || "-date-year", "Year", $date?year, 4, "YYYY", $dateHint, "year") }
                </div>
            </fieldset>
            <fieldset class="usa-fieldset hsg-date-time__group">
                <legend class="usa-legend">{$label} time<span class="usa-hint"> (optional)</span></legend>
                <span class="usa-hint" id="{$timeHint}">For example: {if ($prefix eq "start") then "09 00 am" else "05 00 pm"}</span>
                <div class="usa-memorable-date">
                    { srch:part-field($prefix || "-time-hour", "Hour", $time?hour, 2, "hh", $timeHint, "hour") }
                    { srch:part-field($prefix || "-time-minute", "Minute", $time?minute, 2, "mm", $timeHint, "minute") }
                    <div class="usa-form-group hsg-date-time__period">
                        <label class="usa-label" for="{$prefix}-time-period">am/pm</label>
                        <select class="usa-select" id="{$prefix}-time-period" data-part="period">
                            <option value="am">{if ($time?pm) then () else attribute selected { "selected" }}am</option>
                            <option value="pm">{if ($time?pm) then attribute selected { "selected" } else ()}pm</option>
                        </select>
                    </div>
                </div>
            </fieldset>
            <input type="hidden" id="{$prefix}-date" name="{$prefix}-date" value="{page:parameter($context, $prefix || '-date', '')}">{ if (exists($form)) then attribute form { $form } else () }</input>
            <input type="hidden" id="{$prefix}-time" name="{$prefix}-time" value="{page:parameter($context, $prefix || '-time', '')}">{ if (exists($form)) then attribute form { $form } else () }</input>
        </div>
};

(:~ The whole date filter: start and end. Disabled, so nothing in it is
 : submitted, and with $mode "hide" hidden, unless Historical Documents is
 : the only section searched (srch:documents-only). :)
declare %private function srch:date-filter($context as map(*), $within as xs:string*, $form as xs:string?,
        $class as xs:string, $legend as element(), $mode as xs:string) as element(fieldset) {
    <fieldset class="usa-fieldset {$class}">
        { srch:documents-only($within, $mode) }
        { $legend }
        { srch:date-time-fields($context, "start", $form) }
        { srch:date-time-fields($context, "end", $form) }
    </fieldset>
};

(: ============== results sidebar ============== :)

declare %private function srch:filter-group($title as xs:string, $hint as xs:string?, $controls as item()*) as element(fieldset) {
    srch:filter-group($title, $hint, $controls, ())
};

declare %private function srch:filter-group($title as xs:string, $hint as xs:string?, $controls as item()*,
        $attributes as attribute()*) as element(fieldset) {
    <fieldset class="usa-fieldset hsg-filter-group">
        { $attributes }
        <legend class="hsg-filter-group__title">{$title}</legend>
        { if (exists($hint)) then <p class="hsg-filter-group__hint">{$hint}</p> else () }
        { $controls }
    </fieldset>
};

(:~ "Volume 31, Part 1" style labels are long; the design shows the title
 : without the series name and with the volume abbreviated. Falls back to the
 : bare id where the volume's own title can't be read. :)
declare %private function srch:volume-label($volumeId as xs:string) as xs:string {
    let $title := hsg:publication-title($volumeId)
    return
        if (exists($title) and $title ne "") then
            replace(replace($title, "^Foreign Relations of the United States,\s*", ""), "Volume ", "Vol. ")
        else
            $volumeId
};

(:~ Reset link for the sidebar: back to the keyword alone, dropping every filter. :)
declare %private function srch:reset-href($context as map(*)) as xs:string {
    $context?context-path || "/search?q=" || encode-for-uri(normalize-space(page:parameter($context, "q", "")))
};

(:~
 : The whole "Filter by" sidebar, the same on the landing and the results
 : page (OP#1436): the Sections, Date and Volumes groups and the Reset /
 : Apply buttons. Every control names the search form with @form (see
 : $srch:FORM_ID) instead of being nested in it; both pages give their
 : search form that id.
 :)
declare function srch:filters($context as map(*)) as element(div) {
    srch:filters($context, true())
};

(:~ $volumes false() is the landing page: its Volumes group has no options,
 : since they are the volumes of the current hits and there is no search yet,
 : only a note, so the sidebar has the same groups on both pages (OP#1436). :)
declare function srch:filters($context as map(*), $volumes as xs:boolean) as element(div) {
    (: the sections actually searched, so a date-only deep link (no within)
       shows Historical Documents ticked and its date filter open :)
    let $within := srch:read-params($context)?within[. ne "entire-site"]
    return
    <div class="hsg-search-filters">
        <h2 class="hsg-search-filters__heading">Filter by</h2>
        {
            srch:filter-group("Sections", (), srch:section-checkboxes($srch:FORM_ID, $within)),
            srch:date-filter($context, $within, $srch:FORM_ID, "hsg-filter-group hsg-date-filter",
                <legend class="hsg-filter-group__title">Date</legend>, "disable"),
            if ($volumes) then srch:filter-volumes($context, $within) else srch:filter-volumes-placeholder($within)
        }
        <div class="hsg-search-filters__actions">
            <a class="usa-button usa-button--outline" href="{srch:reset-href($context)}">Reset filters</a>
            <button class="usa-button" type="submit" form="{$srch:FORM_ID}">Apply filters</button>
        </div>
    </div>
};

(:~ "Sort by" select for the heading row of the results. It belongs to the
 : search form; resources/scripts/search-results.js submits it on change. :)
declare function srch:sort-select($context as map(*)) as element(div) {
    let $current := srch:read-params($context)?("sort-by")
    return
        <div class="hsg-sort">
            <label class="usa-label" for="sort-by">Sort by</label>
            <select class="usa-select" id="sort-by" name="sort-by" form="{$srch:FORM_ID}" data-submit-on-change="">
            {
                for $option in (
                    map { "value": "relevance", "label": "Relevance" },
                    map { "value": "date-asc", "label": "Dates (oldest first)" },
                    map { "value": "date-desc", "label": "Dates (most recent first)" }
                )
                return
                    <option value="{$option?value}">
                    { if ($option?value eq $current) then attribute selected { "selected" } else () }
                    {$option?label}
                    </option>
            }
            </select>
        </div>
};

(:~ The volumes the current hits fall in, as checkboxes. Absent when nothing
 : matched or no hit is a FRUS volume. The label is clamped to two lines by
 : the theme; the full title stays available as the tooltip. :)
(:~ The landing page's Volumes group: no search has run, so there are no
 : volumes to offer yet, only a note on where they come from. :)
declare %private function srch:filter-volumes-placeholder($within as xs:string*) as element(fieldset) {
    srch:filter-group("Volumes", (),
        <p class="hsg-filter-group__note">Run a search to choose from the volumes your results come from.</p>,
        srch:documents-only($within, "disable")
    )
};

declare %private function srch:filter-volumes($context as map(*), $within as xs:string*) as element(fieldset)? {
    let $r := srch:results($context)
    return
        if (empty($r?("results-vol-ids"))) then
            ()
        else
            srch:filter-group("Volumes", (),
                for $volId in sort($r?("results-vol-ids"))
                let $label := srch:volume-label($volId)
                return
                    <div class="usa-checkbox">
                        <input class="usa-checkbox__input" type="checkbox" name="volume-id" id="volume-{$volId}" value="{$volId}" form="{$srch:FORM_ID}">
                        { if ($volId = $r?("volume-id")) then attribute checked { "checked" } else () }
                        </input>
                        <label class="usa-checkbox__label" for="volume-{$volId}" title="{hsg:publication-title($volId)}">
                            <span class="hsg-filter-group__label-text">{$label}</span>
                        </label>
                    </div>,
                srch:documents-only($within, "disable")
            )
};
