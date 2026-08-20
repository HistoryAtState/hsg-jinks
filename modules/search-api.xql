xquery version "3.1";

module namespace searchapi = "https://history.state.gov/api/search";

import module namespace vapi = "http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace errors = "http://e-editiones.org/roaster/errors";
import module namespace query-guard = "http://history.state.gov/ns/site/hsg/query-guard" at "query-guard.xqm";
import module namespace srch = "https://history.state.gov/ns/templates/search" at "templates/search.xqm";
import module namespace hsg-errors="https://history.state.gov/ns/site/hsg/errors" at "hsg-errors.xqm";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : technique as hsgapi:handle-error / dhapi:handle-error.
 :)
declare namespace router = "http://e-editiones.org/roaster/router";

(:~
 : GET /search -- single route, two page shapes (OP#1102 / OP#1179). Folds
 : over q/start-date/end-date: if any of the three is non-empty after
 : normalize-space (a whitespace-only q does NOT count), render the results
 : template, otherwise the landing form. within/volume-id/sort-by alone never
 : trigger the results view.
 :)
declare function searchapi:search($request as map(*)) {
    if (query-guard:check($request?parameters?q)) then
        (: roaster's own 400 code: hsg-errors:handle maps it to the invalid-search page (OP#1273/#1309) :)
        error($errors:BAD_REQUEST, "search query rejected by query guard")
    else if (not(srch:query-parses(string-join($request?parameters?q, " ")))) then
        (: malformed Lucene syntax, e.g. an unbalanced quote (OP#1273) :)
        error($errors:BAD_REQUEST, "malformed search query syntax")
    else
        let $showResults :=
            some $name in ("q", "start-date", "end-date")
            satisfies normalize-space($request?parameters?($name)) ne ""
        let $file := if ($showResults) then "pages/search/results" else "pages/search/landing"
        return
            (: map:put, not an outer map:merge((`$request`, map{"parameters": ...})):
               both operands would carry a "parameters" key, and map:merge's default
               "use-first" duplicate policy silently keeps $request's original
               (unmerged) "parameters" map, discarding this function's own. map:put
               has no such ambiguity -- it always overwrites the single named key. :)
            vapi:html(map:put($request, "parameters", map:merge((
                $request?parameters,
                map {
                    "file": $file,
                    "suppress-sitewide-search-field": "true"
                }
            ))))
};

(:~
 : GET /search/tips -- static help page, no backing document. Any other child
 : of /search (e.g. /search/foo) is not declared here and falls through to
 : Roaster's own unmatched-route 404, matching #1182's own note.
 :)
declare function searchapi:tips($request as map(*)) {
    vapi:html(map:put($request, "parameters", map:merge((
        $request?parameters,
        map { "file": "pages/search/tips" }
    ))))
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
 : hardcodes HTTP 200) to correct the status code -- same base pattern as
 : hsgapi:handle-error / dhapi:handle-error / countryapi:handle-error, but
 : those three all fall through to the unmodified (200) response for any
 : error code they don't explicitly recognize -- meaning a genuine,
 : unanticipated runtime error would silently render as a 200 "success"
 : page. Fixed here: anything that isn't a recognized NOT_FOUND/BAD_REQUEST
 : is a real server-side failure, not a client-facing 404/400, so it maps to
 : 500 instead of passing the hardcoded 200 through.
 :)
declare function searchapi:handle-error($error as map(*)) {
    (: Central status mapping + themed 404/400 pages: OP#1309. :)
    hsg-errors:handle($error)
};
