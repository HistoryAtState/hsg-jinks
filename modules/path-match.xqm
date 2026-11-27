xquery version "3.1";

(:~
 : Middleware for request paths that do not equal their route (OP#1527).
 :
 : Roaster 1.x anchors route patterns at the start only, so /about also
 : matched /about/anything and served the About page with 200. Such paths
 : are answered with 404, using the end anchor Roaster 2.1.1 added (route
 : regex + "/?$"), so that check does nothing once the router anchors
 : patterns itself. A path ending in a slash, or containing repeated
 : slashes, is redirected permanently (301) to the same path without them,
 : as on the live site (hsg-shell's controller.xql strips both).
 :
 : Both answers go through the shared middleware signal (middleware.xqm), so
 : neither runs the handler or is logged as an error.
 :)
module namespace path-match="https://history.state.gov/ns/site/hsg/path-match";

import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace roaster="http://e-editiones.org/roaster";
import module namespace mw="https://history.state.gov/ns/site/hsg/middleware" at "middleware.xqm";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";

declare function path-match:use($request as map(*), $response as map(*)) as map(*)+ {
    let $path := $request?path
    let $normalized := path-match:normalize($path)
    return (
        if ($normalized ne $path) then
            mw:answer($request, roaster:response(301, "text/plain", (), map { "Location": path-match:location($normalized) }))
        else if (not(matches($path, path-match:anchored($request?regex)))) then
            mw:fail($request, map { "code": $errors:NOT_FOUND, "description": "No route matches " || $path })
        else
            $request,
        $response
    )
};

(:~ Repeated slashes collapsed, the trailing slash removed; the root stays "/". :)
declare %private function path-match:normalize($path as xs:string) as xs:string {
    let $collapsed := replace($path, "/{2,}", "/")
    return
        if ($collapsed ne "/" and ends-with($collapsed, "/")) then
            substring($collapsed, 1, string-length($collapsed) - 1)
        else
            $collapsed
};

declare %private function path-match:location($path as xs:string) as xs:string {
    let $query := request:get-query-string()
    return $config:context-path || $path || (if ($query) then "?" || $query else ())
};

(: Roaster 2.1.1 already ends its route regexes with "/?$" :)
declare %private function path-match:anchored($regex as xs:string) as xs:string {
    if (ends-with($regex, "$")) then $regex else $regex || "/?$"
};
