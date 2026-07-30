xquery version "3.1";

module namespace searchapi = "https://history.state.gov/api/search";

import module namespace vapi = "http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace errors = "http://e-editiones.org/roaster/errors";
import module namespace query-guard = "http://history.state.gov/ns/site/hsg/query-guard" at "query-guard.xqm";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : technique as hsgapi:handle-error / dhapi:handle-error.
 :)
declare namespace router = "http://e-editiones.org/roaster/router";

(:~
 : Error code for a query rejected by the query guard (SQL-injection shape, or
 : total `q` length over 1000 chars). Not one of roaster's own $errors:*
 : constants -- searchapi:handle-error below maps it to HTTP 400 itself, the
 : same way hsgapi:handle-error maps $errors:NOT_FOUND to 404.
 :)
declare variable $searchapi:BAD_REQUEST as xs:QName := xs:QName("searchapi:bad-request");

(:~
 : GET /search -- single route, two page shapes (OP#1102 / OP#1179). Folds
 : over q/start-date/end-date exactly like hsg-shell's controller.xql: if any
 : of the three is non-empty after normalize-space (a whitespace-only q does
 : NOT count, and a repeated parameter counts if ANY of its values is
 : non-empty), render the results template, otherwise the landing form.
 : within/volume-id/sort-by alone never trigger the results view.
 :
 : The query guard runs on the RAW request parameter (request:get-parameter,
 : not roaster's schema-coerced $request?parameters?q) so a repeated `q` is
 : checked the same way hsg-shell's query-guard:check($q as xs:string*) always
 : was, independent of how roaster's OpenAPI-declared (scalar) schema for `q`
 : happens to coerce repeats.
 :)
declare function searchapi:search($request as map(*)) {
    let $rawQ := request:get-parameter("q", ())
    return
        if (query-guard:check($rawQ)) then
            error($searchapi:BAD_REQUEST, "search query rejected by query guard")
        else
            let $showResults :=
                some $name in ("q", "start-date", "end-date")
                satisfies (
                    some $value in request:get-parameter($name, ())
                    satisfies normalize-space($value) ne ""
                )
            let $file := if ($showResults) then "pages/search/results" else "pages/search/landing"
            return
                vapi:html(map:merge((
                    $request,
                    map {
                        "parameters": map:merge((
                            $request?parameters,
                            map {
                                "file": $file,
                                "suppress-sitewide-search-field": "true"
                            }
                        ))
                    }
                )))
};

(:~
 : GET /search/tips -- static help page, no backing document. Any other child
 : of /search (e.g. /search/foo) is not declared here and falls through to
 : Roaster's own unmatched-route 404, matching #1182's own note.
 :)
declare function searchapi:tips($request as map(*)) {
    vapi:html(map:merge((
        $request,
        map {
            "parameters": map:merge((
                $request?parameters,
                map { "file": "pages/search/tips" }
            ))
        }
    )))
};

(:~
 : GET /search/{other} -- explicit catch for any child of /search other than
 : /search/tips. Without this, jinks' own generic /{docid} route (allowReserved
 : path param, matches any otherwise-unrouted path) would intercept it and its
 : unwrapped vapi:handle-error would hardcode HTTP 200 -- confirmed live during
 : implementation of OP#1102, the same gap the departmenthistory section has
 : today for its own unrouted children (out of scope to fix there).
 :)
declare function searchapi:not-found($request as map(*)) {
    error($errors:NOT_FOUND, "no route below /search/" || $request?parameters?other)
};

(:~
 : Wrap the jinks-owned vapi:handle-error (renders the error page but
 : hardcodes HTTP 200) to correct the status code -- same pattern as
 : hsgapi:handle-error / dhapi:handle-error / countryapi:handle-error.
 :)
declare function searchapi:handle-error($error as map(*)) {
    let $response := vapi:handle-error($error)
    return
        if ($error?code eq $errors:NOT_FOUND) then
            map:put($response, xs:QName("router:RESPONSE_CODE"), 404)
        else if ($error?code eq $searchapi:BAD_REQUEST) then
            map:put($response, xs:QName("router:RESPONSE_CODE"), 400)
        else
            $response
};
