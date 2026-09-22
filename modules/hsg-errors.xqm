xquery version "3.1";

(:~
 : Site-wide error pages (OP#1309), reference parity with hsg-shell's
 : error-page-404.xml / error-page-400.xml / error-page.xml: a friendly
 : themed page per error class, with the correct HTTP status.
 :
 : Every section api module's x-error-handler wrapper delegates here, so the
 : status mapping and template choice live in one place: 404 for roaster's
 : NOT_FOUND, 400 for BAD_REQUEST (the search query guard, OP#1273), and the
 : jinks-owned generic error page (which carries the diagnostic details) for
 : everything else. The generic page keeps vapi:handle-error's rendering; the
 : 404/400 pages deliberately show no internals, like the reference.
 :)
module namespace hsg-errors="https://history.state.gov/ns/site/hsg/errors";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace tmpl="http://e-editiones.org/xquery/templates";
import module namespace roaster="http://e-editiones.org/roaster";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : technique as the former per-module handlers.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

declare function hsg-errors:handle($error as map(*)) {
    (: FORG0001 is roaster's own parameters:cast-value failing on a query
       parameter whose OpenAPI schema declares a numeric type (e.g. a
       non-integer n) -- a client error, but not one of roaster's $errors:*
       QNames. It gets the 400 status with the diagnostics body (the friendly
       400 page's invalid-search copy would be wrong for it), the same
       mapping the per-section handlers carried before delegating here. :)
    let $status :=
        if ($error?code eq $errors:NOT_FOUND) then 404
        else if ($error?code eq $errors:BAD_REQUEST) then 400
        else if (local-name-from-QName($error?code) eq "FORG0001") then 400
        else 500
    return
        if ($error?code = ($errors:NOT_FOUND, $errors:BAD_REQUEST)) then
            hsg-errors:render($error, "error-" || $status || ".html", $status)
        else
            (: the jinks-owned generic page renders the diagnostics; only the
               status needs correcting (it hardcodes 200) :)
            map:put(vapi:handle-error($error), xs:QName("router:RESPONSE_CODE"), $status)
};

(:~
 : Render one of the friendly error templates: same pipeline as the
 : jinks-owned vapi:handle-error, with the template path parameterized and
 : the response status set from the error class.
 :)
declare %private function hsg-errors:render($error as map(*), $file as xs:string, $status as xs:integer) {
    let $path := $config:app-root || "/templates/" || $file
    let $template :=
        if (doc-available($path)) then
            doc($path) => serialize()
        else
            util:binary-doc($path) => util:binary-to-string()
    let $model := map:merge((
        vapi:load-config-json($error),
        map {
            "type": $error?code,
            "description": $error?description,
            "context-path": $config:context-path
        }
    ))
    let $html :=
        tmpl:process($template, $model, map {
            "plainText": false(),
            "resolver": vapi:resolver#1,
            "modules": map {
                "http://www.tei-c.org/tei-simple/config": map {
                    "prefix": "config",
                    "at": "modules/config.xqm"
                },
                (: templates/layouts/base.html (extended by the 404 page, OP#1398,
                   to reuse the real site header/nav/footer instead of a bare
                   standalone page) calls page:resolve-language($context).
                   Declared explicitly here rather than via ignoreImports=false,
                   because that flag also controls the site-wide "use" block
                   library and every ancestor template's own frontmatter
                   modules -- more than this page needs. :)
                "http://teipublisher.com/ns/templates/page": map {
                    "prefix": "page",
                    "at": "modules/templates/page.xqm"
                }
            },
            "ignoreImports": true(),
            "ignoreUse": true()
        })
    return
        map:put(roaster:response(200, "text/html", $html), xs:QName("router:RESPONSE_CODE"), $status)
};
