xquery version "3.1";

module namespace dhapi="http://teipublisher.com/api/departmenthistory";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace errors="http://e-editiones.org/roaster/errors";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : approach as hsgapi:handle-error / countryapi:handle-error.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

(:~
 : This phase of the section (hub pages + static articles) has no backing
 : document for any route, so every operation renders through vapi:html with a
 : fixed template -- same technique as hsgapi:view-section and every
 : countryapi:index/list/archives-index/archives-list operation.
 :)
declare %private function dhapi:render($request as map(*), $file as xs:string) {
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

declare function dhapi:index($request as map(*)) {
    dhapi:render($request, "pages/departmenthistory")
};

declare function dhapi:people($request as map(*)) {
    dhapi:render($request, "pages/departmenthistory-people")
};

declare function dhapi:chiefs($request as map(*)) {
    dhapi:render($request, "pages/departmenthistory-chiefsofmission")
};

declare function dhapi:principals-chiefs($request as map(*)) {
    dhapi:render($request, "pages/departmenthistory-principals-chiefs")
};

declare function dhapi:travels($request as map(*)) {
    dhapi:render($request, "pages/departmenthistory-travels")
};

declare function dhapi:couriers($request as map(*)) {
    dhapi:render($request, "pages/departmenthistory-couriers")
};

declare function dhapi:marine-corps($request as map(*)) {
    dhapi:render($request, "pages/departmenthistory-marine-corps")
};

declare function dhapi:wwi($request as map(*)) {
    dhapi:render($request, "pages/departmenthistory-wwi")
};

(:~
 : Wrap the jinks-owned vapi:handle-error, which renders the error page but
 : hardcodes HTTP 200, so a missing page still reports success to crawlers and
 : link checkers. Keep its markup, correct the status. Same as
 : hsgapi:handle-error / countryapi:handle-error.
 :)
declare function dhapi:handle-error($error as map(*)) {
    let $response := vapi:handle-error($error)
    return
        if ($error?code eq $errors:NOT_FOUND) then
            map:put($response, xs:QName("router:RESPONSE_CODE"), 404)
        else
            $response
};
