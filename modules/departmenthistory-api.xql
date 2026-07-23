xquery version "3.1";

module namespace dhapi="http://teipublisher.com/api/departmenthistory";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
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
 : Phase 2 pilot (#1136): the first POCOM record-backed route. Renders
 : through vapi:html like the static pages -- dh:secretaries computes the
 : list directly, there is no ODD transform involved.
 :)
declare function dhapi:secretaries($request as map(*)) {
    dhapi:render($request, "pages/departmenthistory-secretaries")
};

(:~
 : A 302 with a Location header, built by hand from the same raw
 : router:RESPONSE_* QNames dhapi:handle-error already uses to rewrite a
 : status code -- roaster.xqm's own roaster:response($code, $media-type,
 : $body, $headers) constructor isn't imported here (nothing else in this
 : module needs it), so this mirrors what it builds rather than pulling in
 : the whole module for one call. Confirmed against roaster 1.9's
 : router.xql: router:write-response reads RESPONSE_CODE, sets
 : RESPONSE_HEADERS via response:set-header, then serializes RESPONSE_BODY
 : under RESPONSE_TYPE -- an empty string body with a text/html type is a
 : normal, empty redirect response.
 :)
declare %private function dhapi:redirect($url as xs:string) as map(*) {
    map {
        xs:QName("router:RESPONSE_CODE"): 302,
        xs:QName("router:RESPONSE_HEADERS"): map { "Location": $url },
        xs:QName("router:RESPONSE_TYPE"): "text/html",
        xs:QName("router:RESPONSE_BODY"): ""
    }
};

(:~
 : #1141. Three outcomes: the id resolves to a real person -> render;
 : the id is a recorded old-id -> 302 to the canonical id (60 old-ids on the
 : devcontainer's data, per collection(...)/person[old-ids] -- ticket says
 : 63, another instance-divergence case like #1136's, not re-litigated
 : here); neither -> 404. dh:person-has-bio
 : (checked again inside the template) decides the biography-vs-record-only
 : layout; this handler only resolves which person is being requested.
 :)
declare function dhapi:person($request as map(*)) {
    let $personId := $request?parameters?personId
    return
        if (exists(dh:person-doc($personId))) then
            dhapi:render($request, "pages/departmenthistory-person")
        else
            let $canonical := dh:person-canonical-id-for-old-id($personId)
            return
                if (exists($canonical)) then
                    dhapi:redirect($config:context-path || "/departmenthistory/people/" || $canonical)
                else
                    error($errors:NOT_FOUND, "no person " || $personId)
};

declare function dhapi:people-by-name($request as map(*)) {
    dhapi:render($request, "pages/departmenthistory-people-by-name")
};

(:~
 : Rework note (#1137): the old site's letter route raises a raw
 : collection-not-found error (400) on an id outside a-z; validate against
 : dh:people-letters (only letters that actually have people) and 404
 : instead, the same normalization #1134/#1135 already did for unknown
 : section ids.
 :)
declare function dhapi:people-by-name-letter($request as map(*)) {
    let $letter := $request?parameters?letter
    return
        if (not($letter = dh:people-letters())) then
            error($errors:NOT_FOUND, "no people starting with letter " || $letter)
        else
            dhapi:render($request, "pages/departmenthistory-people-by-name-letter")
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
