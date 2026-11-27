xquery version "3.1";

(:~
 : Last-Modified and 304 Not Modified for the page routes (OP#1471).
 :
 : lm:use is a Roaster middleware (guarded by mw:guard in modules/lib/api.xql)
 : for the page routes. It answers a conditional request (If-Modified-Since)
 : that is not older with 304 through the shared middleware signal, without
 : calling the handler, and otherwise adds a Last-Modified date to the
 : response. Roaster merges that header into the handler's response; an error
 : the handler raises is answered without it.
 :
 : The date is the same for every page: the latest of the app's own package
 : date and the package dates of all data packages the app reads. A page can
 : draw on any of them (every section module imports hsg.xqm, and templates
 : may call any module listed in config.json), so a narrower date could miss a
 : change. A package date is the commit time in its repo.xml, which a release
 : build fills in; without one, the time repo.xml was stored, i.e. the install.
 :)
module namespace lm="https://history.state.gov/ns/site/hsg/last-modified";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace roaster="http://e-editiones.org/roaster";
import module namespace mw="https://history.state.gov/ns/site/hsg/middleware" at "middleware.xqm";

declare namespace repo="http://exist-db.org/xquery/repo";
declare namespace router="http://e-editiones.org/roaster/router";

(: the data packages below /db/apps the app reads :)
declare variable $lm:PACKAGES := (
    "carousel", "conferences", "frus-history", "frus-tei", "gsh", "hac", "milestones",
    "other-publications", "pocom", "rdcr", "tags", "travels", "visits", "wwdai"
);

(: the API modules whose routes serve pages; their not-found handlers are excluded :)
declare variable $lm:PAGE_APIS := (
    "aboutapi", "confapi", "countryapi", "dhapi", "devapi", "eduapi", "hsgapi",
    "milapi", "ogapi", "searchapi", "tagapi"
);

declare variable $lm:EPOCH := xs:dateTime("1970-01-01T00:00:00Z");

(: the key roaster reads a response map's headers from; roaster.xqm does not re-export it :)
declare variable $lm:RESPONSE_HEADERS := xs:QName("router:RESPONSE_HEADERS");

declare function lm:use($request as map(*), $response as map(*)) as map(*)+ {
    let $lastModified :=
        if (lm:is-page-route($request?config?operationId)) then lm:site-last-modified() else ()
    let $since := lm:if-modified-since()
    return
        if (empty($lastModified)) then
            ($request, $response)
        else if (exists($since) and $lastModified le $since) then (
            mw:answer($request, roaster:response(304, (), (), map { "Last-Modified": lm:http-date($lastModified) })),
            $response
        ) else (
            $request,
            map:put($response, $lm:RESPONSE_HEADERS, map:merge((
                $response($lm:RESPONSE_HEADERS),
                map { "Last-Modified": lm:http-date($lastModified) }
            )))
        )
};

declare function lm:is-page-route($operationId as xs:string) as xs:boolean {
    substring-before($operationId, ":") = $lm:PAGE_APIS
    and substring-after($operationId, ":") ne "not-found"
};

(:~
 : The latest package date of the app and its data packages, to the second:
 : HTTP dates carry no fractions, so If-Modified-Since compares in seconds.
 :)
declare function lm:site-last-modified() as xs:dateTime? {
    let $dates := (
        lm:package-date($config:app-root),
        for $package in $lm:PACKAGES
        return lm:package-date("/db/apps/" || $package)
    )
    return
        if (empty($dates)) then
            ()
        else
            max($dates)
            => adjust-dateTime-to-timezone(xs:dayTimeDuration("PT0H"))
            => format-dateTime("[Y0001]-[M01]-[D01]T[H01]:[m01]:[s01]Z")
            => xs:dateTime()
};

declare function lm:package-date($root as xs:string) as xs:dateTime? {
    if (doc-available($root || "/repo.xml")) then
        let $commitTime := doc($root || "/repo.xml")/repo:meta/@commit-time[. castable as xs:integer]
        return
            if (exists($commitTime)) then
                $lm:EPOCH + xs:dayTimeDuration("PT" || $commitTime || "S")
            else
                xmldb:last-modified($root, "repo.xml")
    else
        ()
};

declare %private function lm:if-modified-since() as xs:dateTime? {
    let $header := request:get-header("If-Modified-Since")
    return
        if (empty($header)) then () else try { parse-ietf-date($header) } catch * { () }
};

declare function lm:http-date($dateTime as xs:dateTime) as xs:string {
    $dateTime
    => adjust-dateTime-to-timezone(xs:dayTimeDuration("PT0H"))
    => format-dateTime("[FNn,*-3], [D01] [MNn,*-3] [Y0001] [H01]:[m01]:[s01] GMT", "en", (), ())
};
