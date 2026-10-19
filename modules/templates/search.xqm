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

(:~ Words of a semantic-only hit's opening shown on its card (srch:opening). :)
declare variable $srch:OPENING_WORDS as xs:integer := 60;

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
        "fields": map { "fields": ("hsg-date-min", "hsg-url") },
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
 : fields then contribute nothing, as on the keyword leg.
 : Returns the hits as srch:scored-vector-hits rows, nearest first, so the
 : cards can show each hit's similarity. :)
declare %private function srch:query-vector-sections($queryConf as map(*), $q as xs:string) as map(*)* {
    if (normalize-space($q) eq "") then
        ()
    else
        try {
            srch:vector-neighbors($queryConf, vector:embed($q, $srch:EMBED_MODEL))
        } catch * {
            ()
        }
};

(:~
 : The VECTOR_K nodes nearest to $vec across the searched collections, as
 : srch:scored-vector-hits rows, nearest first: the vector leg of a hybrid
 : search ($vec embeds the query) and of a "similar to" search ($vec embeds
 : a hit, srch:like-vector). See srch:query-vector-sections for the options.
 :)
declare %private function srch:vector-neighbors($queryConf as map(*), $vec as array(*)) as map(*)* {
    try {
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
                return $row
            return subsequence($ranked, 1, $srch:VECTOR_K)
        } catch * {
            ()
        }
};

(:~ The collections, below /db/apps, a "similar to" search may start from. :)
declare variable $srch:LIKE_ROOTS as xs:string+ := (
    "frus-data-jinks", "other-publications", "conferences", "hac", "frus-history", "rdcr", "wwdai", "milestones"
);

(:~
 : The hit a "similar to" search starts from. $like names it as the file's
 : path below /db/apps and, for a division, its @xml:id after "#", the form
 : srch:like-ref writes: "hac/hac.xml#june-1996", or
 : "rdcr/articles/afghanistan.xml" for a tei:body. Only the collections the
 : search covers ($srch:LIKE_ROOTS) are accepted, and only the tei:div and
 : tei:body hits whose vector field embeds their whole text.
 :)
declare %private function srch:like-seed($like as xs:string?) as element()? {
    let $path := substring-before($like || "#", "#")
    let $id := substring-after($like, "#")
    return
        if (not(matches($path, "^[A-Za-z0-9._/-]+\.xml$")) or contains($path, "..")
            or not(some $root in $srch:LIKE_ROOTS satisfies starts-with($path, $root || "/"))) then
            ()
        else
            let $uri := "/db/apps/" || $path
            let $doc := if (doc-available($uri)) then doc($uri) else ()
            return
                if ($id ne "") then $doc//tei:div[@xml:id = $id][1]
                else ($doc//tei:body)[1]
};

(:~ The srch:like-seed reference of a tei:div or tei:body hit. :)
declare function srch:like-ref($hit as element()) as xs:string {
    substring-after(document-uri(root($hit)), "/db/apps/")
    || ($hit[self::tei:div]/@xml:id ! ("#" || .))
};

(:~
 : The vector a hit was indexed with, computed again: the packages' vector
 : fields embed the node's text (expression ".", or a guard that returns the
 : node), and the model is deterministic, so embedding string($hit) gives the
 : stored vector, short of differences in how the indexer prepares the text.
 : eXist has no function that reads a stored vector back. The model reads
 : only the first 128 tokens, so only the opening is passed.
 :)
declare %private function srch:like-vector($hit as element()) as array(*)? {
    try { vector:embed(substring(string($hit), 1, 4000), $srch:EMBED_MODEL) } catch * { () }
};

(:~
 : What the semantic search found, for the cards: each vector hit's
 : similarity, and whether the keyword search found it too, keyed by node id.
 : The keyword copy of a hit found by both is the one RRF keeps, so its card
 : has keyword matches to highlight; a hit found only by the semantic search
 : has none, because it matched on one vector for the whole node, not on any
 : words.
 :)
declare %private function srch:semantic-matches($lucene as element()*, $vector as map(*)*) as map(*) {
    let $both := map:merge(
        (($vector ! ?node) intersect $lucene) ! map:entry(generate-id(.), true())
    )
    return map:merge(
        for $row in $vector
        return map:entry($row?id, map { "score": $row?score, "keyword": map:contains($both, $row?id) }),
        map { "duplicates": "use-first" }
    )
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
    (: a keyword typed while exploring starts a keyword search again :)
    let $like := normalize-space(page:parameter($context, "like", ()))[. ne ""][not($q)]
    (: without a keyword there is no relevance to sort by, except in a
       "similar to" search, where relevance is nearness to the seed :)
    let $sortBy :=
        if (not($q) and not($like) and $sortByParam eq "relevance") then "date-asc"
        else if ($orderBy eq "date") then "date-asc"
        else if (not($sortByParam)) then "relevance"
        else $sortByParam
    let $section :=
        if (empty($within)) then
            if ($startDate or $volumeId) then "documents" else "entire-site"
        else
            $within
    let $modeParam := normalize-space(page:parameter($context, "mode", "keyword"))
    let $mode := if ($like) then "similar" else if ($modeParam eq "hybrid") then "hybrid" else "keyword"
    return map {
        "like": $like,
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
        let $params := map { "q": $p?q, "within": $p?within, "volume-id": $p?("volume-id"), "start-date": $p?("start-date"), "end-date": $p?("end-date"), "start-time": $p?("start-time"), "end-time": $p?("end-time"), "mode": $p?mode, "like": $p?like }
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
        else if ($p?mode eq "similar") then
            srch:similar-entry($p, $queryId)
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
                    srch:fuse-rrf(srch:sort($luceneHits, "relevance"), $vectorHits ! ?node)
                else
                    $luceneHits
            let $volIds :=
                try { map:keys(ft:facets($luceneHits, "frus-volume-id", ())) }
                catch * { () }
            return map {
                "id": $queryId, "hits": $fused, "fused": exists($vectorHits), "orders": map {},
                "semantic": srch:semantic-matches($luceneHits, $vectorHits),
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
            "semantic": $entry?semantic,
            "seed": $entry?seed,
            "took": $took,
            "range-start": $entry?("range-start"),
            "range-end": $entry?("range-end")
        }
    ))
};

(:~
 : The cache entry of a "similar to" search: the VECTOR_K hits nearest to
 : the seed hit (srch:like-seed), nearest first, without the seed itself.
 : There is no keyword leg; the section, volume and date filters apply as in
 : a hybrid search's vector leg. An unknown or unsupported seed finds
 : nothing.
 :)
declare %private function srch:similar-entry($p as map(*), $queryId as xs:string) as map(*) {
    let $seed := srch:like-seed($p?like)
    let $range := srch:date-range($p?("start-date"), $p?("end-date"), $p?("start-time"), $p?("end-time"))
    let $queryConf := srch:prepare-query($p?within, $p?("volume-id"), (), $range?start, $range?end)
    let $vec := $seed ! srch:like-vector(.)
    let $seedId := $seed ! generate-id(.)
    let $rows := if (exists($vec)) then srch:vector-neighbors($queryConf, $vec)[not(.?id = $seedId)] else ()
    return map {
        "id": $queryId, "hits": $rows ! ?node, "fused": true(), "orders": map {},
        "semantic": srch:semantic-matches((), $rows),
        "seed": $seed,
        "results-vol-ids": (),
        "range-start": $range?start, "range-end": $range?end, "created": current-dateTime()
    }
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

(:~
 : The keyword-in-context snippets of the matches in $root, at most five,
 : each wrapped in its own span so the card can hold every match to a single
 : line. A snippet shows up to $width characters before its first match and
 : after its last. A match within $width characters of the previous one is
 : highlighted in the same snippet instead of starting another, so matches
 : close together ("Star Wars or Hot Wars") don't each repeat the passage.
 :)
declare %private function srch:snippets($root as node(), $width as xs:integer) as element(span)* {
    srch:snippets-from($root, ($root//exist:match)[1], $width, 5)
};

declare %private function srch:snippets-from($root as node(), $match as element(exist:match)?,
        $width as xs:integer, $remaining as xs:integer) as element(span)* {
    if (empty($match) or $remaining le 0) then
        ()
    else
        let $run := srch:snippet-run($root, $match, $width, 0, 0, (), $match)
        return (
            <span class="hsg-snippet">{
                srch:text-before($root, $match, $width, ""),
                <span class="hi">{srch:spaces(string($match))}</span>,
                $run?content
            }</span>,
            srch:snippets-from($root, ($run?last/following::exist:match)[1], $width, $remaining - 1)
        )
};

(:~ Up to $width characters of the text before $node within $root, white
 : space collapsed, starting at a word boundary, with "..." in front when it
 : doesn't start at $root's. :)
declare %private function srch:text-before($root as node(), $node as node(), $width as xs:integer,
        $text as xs:string) as xs:string {
    let $prev := $node/preceding::text()[1]
    return
        if (string-length($text) gt $width) then
            "..." || replace(substring($text, string-length($text) - $width), "^\S*\s+", "")
        else if (empty($prev) or empty($prev/ancestor::node()[. is $root])) then
            replace($text, "^\s+", "")
        else
            srch:text-before($root, $prev, $width, srch:spaces($prev || $text))
};

(:~
 : The rest of a snippet after $node: up to $width characters of text, and
 : any match reached within them, which continues the snippet. $chars counts
 : the text since the last match, $total all of it since the snippet's first
 : match: past 2 × $width, the snippet ends and the next match starts another.
 :)
declare %private function srch:snippet-run($root as node(), $node as node(), $width as xs:integer,
        $chars as xs:integer, $total as xs:integer, $content as item()*, $last as element(exist:match)) as map(*) {
    let $next := $node/following::text()[1]
    let $match := $next/parent::exist:match
    (: counted with its white space collapsed, as it is shown :)
    let $piece := srch:spaces($next)
    return
        if (empty($next) or empty($next/ancestor::node()[. is $root])) then
            map { "content": $content, "last": $last }
        else if (exists($match)) then
            if ($total le 2 * $width) then
                srch:snippet-run($root, $match, $width, 0, $total + string-length($piece),
                    ($content, <span class="hi">{srch:spaces(string($match))}</span>), $match)
            else
                map { "content": ($content, "..."), "last": $last }
        else if ($chars + string-length($piece) gt $width) then
            (: end at a word boundary: drop a word the cut would split :)
            let $cut := replace(substring($piece, 1, $width - $chars + 1), "\s+\S*$", "")
            return map { "content": ($content, $cut, "..."), "last": $last }
        else
            srch:snippet-run($root, $next, $width, $chars + string-length($piece), $total + string-length($piece),
                ($content, $piece), $last)
};

(:~ Runs of white space, such as the source's line breaks and indentation, as one space. :)
declare %private function srch:spaces($text as xs:string?) as xs:string {
    replace($text, "\s+", " ")
};

(:~ Metadata list of a card. :)
declare %private function srch:meta-list($rows as element()*) as element(dl)? {
    if (exists($rows)) then <dl class="hsg-result__meta">{$rows}</dl> else ()
};

(:~
 : Card content for a FRUS division: the place and date chips and the
 : recorded/encoded date rows (historical documents only), the resource id,
 : and the snippets and scores. No facsimile link: search results don't
 : offer one (OP#1432, a business decision; the reference site didn't show
 : it either).
 :)
declare %private function srch:frus-card($doc as element(tei:div), $match as map(*)) as map(*) {
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
    return map {
        "tags": if ($historical) then ($placeNameString, $dateString)[. ne ""] else (),
        "summary": srch:meta-list((
            if ($historical) then (
                srch:meta-row("Recorded Date", ($dateString, "(None)")[. ne ""][1]),
                srch:meta-row("Recorded Location", ($placeNameString, "(None)")[. ne ""][1]),
                if ($date/@when) then srch:meta-row("Encoded Date", <code>when="{string($date/@when)}"</code>) else ()
            ) else (),
            srch:meta-row("Resource ID", $volId/string() || "/" || $docId/string()),
            srch:found-by-row($match),
            srch:text-row($doc, $match, 40),
            if ($match?keyword) then ft:score($doc)[boolean(.)] !srch:meta-row("Keyword Relevance", .) else (),
            srch:similarity-row($match)
        ))
    }
};

(:~
 : What one hit renders as: title and href for the card heading, plus
 : "tags" (chips above the title) and "summary" (the metadata list), both
 : empty where a hit type has nothing to show. The href trusts the hsg-url Lucene field (module doc
 : above) except for the two element types with no such field. $match says
 : which searches found the hit (see srch:hit-match).
 :)
declare %private function srch:render-hit($hit as element(), $match as map(*)) as map(*) {
    let $href := ft:field($hit, "hsg-url")
    let $card := function($title as xs:string, $rows as element()*) as map(*) {
        map { "title": $title, "href": $href, "tags": (), "summary": srch:meta-list(($rows, srch:similarity-row($match))) }
    }
    return
        typeswitch ($hit)
            case element(persName) return
                $card(string-join(($hit/forename, $hit/surname, $hit/genName), " "), srch:found-by-row($match))
            case element(visit) return
                $card("Visits By Foreign Leaders: " || string-join($hit/visitor, ", "), srch:found-by-row($match))
            case element(trips) return
                $card("Travels: " || string-join($hit/trip[1]/name, ", "), (
                    srch:found-by-row($match),
                    if ($match?keyword) then srch:meta-row("Matching Trips", srch:matching-trips($hit)) else ()
                ))
            case element(tei:div) return
                if (ft:field($hit, "hsg-publication") = "frus" or starts-with(base-uri($hit), $srch:FRUS_COL)) then
                    map:merge((map { "title": srch:frus-title($hit), "href": $href }, srch:frus-card($hit, $match)))
                else
                    $card(
                        normalize-space(string-join(($hit/tei:head)[1]//text()[not(./ancestor::tei:note)])),
                        (srch:found-by-row($match), srch:text-row($hit, $match, 60))
                    )
            case element(tei:body) return
                $card(
                    normalize-space(string-join(($hit/ancestor::tei:TEI//tei:titleStmt/tei:title)[1])),
                    (srch:found-by-row($match), srch:text-row($hit, $match, 60))
                )
            default return
                map { "title": "Untitled result", "href": "#", "tags": (), "summary": () }
};

(:~
 : Which searches found a hit: "keyword", and "semantic" with the hit's
 : similarity when the semantic search found it. "hybrid" says the page ran
 : both, so the cards say which found each hit. $semantic is the
 : srch:semantic-matches map of the search, empty for a keyword search.
 :)
declare %private function srch:hit-match($hit as element(), $semantic as map(*)?, $hybrid as xs:boolean) as map(*) {
    let $id := generate-id($hit)
    (: a cached map: read with the lookup operator, as in srch:results :)
    let $found := if (exists($semantic) and map:contains($semantic, $id)) then $semantic?($id) else ()
    return map {
        "hybrid": $hybrid,
        "keyword": empty($found) or $found?keyword,
        "semantic": $found?score
    }
};

(:~ The "Found By" row of a hybrid search's cards. :)
declare %private function srch:found-by-row($match as map(*)) as element()* {
    if ($match?hybrid) then
        srch:meta-row("Found By",
            if (exists($match?semantic) and $match?keyword) then "Keyword and semantic search"
            else if (exists($match?semantic)) then "Semantic search"
            else "Keyword search")
    else
        ()
};

(:~ The "Semantic Similarity" row: the cosine similarity of the hit's
 : embedding to the query's, for a hit the semantic search found. :)
declare %private function srch:similarity-row($match as map(*)) as element()* {
    $match?semantic ! srch:meta-row("Semantic Similarity", .)
};

(:~
 : The text row of a tei:div or tei:body hit. A keyword match shows its
 : "Keyword Results" snippets: the search queries the hsg-fulltext field, so
 : the matches are marked in the field's stored text, as for FRUS;
 : util:expand finds none. A package that doesn't store the field has no
 : snippets. A hit only the semantic search found has no matches to show,
 : so it shows the opening of its text instead (srch:opening).
 :)
declare %private function srch:text-row($hit as element(), $match as map(*), $width as xs:integer) as element()* {
    if ($match?keyword) then
        let $snippets := ft:highlight-field-matches($hit, "hsg-fulltext")[1] ! srch:snippets(., $width)
        return if (exists($snippets)) then srch:meta-row("Keyword Results", $snippets) else ()
    else
        srch:opening($hit) ! srch:meta-row("Semantic Match", .)
};

(:~
 : The opening of a hit's text, the part its semantic match is based on.
 : The packages embed each node's whole text with all-MiniLM-L6-v2, which
 : reads only the first 128 tokens, about 100 words, and ignores the rest.
 : So a semantic hit matched on its opening, whatever comes later. Shows
 : $srch:OPENING_WORDS words of it, read from no more than the first few
 : thousand characters, so a long division isn't read in full.
 :)
declare %private function srch:opening($hit as element()) as element(span)? {
    (: the heading is already the card's title, and notes aren't prose :)
    let $text := string-join(subsequence($hit//text()[not(ancestor::tei:head or ancestor::tei:note)], 1, 400))
    let $words := tokenize(normalize-space(substring($text, 1, 4000)), " ")
    return
        if (exists($words)) then
            <span class="hsg-snippet">{
                string-join(subsequence($words, 1, $srch:OPENING_WORDS), " ")
                || (if (count($words) gt $srch:OPENING_WORDS) then " ..." else ())
            }</span>
        else
            ()
};

(:~
 : How many of a travels hit's trips match. The matches are marked in the
 : stored hsg-fulltext values, one exist:field per value of the field's
 : expression in travels' index configuration, with no trip around them. The
 : same expression over the hit gives each value's trip, position by
 : position. If the counts disagree (the configuration has changed), this
 : counts matching values instead.
 :)
declare %private function srch:matching-trips($hit as element(trips)) as xs:integer {
    let $values := ft:highlight-field-matches($hit, "hsg-fulltext")
    let $sources := ($hit/trip/name, $hit/trip/country, $hit/trip/remarks, $hit/trip/locale)
    let $matching := for $value at $i in $values where $value//exist:match return $i
    return
        if (count($values) eq count($sources)) then
            count(distinct-values(for $i in $matching return generate-id($sources[$i]/parent::trip)))
        else
            count($matching)
};

(: ============== template-facing functions ============== :)

declare function srch:results-summary($context as map(*)) as element(p) {
    let $r := srch:results($context)
    return
        if ($r?("hit-count") gt 0) then
            <p class="usa-prose hsg-results-summary">
                Displaying {$r?start}&#8211;{$r?end} of <span class="search-count">{format-number($r?("hit-count"), "#,###")}</span> results
                {
                    (: a "similar to" search names the hit it started from :)
                    $r?seed ! (
                        let $seed := srch:render-hit(., map { "keyword": false() })
                        return (" most similar to ", <a href="{$context?context-path}{$seed?href}">{$seed?title}</a>, " ")
                    )
                }
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
            let $rendered := srch:render-hit($hit, srch:hit-match($hit, $r?semantic, $r?mode eq "hybrid"))
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
                        { srch:similar-link($context, $r, $hit) }
                    </div>
                </li>
        }
        </ul>
};

(:~
 : A card's "Similar documents" link: a "similar to" search from this hit,
 : keeping the current search's sections and dates, so a reader can step
 : from result to result through the semantic index. Only for the tei:div
 : and tei:body hits srch:like-seed accepts.
 :)
declare %private function srch:similar-link($context as map(*), $r as map(*), $hit as element()) as element(p)? {
    if ($hit[self::tei:div or self::tei:body] and $srch:LIKE_ROOTS = substring-before(substring-after(document-uri(root($hit)), "/db/apps/"), "/")) then
        let $query := string-join((
            "like=" || encode-for-uri(srch:like-ref($hit)),
            $r?within[not(. = ("", "entire-site"))] ! ("within=" || encode-for-uri(.)),
            $r?("start-date")[. ne ""] ! ("start-date=" || .),
            $r?("end-date")[. ne ""] ! ("end-date=" || .)
        ), "&amp;")
        return
            <p class="hsg-result__actions">
                <a class="hsg-result__similar" href="{$context?context-path}/search?{$query}">Similar documents</a>
            </p>
    else
        ()
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
        if ($r?mode eq "hybrid") then "mode=hybrid" else (),
        $r?like ! ("like=" || encode-for-uri(.))
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
            {
                (: keeps a "similar to" search when the filters or sort change;
                   ignored once a keyword is entered (srch:read-params) :)
                normalize-space(page:parameter($context, "like", ()))[. ne ""] !
                    <input type="hidden" name="like" value="{.}" form="hsg-search"/>
            }
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

(: ============== similar documents (FRUS document pages) ============== :)

(:~ Cache of each FRUS document's similar documents, as plain strings: the
 : list depends only on the index, so it is kept an hour after its last use.
 : pre-install.xql destroys it, as $srch:CACHE. :)
declare variable $srch:SIMILAR_CACHE as xs:string := "hsg-similar";
declare variable $srch:SIMILAR_CACHE_CONFIG as map(*) := map {
    "expireAfterAccess": 3600000,
    "maximumSize": 5000
};

(:~ How many similar documents a document page lists. :)
declare variable $srch:SIMILAR_COUNT as xs:integer := 8;

(:~ How many candidates the panel asks the vector index for, before keeping
 : the SIMILAR_COUNT nearest. Lucene's HNSW search explores only about k
 : candidates, so asking for 12 missed better matches: on a FRUS sample, k=5
 : kept 1 of the true top 5 for 2 of 10 queries, while k=100 cost no
 : measurable time (6 to 10 ms either way). :)
declare variable $srch:SIMILAR_CANDIDATES as xs:integer := 100;

(:~
 : The "Similar documents" panel of a FRUS document page, for the sidebar
 : (srch:similar-loader). It loads after the page, through
 : GET /api/similar/{publicationId}/{divisionId}, because finding the
 : neighbors resolves the FRUS collection, which can take a moment.
 :)
declare function srch:similar-loader($context as map(*)) as element()? {
    let $div := ($context?doc?content//tei:text//tei:div[@xml:id])[1]
    let $publicationId := replace(document-uri(root($div)), "^.*/frus-v2-data/([^/]+)/.*$", "$1")
    return
        if ($div and $publicationId ne document-uri(root($div))
            and starts-with(normalize-space(($context?doc?content//tei:bibl[@type='frus-division-type'])[1]), "document")) then
            <pb-load class="hsg-similar-loader" url="api/similar/{$publicationId}/{$div/@xml:id}" auto="auto"/>
        else
            ()
};

(:~
 : The documents whose embeddings are nearest a FRUS document's, across all
 : of FRUS: documents only, so title-only chapters and front matter don't
 : crowd them out. Each is a map of strings (href, title, volume, date,
 : score), so the cache holds no nodes.
 :)
declare %private function srch:similar-documents($publicationId as xs:string, $divisionId as xs:string) as map(*)* {
    let $key := $publicationId || "/" || $divisionId
    let $create := cache:create($srch:SIMILAR_CACHE, $srch:SIMILAR_CACHE_CONFIG)
    let $cached := cache:get($srch:SIMILAR_CACHE, $key)
    return
        if (exists($cached)) then
            (: an empty list is cached as an empty array :)
            $cached?*
        else
            let $seed := collection($srch:FRUS_COL || "/data/frus-v2-data/" || $publicationId)/id($divisionId)[self::tei:div]
            let $vec := $seed[1] ! srch:like-vector(.)
            let $opts := map { "facets": map { "frus-division-type": "document" } }
            let $hits :=
                if (exists($vec)) then
                    try { collection($srch:FRUS_COL)//tei:div[ft:query-vector(., $vec, $srch:SIMILAR_CANDIDATES, $opts)] } catch * { () }
                else
                    ()
            let $list := subsequence(
                for $hit in $hits[not(. is $seed[1])]
                let $score := ft:score($hit)
                order by $score descending
                return map {
                    "href": string(ft:field($hit, "hsg-url")),
                    "title": srch:frus-title($hit),
                    "volume": srch:volume-label(replace(document-uri(root($hit)), "^.*/frus-v2-data/([^/]+)/.*$", "$1")),
                    "date": normalize-space(string-join((($hit//tei:dateline[.//tei:date])[1]//tei:date)[1]//text()[not(ancestor::tei:note)])),
                    "score": $score
                },
                1, $srch:SIMILAR_COUNT)
            let $store := if (exists($seed)) then cache:put($srch:SIMILAR_CACHE, $key, array { $list }) else ()
            return $list
};

(:~ The panel GET /api/similar/{publicationId}/{divisionId} returns. :)
declare function srch:similar-panel($contextPath as xs:string, $publicationId as xs:string, $divisionId as xs:string) as element()? {
    if (not(matches($publicationId, "^[A-Za-z0-9._-]+$") and matches($divisionId, "^[A-Za-z0-9._-]+$"))) then
        ()
    else
        let $similar := srch:similar-documents($publicationId, $divisionId)
        let $seed := collection($srch:FRUS_COL || "/data/frus-v2-data/" || $publicationId)/id($divisionId)[self::tei:div][1]
        return
            if (empty($similar)) then
                ()
            else
                <section class="hsg-similar" aria-labelledby="hsg-similar-heading">
                    <h2 class="hsg-similar__heading" id="hsg-similar-heading">Similar documents</h2>
                    <ol class="usa-list usa-list--unstyled hsg-similar__list">
                    {
                        for $doc in $similar
                        return
                            <li class="hsg-similar__item">
                                <a href="{$contextPath}{$doc?href}">{$doc?title}</a>
                                <span class="hsg-similar__meta">{
                                    string-join(($doc?volume, $doc?date)[. ne ""], " · ")
                                }</span>
                            </li>
                    }
                    </ol>
                    {
                        $seed ! <p class="hsg-similar__more"><a href="{$contextPath}/search?like={encode-for-uri(srch:like-ref(.))}&amp;within=documents">Explore similar documents</a></p>
                    }
                </section>
};
