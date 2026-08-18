xquery version "3.1";

module namespace eduapi="http://teipublisher.com/api/education";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace edu="https://history.state.gov/ns/templates/education" at "templates/education.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : approach as hsgapi:handle-error / countryapi:handle-error / dhapi:handle-error.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

(:~
 : /education and /education/modules have no backing document -- both render
 : through vapi:html with a fixed template, same technique as
 : dhapi:index/dhapi:people.
 :)
declare %private function eduapi:render($request as map(*), $file as xs:string) {
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

declare function eduapi:index($request as map(*)) {
    eduapi:render($request, "pages/education/index")
};

declare function eduapi:modules($request as map(*)) {
    eduapi:render($request, "pages/education/modules")
};

(:~
 : Renders through vapi:html with a fixed template, not vapi:view+docid:
 : with $context?doc truthy, a vapi:view route's default hsg-content.html
 : breadcrumb block wins over module.html's own [% template breadcrumb %]
 : override in this templating engine (confirmed live) -- the same reason
 : every departmenthistory TEI page (monograph sections included) uses
 : vapi:html with content re-resolved from request parameters instead of
 : vapi:view. The moduleId 404 guard happens here, one level before any
 : template rendering: the in-preparation module has an empty
 : tei-document-name, so it can never be reached this way, and an unknown
 : moduleId fails the record lookup directly.
 :)
declare function eduapi:view-module($request as map(*)) {
    let $moduleId := $request?parameters?moduleId
    let $module := edu:module-by-tei-document-name($moduleId)
    return
        if (empty($module)) then
            error($errors:NOT_FOUND, "no published education module " || $moduleId)
        else
            eduapi:render($request, "pages/education/module")
};

(:~
 : Wraps vapi:handle-error to correct its hardcoded 200 to 404 for
 : errors:NOT_FOUND -- vapi:handle-error itself always returns 200.
 : Identical pattern to hsgapi:handle-error / countryapi:handle-error /
 : dhapi:handle-error.
 :)
declare function eduapi:handle-error($error as map(*)) {
    let $response := vapi:handle-error($error)
    return
        if ($error?code eq $errors:NOT_FOUND) then
            map:put($response, xs:QName("router:RESPONSE_CODE"), 404)
        else
            $response
};
