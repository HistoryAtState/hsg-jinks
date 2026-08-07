xquery version "3.1";

module namespace confapi="http://teipublisher.com/api/conferences";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace conf="https://history.state.gov/ns/templates/conferences" at "templates/conferences.xqm";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : approach as hsgapi:handle-error / countryapi:handle-error / dhapi:handle-error.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

(:~
 : Landing page for the Conferences section: a list of all conferences.
 :
 : No document of its own, so it renders through vapi:html rather than
 : vapi:view -- same technique as hsgapi:view-section / dhapi:render.
 :)
declare function confapi:index($request as map(*)) {
    vapi:html(map:merge((
        $request,
        map {
            "parameters": map:merge((
                $request?parameters,
                map { "file": "pages/conferences/index" }
            ))
        }
    )))
};

(:~
 : Landing page for one conference: full document view.
 :
 : Conferences are single monolithic TEI documents (no xinclude-split
 : divisions), so unlike hsgapi:view there is no per-document docid whose
 : whole-document load through vapi:view is the only content needed --
 : rendering the whole tei:body plus a TOC/conference-list sidebar needs
 : more than vapi:view's doc.content model provides. Same technique as
 : dhapi:monograph-toc: resolve/guard server-side, pass plain request
 : parameters through vapi:html, let the template call back into conf:* for
 : content.
 :)
declare function confapi:view($request as map(*)) {
    let $conferenceId := $request?parameters?conferenceId
    let $doc := conf:conference-doc($conferenceId)
    return
        if (empty($doc)) then
            error($errors:NOT_FOUND, "no conference " || $conferenceId)
        else
            vapi:html(map:merge((
                $request,
                map {
                    "parameters": map:merge((
                        $request?parameters,
                        map { "file": "pages/conferences/conference" }
                    ))
                }
            )))
};

(:~
 : Interior page for one division (tei:div) of a conference.
 :
 : Unlike hsgapi:view-interior, conference divisions are not xincluded into
 : their own file -- all of a conference's divisions live in one document,
 : so there is no per-division file to resolve a docid to. Locate the
 : division by @xml:id directly (guarding the same id()-whitespace-
 : tokenization pitfall as hsgapi:is-exact-division) and pass conferenceId/
 : sectionId as template parameters; the template hands the division to
 : page:transform itself via conf:section-content. Same technique as
 : dhapi:monograph-section.
 :)
declare function confapi:view-section($request as map(*)) {
    let $conferenceId := $request?parameters?conferenceId
    let $sectionId := $request?parameters?sectionId
    let $doc := conf:conference-doc($conferenceId)
    let $division := conf:division($doc, $sectionId)
    return
        if (not(confapi:is-exact-division($division, $sectionId))) then
            error($errors:NOT_FOUND, "no division " || $sectionId || " in " || $conferenceId)
        else
            vapi:html(map:merge((
                $request,
                map {
                    "parameters": map:merge((
                        $request?parameters,
                        map { "file": "pages/conferences/section" }
                    ))
                }
            )))
};

(:~
 : Whether id() resolved to exactly the requested division. Same guard as
 : hsgapi:is-exact-division: id() tokenizes its argument on whitespace, so
 : "d1 d3" resolves to two elements and "d1 " to one -- guard against both.
 : This also covers an unknown conferenceId, since $division is then empty
 : (conf:conference-doc returns () and conf:division on an empty document
 : returns no nodes).
 :)
declare function confapi:is-exact-division($division as node()*, $sectionId as xs:string) as xs:boolean {
    count($division) eq 1 and $division/@xml:id = $sectionId
};

(:~
 : Wrap the jinks-owned vapi:handle-error, which renders the error page but
 : hardcodes HTTP 200, so a missing page still reports success to crawlers
 : and link checkers. Keep its markup, correct the status. Same as
 : hsgapi:handle-error / countryapi:handle-error / dhapi:handle-error.
 :)
declare function confapi:handle-error($error as map(*)) {
    let $response := vapi:handle-error($error)
    return
        if ($error?code eq $errors:NOT_FOUND) then
            map:put($response, xs:QName("router:RESPONSE_CODE"), 404)
        else
            $response
};
