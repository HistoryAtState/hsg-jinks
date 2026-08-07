xquery version "3.1";

module namespace devapi="http://teipublisher.com/api/developer";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace errors="http://e-editiones.org/roaster/errors";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : approach as hsgapi:handle-error / dhapi:handle-error / aboutapi:handle-error.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

(:~
 : Both pages (hsg-shell's publication-id "app") have no backing document --
 : same technique as hsgapi:view-section / aboutapi:render.
 :)
declare %private function devapi:render($request as map(*), $file as xs:string) {
    vapi:html(map:merge((
        $request,
        map {
            "parameters": map:merge((
                $request?parameters,
                map { "file": $file }
            ))
        }
    )))
};

declare function devapi:index($request as map(*)) {
    devapi:render($request, "pages/developer/index")
};

declare function devapi:catalog($request as map(*)) {
    devapi:render($request, "pages/developer/catalog")
};

(:~
 : Neither of the two real pages takes a path parameter, so any other
 : segment under /developer (e.g. /developer/foo) has no page to serve --
 : hsg-shell's own controller.xql falls through to
 : local:serve-not-found-page() for exactly this case. Without this route,
 : Roaster's own path-matching regex has no end anchor for static segments
 : ("/developer" normalizes to "^/developer", which prefix-matches
 : "/developer/foo" too), and that lower-specificity bare route would win by
 : default and silently render the landing page with a 200. Declaring this
 : parameterized catch-all raises the specificity of any two-segment
 : /developer/* path above the bare route, so it wins the match instead and
 : always 404s -- the "catalog" segment is still routed to devapi:catalog
 : first since that literal route has higher specificity still.
 :)
declare function devapi:not-found($request as map(*)) {
    error($errors:NOT_FOUND, "no page " || $request?parameters?page || " under /developer")
};

(:~
 : Wrap the jinks-owned vapi:handle-error, which renders the error page but
 : hardcodes HTTP 200, so a missing page still reports success to crawlers
 : and link checkers. Keep its markup, correct the status. Same pattern as
 : hsgapi:handle-error / dhapi:handle-error / countryapi:handle-error /
 : aboutapi:handle-error.
 :)
declare function devapi:handle-error($error as map(*)) {
    let $response := vapi:handle-error($error)
    return
        if ($error?code eq $errors:NOT_FOUND) then
            map:put($response, xs:QName("router:RESPONSE_CODE"), 404)
        else
            $response
};
