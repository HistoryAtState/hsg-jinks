xquery version "3.1";

module namespace countryapi="http://teipublisher.com/api/countries";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace errors="http://e-editiones.org/roaster/errors";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : approach as hsgapi:handle-error / dhapi:handle-error.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

declare variable $countryapi:RDCR_ARTICLES := "/db/apps/rdcr/articles";
declare variable $countryapi:WWDAI_ARTICLES := "/db/apps/wwdai/articles";

declare %private function countryapi:render($request as map(*), $file as xs:string) {
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

declare function countryapi:index($request as map(*)) {
    countryapi:render($request, "pages/countries/index")
};

declare function countryapi:list($request as map(*)) {
    countryapi:render($request, "pages/countries/all")
};

declare function countryapi:archives-index($request as map(*)) {
    countryapi:render($request, "pages/countries/archives/index")
};

declare function countryapi:archives-list($request as map(*)) {
    countryapi:render($request, "pages/countries/archives/all")
};

(:~
 : docid is an absolute db path into the foreign rdcr collection --
 : config:get-document() resolves absolute paths via plain doc() regardless
 : of which app owns the collection, the same technique used for FRUS
 : volumes (hsgapi:view) but pointed outside this app's own data root.
 : Unknown ids fail that lookup and vapi:view's existing NOT_FOUND path
 : already answers 404 -- no separate guard needed here.
 :)
declare function countryapi:view($request as map(*)) {
    let $countryId := $request?parameters?countryId
    return
        vapi:view(map:put($request, "parameters", map:merge((
            $request?parameters,
            map { "docid": $countryapi:RDCR_ARTICLES || "/" || $countryId || ".xml" }
        ))))
};

declare function countryapi:archives-view($request as map(*)) {
    let $archiveId := $request?parameters?archiveId
    return
        vapi:view(map:put($request, "parameters", map:merge((
            $request?parameters,
            map { "docid": $countryapi:WWDAI_ARTICLES || "/" || $archiveId || ".xml" }
        ))))
};
