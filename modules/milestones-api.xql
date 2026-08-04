xquery version "3.1";

module namespace milapi="http://teipublisher.com/api/milestones";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace ms="https://history.state.gov/ns/templates/milestones" at "templates/milestones.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : approach as hsgapi:handle-error / dhapi:handle-error / countryapi:handle-error.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

(:~
 : Index and all-listing have no document of their own -- same technique as
 : hsgapi:view-section and every dhapi:render call.
 :)
declare %private function milapi:render($request as map(*), $file as xs:string) {
    (: map:put, not an outer map:merge((`$request`, map{"parameters": ...})): both
       operands would carry a "parameters" key, and map:merge's default
       "use-first" duplicate policy silently keeps $request's original
       (unmerged) "parameters" map, discarding this function's own. map:put
       has no such ambiguity -- it always overwrites the single named key. :)
    vapi:html(map:put($request, "parameters", map:merge((
        $request?parameters,
        map { "file": $file }
    ))))
};

declare function milapi:index($request as map(*)) {
    milapi:render($request, "pages/milestones/index")
};

declare function milapi:all($request as map(*)) {
    milapi:render($request, "pages/milestones/all")
};

(:~
 : Era landing page (table of contents only). Eras are one-TEI-file-per-era,
 : like departmenthistory's single-file monographs -- unlike
 : hsgapi:view-interior's per-division files -- so the era is located by
 : @xml:id / filename directly rather than resolved via vapi:view's whole
 : document lookup. Unknown eraId: ms:era-doc returns the empty sequence
 : (doc-available guarded), which the 404 check below catches.
 :)
declare function milapi:view($request as map(*)) {
    let $eraId := $request?parameters?eraId
    let $doc := ms:era-doc($eraId)
    return
        if (empty($doc)) then
            error($errors:NOT_FOUND, "no era " || $eraId)
        else
            vapi:html(map:put($request, "parameters", map:merge((
                $request?parameters,
                map { "file": "pages/milestones/view" }
            ))))
};

(:~
 : Article page. Resolves articleId against the era doc directly (not via
 : id(), since -- unlike hsgapi:view-interior's collection() lookup -- the
 : era doc is already known and articleId is scoped to just that one
 : document); same exact-count guard reasoning as
 : hsgapi:is-exact-division / dhapi:monograph-section: anything other than
 : exactly one division whose xml:id equals the requested id is a miss. An
 : unknown eraId already yields an empty $doc, so $division is empty too --
 : one guard covers both "unknown era" and "unknown article" (#1166).
 :)
declare function milapi:view-section($request as map(*)) {
    let $eraId := $request?parameters?eraId
    let $articleId := $request?parameters?articleId
    let $doc := ms:era-doc($eraId)
    let $division := ms:era-divisions($doc)[@xml:id = $articleId]
    return
        if (count($division) ne 1) then
            error($errors:NOT_FOUND, "no article " || $articleId || " in era " || $eraId)
        else
            vapi:html(map:put($request, "parameters", map:merge((
                $request?parameters,
                map { "file": "pages/milestones/view-section" }
            ))))
};

(:~
 : Wrap the jinks-owned vapi:handle-error, which renders the error page but
 : hardcodes HTTP 200, so a missing page (or any other failure) still reports
 : success to crawlers and link checkers. Keep its markup, correct the
 : status for every error type via roaster's own
 : errors:get-status-code-from-error (not just NOT_FOUND -> 404), so a real
 : bug reports 500 instead of silently succeeding.
 :)
declare function milapi:handle-error($error as map(*)) {
    let $response := vapi:handle-error($error)
    return map:put($response, xs:QName("router:RESPONSE_CODE"), errors:get-status-code-from-error($error?code))
};
