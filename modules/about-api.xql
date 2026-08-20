xquery version "3.1";

module namespace aboutapi="http://teipublisher.com/api/about";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace about="https://history.state.gov/ns/templates/about" at "templates/about.xqm";
import module namespace hsg-errors="https://history.state.gov/ns/site/hsg/errors" at "hsg-errors.xqm";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : approach as hsgapi:handle-error / dhapi:handle-error.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

(:~
 : The five hand-authored pages (index, contact-us, the-historian,
 : recent-publications, reports, content-warning) have no backing document --
 : publication-id "app" in hsg-shell -- so every one of them renders through
 : vapi:html with a fixed template, same technique as hsgapi:view-section and
 : dhapi:render.
 :)
declare %private function aboutapi:render($request as map(*), $file as xs:string) {
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

declare function aboutapi:index($request as map(*)) {
    aboutapi:render($request, "pages/about/index")
};

declare function aboutapi:contact-us($request as map(*)) {
    aboutapi:render($request, "pages/about/contact-us")
};

declare function aboutapi:the-historian($request as map(*)) {
    aboutapi:render($request, "pages/about/the-historian")
};

declare function aboutapi:reports($request as map(*)) {
    aboutapi:render($request, "pages/about/reports")
};

declare function aboutapi:content-warning($request as map(*)) {
    aboutapi:render($request, "pages/about/content-warning")
};

(:~
 : Not actually static despite hsg-shell's publication-id "app": the page's
 : body is a live cross-collection listing over the historicaldocuments/FRUS
 : collection (about:recent-publications). Still a fixed template with no
 : document to resolve, so vapi:html applies exactly as for the other four
 : static pages -- the bespoke part is inside the template's own model, not
 : the route.
 :)
declare function aboutapi:recent-publications($request as map(*)) {
    aboutapi:render($request, "pages/about/recent-publications")
};

(:~
 : FAQ and HAC (#1153) are single-file TEI monographs with exactly one
 : document per publication in hsg-shell's $config:PUBLICATIONS map, so the
 : document id is a fixed route segment ('faq'/'hac'), not a path parameter --
 : the handler passes it as a synthesized "publication" request parameter,
 : mirroring dhapi:monograph-toc (built for Short History/Buildings, the same
 : single-file-monograph shape).
 :)
declare %private function aboutapi:monograph-toc($request as map(*), $publication as xs:string) {
    vapi:html(map:put($request, "parameters", map:merge((
        $request?parameters,
        map {
            "file": "pages/about/monograph-toc",
            "publication": $publication
        }
    ))))
};

declare function aboutapi:view-faq($request as map(*)) {
    aboutapi:monograph-toc($request, "faq")
};

declare function aboutapi:view-hac($request as map(*)) {
    aboutapi:monograph-toc($request, "hac")
};

(:~
 : Interior page for one FAQ/HAC division (#1154). Same guard as
 : hsgapi:is-exact-division / dhapi:monograph-section: id()/xml:id lookups
 : tokenize on whitespace, so anything that does not resolve to exactly one
 : division is a 404, not a silently wrong page. HAC's meeting-notes
 : subchapter ids are inconsistently cased in the live data ('March-2025' vs
 : 'december-1996') -- resolved by exact xml:id match, no casing
 : normalization applied.
 :)
declare %private function aboutapi:monograph-section($request as map(*), $publication as xs:string) {
    let $sectionId := $request?parameters?sectionId
    let $doc := about:monograph-doc($publication)
    let $division := about:monograph-division($doc, $sectionId)
    return
        if (count($division) ne 1) then
            error($errors:NOT_FOUND, "no section " || $sectionId || " in " || $publication)
        else
            vapi:html(map:put($request, "parameters", map:merge((
                $request?parameters,
                map {
                    "file": "pages/about/monograph-section",
                    "publication": $publication
                }
            ))))
};

declare function aboutapi:view-faq-section($request as map(*)) {
    aboutapi:monograph-section($request, "faq")
};

declare function aboutapi:view-hac-section($request as map(*)) {
    aboutapi:monograph-section($request, "hac")
};

(:~
 : Wrap the jinks-owned vapi:handle-error, which renders the error page but
 : hardcodes HTTP 200, so a missing page still reports success to crawlers
 : and link checkers. Keep its markup, correct the status. Same pattern as
 : hsgapi:handle-error / dhapi:handle-error / countryapi:handle-error.
 :)
declare function aboutapi:handle-error($error as map(*)) {
    (: Central status mapping + themed 404/400 pages: OP#1309. :)
    hsg-errors:handle($error)
};
