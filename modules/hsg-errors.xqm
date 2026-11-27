xquery version "3.1";

(:~
 : Site-wide error pages (OP#1309), reference parity with hsg-shell's
 : error-page-404.xml / error-page-400.xml / error-page.xml: a friendly
 : themed page per error class, with the correct HTTP status.
 :
 : Every section api module's x-error-handler wrapper delegates here, so the
 : status mapping and template choice live in one place: 404 for roaster's
 : NOT_FOUND, 400 for BAD_REQUEST, and the friendly generic error page for any
 : other error class (real 500s). A 400 gets the invalid-search page when its
 : value is $hsg-errors:SEARCH (the search query guard, OP#1273), the generic
 : invalid-request page otherwise. The 404/400/500 pages deliberately show no
 : internals, like the reference. Public error responses never include
 : exception details.
 :
 : Handlers that answer with an error page themselves (the catch-all routes,
 : the search query guard) call hsg-errors:handle directly instead of raising:
 : Roaster logs every raised error at ERROR level (eeditiones/roaster#183).
 :)
module namespace hsg-errors="https://history.state.gov/ns/site/hsg/errors";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace tmpl="http://e-editiones.org/xquery/templates";
import module namespace pc = "http://history.state.gov/ns/site/hsg/precompiled-templates" at "precompile.xqm";
import module namespace roaster="http://e-editiones.org/roaster";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : technique as the former per-module handlers.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

(:~ The error value marking a 400 from the search query guard. :)
declare variable $hsg-errors:SEARCH := map { "page": "search" };

declare function hsg-errors:handle($error as map(*)) {
    (: Roaster 2.1 raises BAD_REQUEST for a query parameter it cannot cast to
       its declared type (e.g. a non-integer n); Roaster 1 let the plain cast
       error FORG0001 through. Both get the 400 status with the generic
       invalid-request page: the jinks-owned diagnostics page exposes
       internals. :)
    let $status :=
        if ($error?code eq $errors:NOT_FOUND) then 404
        else if ($error?code eq $errors:BAD_REQUEST) then 400
        else if (local-name-from-QName($error?code) eq "FORG0001") then 400
        else 500
    let $file :=
        if ($status = 404) then "error-404.html"
        else if ($status = 400 and hsg-errors:is-search($error)) then "error-400.html"
        else if ($status = 400) then "error-request.html"
        (: a real 500 (an uncaught dynamic error, a bug elsewhere in the
           app, ...): friendly page, not the diagnostic one -- end users
           should not see a stack trace in production. :)
        else "error-500.html"
    return
        hsg-errors:render($error, $file, $status)
};

declare %private function hsg-errors:is-search($error as map(*)) as xs:boolean {
    $error?value instance of map(*) and $error?value?page = "search"
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
        pc:process($template, $model, map {
            "plainText": false(),
            "resolver": vapi:resolver#1,
            "modules": map {
                "http://www.tei-c.org/tei-simple/config": map {
                    "prefix": "config",
                    "at": "modules/config.xqm"
                },
                (: templates/layouts/base.html (extended by the friendly error
                   pages, OP#1398, to reuse the real site header/nav/footer
                   instead of a bare standalone page) calls
                   page:resolve-language($context). Declared explicitly here
                   rather than via ignoreImports=false, because that flag also
                   controls the site-wide "use" block library and every
                   ancestor template's own frontmatter modules -- more than
                   these pages need. :)
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
