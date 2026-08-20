xquery version "3.1";

module namespace ogapi="http://teipublisher.com/api/open";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace hsg-errors="https://history.state.gov/ns/site/hsg/errors" at "hsg-errors.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : approach as hsgapi:handle-error / devapi:handle-error / dhapi:handle-error.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

(:~
 : The three explainer pages (hsg-shell's publication-id "app") have no
 : backing document -- same technique as hsgapi:view-section / devapi:render.
 :)
declare %private function ogapi:render($request as map(*), $file as xs:string) {
    vapi:html(map:put($request, "parameters", map:merge((
        $request?parameters,
        map { "file": $file }
    ))))
};

declare function ogapi:index($request as map(*)) {
    ogapi:render($request, "pages/open/index")
};

declare function ogapi:frus-latest-page($request as map(*)) {
    ogapi:render($request, "pages/open/frus-latest")
};

declare function ogapi:frus-metadata-page($request as map(*)) {
    ogapi:render($request, "pages/open/frus-metadata")
};

(:~
 : Published/partially-published volumes, most recently published first.
 :
 : Ported from hsg-shell's own unreleased rewrite of open:frus-latest() /
 : open:frus-metadata() (modules/open.xql on the hsg-shell source tree,
 : not the currently deployed version) which already queries the TEI
 : volume collection directly rather than the separate hand-maintained
 : "bibliography" collection the deployed app still reads -- see OP#1197
 : ("Data Transformation"). That collection does not exist in this app's
 : data package (hsg-jinks-data ships volumes as TEI only), so this is the
 : only workable data source here, not just the preferred one.
 :
 : Unlike the ported source, external-location/length are looked up in the
 : TEI namespace (tei:external-location, tei:length/tei:span): the TEI
 : root declares that as its default element namespace, so unprefixed
 : lookups (as the ported source uses) would only ever match no-namespace
 : elements -- consistent with the epic's own finding that this WIP
 : rewrite doesn't yet work against real data. Today's sample volume has
 : neither element, so both are simply omitted; that already degrades
 : gracefully once real data provides them.
 :)
declare %private function ogapi:published-volumes() as element(tei:TEI)* {
    for $revisionDesc in collection($config:data-default)//tei:revisionDesc[@status = ("published", "partially-published")]
    let $volume := $revisionDesc/root(.)/tei:TEI
    let $when := $revisionDesc/tei:change[@corresp eq "#" || $volume/@xml:id]/@when
    order by $when descending
    return $volume
};

declare %private function ogapi:volume-editors($volume as element(tei:TEI)) as xs:string? {
    let $primary := $volume//tei:editor[@role = "primary"]
    let $general := $volume//tei:editor[@role = "general"]
    return
        string-join((
            if (count($primary) gt 1) then
                "Editors: " || string-join($primary/string(), ", ") || "."
            else if (count($primary) eq 1) then
                "Editor: " || $primary || "."
            else (),
            if ($general) then "General Editor: " || $general[1]/string() else ()
        ), " ")
};

(:~
 : Atom 1.0 feed of the most recently published volumes. Verified against
 : hsg-shell: served as text/xml, not application/atom+xml -- a
 : third-party contract (catalog.data.gov), preserved as observed rather
 : than "corrected". See OP#1195.
 :)
declare function ogapi:frus-latest-feed($request as map(*)) {
    let $n := $request?parameters?n
    let $volumes := subsequence(ogapi:published-volumes(), 1, $n)
    let $author := "Office of the Historian, Shared Knowledge Services, Bureau of Administration, United States Department of State"
    let $rights := "Pursuant to federal law, government-produced materials appearing on this site are not copyright protected."
    let $entries :=
        for $volume in $volumes
            let $vol-id := string($volume/@xml:id)
            let $volume-title := normalize-space($volume//tei:title[@type = "complete"])
            let $published-date := string($volume//tei:revisionDesc/tei:change[@corresp eq "#" || $vol-id]/@when)
            let $editors := ogapi:volume-editors($volume)
            let $link := $config:context-path || "/historicaldocuments/" || $vol-id
            return
                <entry xmlns="http://www.w3.org/2005/Atom">
                    <title>{$volume-title}</title>
                    <id>{$link}</id>
                    <link type="text/html" href="{$link}"/>
                    <author><name>{$author}</name></author>
                    <published>{$published-date}</published>
                    <updated>{$published-date}</updated>
                    <rights>{$rights}</rights>
                    <summary>{
                        normalize-space("Published " || $published-date || (if ($editors) then ". " || $editors else "") || ".")
                    }</summary>
                </entry>
    let $latest := $volumes[1]
    let $latest-id := string($latest/@xml:id)
    let $feed-updated := if ($latest) then string($latest//tei:revisionDesc/tei:change[@corresp eq "#" || $latest-id]/@when) else string(current-dateTime())
    let $feed :=
        <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Foreign Relations of the United States: Latest Volumes</title>
            <subtitle>The {$n} most recently published volumes in the Foreign Relations of the United States series, sorted by year of publication.</subtitle>
            <link href="{$config:context-path || '/open/frus-latest.xml'}" rel="self"/>
            <id>http://history.state.gov/atom/frus-metadata-v1</id>
            <updated>{$feed-updated}</updated>
            <author><name>{$author}</name></author>
            {$entries}
        </feed>
    (: Content-Type comes from the spec's declared "text/xml" (no explicit
     : override here): router:write-response derives BOTH the header and
     : the serialization method from the same string, and only recognizes
     : a bare ".../xml" suffix -- passing "text/xml;charset=utf-8" through
     : roaster:response defeats that match, silently falling back to plain
     : text serialization (all markup stripped, verified by testing this).
     : The old app served exactly "text/xml;charset=utf-8"; this is
     : "text/xml" only, a minor, library-forced deviation. :)
    return $feed
};

(:~
 : Bulk XML dump of FRUS volume bibliographic metadata. Verified against
 : hsg-shell: served as text/xml, custom "http://history.state.gov/ns/1.0"
 : vocabulary. See OP#1196.
 :)
declare function ogapi:frus-metadata-feed($request as map(*)) {
    let $volumes :=
        for $volume in ogapi:published-volumes()
            let $vol-id := string($volume/@xml:id)
            let $titles := $volume//tei:title[. ne ""]
            let $locations := $volume/tei:external-location[. ne ''][./@loc = ("db", "madison", "worldcat")]
            let $media := $volume//tei:keywords[@scheme eq "#frus-media-type"]/tei:term/string()
            let $published-year := substring($volume//tei:revisionDesc/tei:change[@corresp eq "#" || $vol-id]/@when, 1, 4)
            let $coverage := string($volume//tei:publicationStmt/tei:date[@type eq "content-date"])
            let $lengths := $volume/tei:length/tei:span[. ne '']
            order by $vol-id
            return
                <volume xmlns="http://history.state.gov/ns/1.0" id="{$vol-id}">
                    {
                        for $title in $titles return element title { $title/@*, $title/text() },
                        for $location in $locations return
                            if ($location/@loc = ("madison", "worldcat")) then
                                <external-location loc="{$location/@loc}">{$location/text()}</external-location>
                            else
                                <external-location loc="db">{$config:context-path || "/historicaldocuments/" || $location}</external-location>
                        ,
                        <media>{$media}</media>,
                        <published>{$published-year}</published>,
                        <coverage>{$coverage}</coverage>,
                        if ($lengths) then
                            <length>{for $length in $lengths return element span { $length/@*, $length/text() }}</length>
                        else ()
                    }
                </volume>
    let $dump :=
        <volumes xmlns="http://history.state.gov/ns/1.0">
            {comment {
                "Dump of FRUS Volume Metadata" ||
                "&#10;Report Last Updated: " || string(current-dateTime())
            }}
            {$volumes}
        </volumes>
    (: See ogapi:frus-latest-feed: content type is the spec's bare
     : "text/xml", not an explicit ";charset=utf-8" override, because
     : roaster's own content-type-to-serialization-method mapping only
     : recognizes the bare suffix. :)
    return $dump
};

(:~
 : Neither explainer page nor either feed takes a path parameter, so any
 : other segment under /open (e.g. /open/foo) has no page to serve --
 : hsg-shell's own controller.xql falls through to
 : local:serve-not-found-page() for exactly this case. Without this route,
 : Roaster's own path-matching regex has no end anchor for static segments,
 : so this lower-specificity bare route would win by default and silently
 : render the landing page with a 200. Same pattern as devapi:not-found.
 :)
declare function ogapi:not-found($request as map(*)) {
    error($errors:NOT_FOUND, "no page " || $request?parameters?page || " under /open")
};

(:~
 : Wrap the jinks-owned vapi:handle-error, which renders the error page but
 : hardcodes HTTP 200, so a missing page still reports success to crawlers
 : and link checkers. Keep its markup, correct the status. Same pattern as
 : hsgapi:handle-error / devapi:handle-error / dhapi:handle-error /
 : countryapi:handle-error.
 :
 : Also maps err:FORG0001 to 400: roaster's own parameters:cast-value casts
 : query parameters with an unguarded xs:integer($value) when the OpenAPI
 : schema declares type "integer" -- verified by testing frus-latest.xml
 : with a non-integer "n": the cast throws err:FORG0001 (Roaster's own
 : try/catch in router:route rethrows it with the same code), which is the
 : exact same unguarded-cast bug OP#1191 flagged in the old app, just moved
 : into the library. Declaring the schema type alone does not give a clean
 : 4xx for free, so this handler has to do it, same trick as the NOT_FOUND
 : mapping below.
 :)
declare function ogapi:handle-error($error as map(*)) {
    (: Central status mapping + themed 404/400 pages: OP#1309. :)
    hsg-errors:handle($error)
};
