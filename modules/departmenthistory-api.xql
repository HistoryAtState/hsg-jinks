xquery version "3.1";

module namespace dhapi="http://teipublisher.com/api/departmenthistory";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace dh="https://history.state.gov/ns/templates/departmenthistory" at "templates/departmenthistory.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

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
 : The four film ids the old controller enumerated (#1146's rework note): a
 : fixed literal whitelist, not a collection scan -- there is no data
 : collection backing these pages, they are four hand-authored templates.
 :)
declare variable $dhapi:COURIER_FILMS := (
    "through-the-khyber-pass", "behind-the-iron-curtain", "into-moscow", "before-the-jet-age"
);

declare function dhapi:courier-film($request as map(*)) {
    let $filmId := $request?parameters?filmId
    return
        if (not($filmId = $dhapi:COURIER_FILMS)) then
            error($errors:NOT_FOUND, "no diplomatic courier film " || $filmId)
        else
            dhapi:render($request, "pages/departmenthistory-courier-" || $filmId)
};

declare %private function dhapi:monograph-toc($request as map(*), $publication as xs:string) {
    vapi:html(map:merge((
        $request,
        map {
            "parameters": map:merge((
                $request?parameters,
                map {
                    "file": "pages/departmenthistory-monograph-toc",
                    "publication": $publication
                }
            ))
        }
    )))
};

declare function dhapi:short-history($request as map(*)) {
    dhapi:monograph-toc($request, "short-history")
};

declare function dhapi:buildings($request as map(*)) {
    dhapi:monograph-toc($request, "buildings")
};

(:~
 : Short History and Buildings (#1135) are single-file monographs -- every
 : chapter/subchapter lives in the one document, so unlike
 : hsgapi:view-interior there is no per-division file to resolve a docid to.
 : Locate the division by @xml:id directly and pass it as a template
 : parameter; the template hands it to page:transform itself (see
 : dh:monograph-doc / dh:monograph-divisions).
 :)
declare %private function dhapi:monograph-section($request as map(*), $publication as xs:string) {
    let $sectionId := $request?parameters?sectionId
    let $doc := dh:monograph-doc($publication)
    let $division := dh:monograph-division($doc, $sectionId)
    return
        if (count($division) ne 1) then
            error($errors:NOT_FOUND, "no section " || $sectionId || " in " || $publication)
        else
            vapi:html(map:merge((
                $request,
                map {
                    "parameters": map:merge((
                        $request?parameters,
                        map {
                            "file": "pages/departmenthistory-monograph-section",
                            "publication": $publication,
                            "sectionId": $sectionId
                        }
                    ))
                }
            )))
};

declare function dhapi:short-history-section($request as map(*)) {
    dhapi:monograph-section($request, "short-history")
};

declare function dhapi:buildings-section($request as map(*)) {
    dhapi:monograph-section($request, "buildings")
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
