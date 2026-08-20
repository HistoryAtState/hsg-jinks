xquery version "3.1";

module namespace tagapi="http://teipublisher.com/api/tags";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace tags="https://history.state.gov/ns/templates/tags" at "templates/tags.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : approach as hsgapi:handle-error / dhapi:handle-error.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

(:~
 : Cross-cutting section (#1101): every page aggregates the taxonomy registry
 : against tag assignments carried by other sections' content (FRUS volumes,
 : Secretary biographies), so there is no per-page backing document to hand
 : vapi:view -- every operation renders through vapi:html with a fixed
 : template, same technique as hsgapi:view-section / dhapi:render.
 :)
declare %private function tagapi:render($request as map(*), $file as xs:string) {
    vapi:html(map:put($request, "parameters", map:merge((
        $request?parameters,
        map { "file": $file }
    ))))
};

declare function tagapi:index($request as map(*)) {
    tagapi:render($request, "pages/tags/index")
};

declare function tagapi:all($request as map(*)) {
    tagapi:render($request, "pages/tags/all")
};

declare function tagapi:view($request as map(*)) {
    let $tagId := $request?parameters?tagId
    return
        if (empty(tags:taxonomy-entry($tagId))) then
            error($errors:NOT_FOUND, "no taxonomy entry " || $tagId)
        else
            tagapi:render($request, "pages/tags/browse")
};
