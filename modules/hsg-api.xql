xquery version "3.1";

module namespace hsgapi="http://teipublisher.com/api/hsg";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace hsg="https://history.state.gov/ns/templates/hsg" at "templates/hsg.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

(:~
 : Render a page that has no backing document of its own through vapi:html;
 : same idiom as devapi:render / aboutapi:render. The template name is fixed
 : by the caller instead of being declared as a parameter, so it cannot be
 : steered from the query string.
 :)
declare %private function hsgapi:render($request as map(*), $file as xs:string) {
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

(:~
 : Landing page for the Historical Documents section: the presidential
 : administrations grid.
 :
 : Without this route the path falls through to the jinks-owned catch-all
 : /{docid}, which treats "historicaldocuments" as a document id and errors --
 : yet the breadcrumb links here from every content page.
 :)
declare function hsgapi:view-section($request as map(*)) {
    hsgapi:render($request, "pages/historicaldocuments/index")
};

(:~
 : Section pages under /historicaldocuments (OP#1291-#1295, #1299-#1305). Their literal
 : routes beat the parameterized /historicaldocuments/{publicationId} volume
 : route by Roaster path specificity; see the note on devapi:not-found in
 : developer-api.xql.
 :)
(:~
 : Shared renderer for the data-driven statics (OP#1313, PR #50 review):
 : one template, pages/historicaldocuments/content-page.html, fed the page
 : id; the template derives breadcrumb label (menu.{page-id} i18n key with
 : the content document's own title as fallback) and content from it.
 :)
declare %private function hsgapi:content-page($request as map(*), $page as xs:string) {
    vapi:html(
        map:put($request, "parameters", map:merge((
            $request?parameters,
            map { "file": "pages/historicaldocuments/content-page" }
        ))),
        map { "page-id": $page }
    )
};

declare function hsgapi:about-frus($request as map(*)) {
    hsgapi:content-page($request, "about-frus")
};

declare function hsgapi:citing-frus($request as map(*)) {
    hsgapi:content-page($request, "citing-frus")
};

declare function hsgapi:pre-1861($request as map(*)) {
    hsgapi:content-page($request, "pre-1861")
};

declare function hsgapi:other-electronic-resources($request as map(*)) {
    hsgapi:content-page($request, "other-electronic-resources")
};

declare function hsgapi:vietnam-guide($request as map(*)) {
    hsgapi:render($request, "pages/historicaldocuments/vietnam-guide")
};

(:~
 : The pre-1861 Serial Set subsection (OP#1303-#1305), backed by the
 : other-publications data package's serial-set document; rendering helpers
 : in modules/templates/serial-set.xqm. The browse route's region/subject
 : query parameters reach the template through the request map.
 :)
declare function hsgapi:serial-set($request as map(*)) {
    hsgapi:render($request, "pages/historicaldocuments/pre-1861/serial-set")
};

declare function hsgapi:serial-set-all($request as map(*)) {
    hsgapi:render($request, "pages/historicaldocuments/pre-1861/serial-set/all")
};

declare function hsgapi:serial-set-browse($request as map(*)) {
    hsgapi:render($request, "pages/historicaldocuments/pre-1861/serial-set/browse")
};

declare function hsgapi:status-of-the-series($request as map(*)) {
    hsgapi:render($request, "pages/historicaldocuments/status-of-the-series")
};

declare function hsgapi:frus-history($request as map(*)) {
    hsgapi:render($request, "pages/historicaldocuments/frus-history")
};

declare function hsgapi:ebooks($request as map(*)) {
    hsgapi:render($request, "pages/historicaldocuments/ebooks")
};

declare function hsgapi:quarterly-releases($request as map(*)) {
    hsgapi:render($request, "pages/historicaldocuments/quarterly-releases")
};

(:~
 : The ten quarterly-release announcement pages (OP#1295). Content is frozen
 : upstream (the digitization partnership's last release was 2018-q4), so each
 : announcement is a verbatim-ported static template and the id vocabulary is
 : a closed list; anything else is a real 404, not hsg-shell's error-page
 : fallthrough (precedent: #1130/#1166). The announcements deliberately do not
 : appear in the section sidebar, matching the reference's section-nav
 : exclusion (hsg-shell urls.xml).
 :)
declare variable $hsgapi:quarterly-release-ids :=
    ("2016-q3", "2016-q4", "2017-q1", "2017-q2", "2017-q3", "2017-q4",
     "2018-q1", "2018-q2", "2018-q3", "2018-q4");

declare function hsgapi:quarterly-release($request as map(*)) {
    let $releaseId := $request?parameters?releaseId
    return
        if ($releaseId = $hsgapi:quarterly-release-ids) then
            (: One template for all announcements since OP#1313; the content
               documents live in data/content/quarterly-releases/. :)
            vapi:html(
                map:put($request, "parameters", map:merge((
                    $request?parameters,
                    map { "file": "pages/historicaldocuments/quarterly-release" }
                ))),
                map { "release-id": $releaseId }
            )
        else
            error($errors:NOT_FOUND, "no quarterly release announcement " || $releaseId)
};

(:~
 : The FRUS History subsection (OP#1294), backed by the frus-history data
 : package (/db/apps/frus-history). The monograph landing page is the
 : frus-history route above; the fixed-segment sub-routes (documents,
 : research, events, appendix-a) beat the {sectionId} catch-all by Roaster
 : path specificity. Unknown ids 404 server-side, per the section's pattern.
 :)
declare variable $hsgapi:frus-history-root := "/db/apps/frus-history";

declare function hsgapi:frus-history-documents($request as map(*)) {
    hsgapi:render($request, "pages/historicaldocuments/frus-history/documents")
};

declare function hsgapi:frus-history-document($request as map(*)) {
    let $documentId := $request?parameters?documentId
    return
        if (doc-available($hsgapi:frus-history-root || "/documents/" || $documentId || ".xml")) then
            vapi:html(
                map:put($request, "parameters", map:merge((
                    $request?parameters,
                    map { "file": "pages/historicaldocuments/frus-history/document" }
                ))),
                map { "document-id": $documentId }
            )
        else
            error($errors:NOT_FOUND, "no frus-history document " || $documentId)
};

declare function hsgapi:frus-history-research($request as map(*)) {
    hsgapi:render($request, "pages/historicaldocuments/frus-history/research")
};

declare function hsgapi:frus-history-article($request as map(*)) {
    let $articleId := $request?parameters?articleId
    return
        if (doc-available($hsgapi:frus-history-root || "/articles/" || $articleId || ".xml")) then
            vapi:html(
                map:put($request, "parameters", map:merge((
                    $request?parameters,
                    map { "file": "pages/historicaldocuments/frus-history/article" }
                ))),
                map { "article-id": $articleId }
            )
        else
            error($errors:NOT_FOUND, "no frus-history article " || $articleId)
};

declare function hsgapi:frus-history-events($request as map(*)) {
    hsgapi:render($request, "pages/historicaldocuments/frus-history/events")
};

declare function hsgapi:frus-history-appendix-a($request as map(*)) {
    hsgapi:render($request, "pages/historicaldocuments/frus-history/appendix-a")
};

declare function hsgapi:frus-history-section($request as map(*)) {
    let $sectionId := $request?parameters?sectionId
    let $division := doc($hsgapi:frus-history-root || "/monograph/frus-history.xml")/id($sectionId)
    return
        if (count($division) eq 1 and $division instance of element(tei:div)
                and $division/@xml:id = $sectionId) then
            vapi:html(
                map:put($request, "parameters", map:merge((
                    $request?parameters,
                    map { "file": "pages/historicaldocuments/frus-history/section" }
                ))),
                map { "section-id": $sectionId }
            )
        else
            error($errors:NOT_FOUND, "no monograph division " || $sectionId || " in frus-history")
};

(:~
 : /historicaldocuments/{publicationId} serves two kinds of page from one
 : path, the same split hsg-shell's controller made: an administration
 : landing page when the id is a slug in the administrations taxonomy
 : (lincoln, nixon-ford, cleveland-22, ...), otherwise a volume. Volumes all
 : start with "frus" and no administration slug does, so the vocabularies
 : cannot collide; unknown ids fall through to the volume branch and 404
 : there.
 :
 : The stub routes above are literal paths and beat this parameterized one by
 : Roaster path specificity, so their slugs never reach this dispatch.
 :)
declare function hsgapi:view($request as map(*)) {
    let $publicationId := $request?parameters?publicationId
    let $_ := util:log("INFO", "publicationId: " || $publicationId)
    return
        if (exists(hsg:administration($publicationId))) then
            vapi:html(
                map:put($request, "parameters", map:merge((
                    $request?parameters,
                    map { "file": "pages/historicaldocuments/administration" }
                ))),
                map { "administration-id": $publicationId }
            )
        else
            vapi:view(map:put($request, "parameters", map:merge((
                $request?parameters,
                map {
                    "docid": $config:frus-volumes || "/" || $publicationId || "/" || $publicationId || ".xml"
                }
            ))))
};

declare function hsgapi:view-interior($request as map(*)) {
    let $publicationId := $request?parameters?publicationId
    let $divisionId := $request?parameters?divisionId
    let $_ := util:log("INFO", "publicationId: " || $publicationId || " divisionId: " || $divisionId)
    let $doc := collection($config:data-default || "/" || $publicationId)/id($divisionId)
        [not(self::tei:divGen)]
        (: The volume root marks where the printed TOC goes with
           <divGen xml:id="toc"/>, so id("toc") resolves both that
           placeholder and the real front-matter division (OP#1306);
           only the division has a page. :)
    return
        if (not(hsgapi:is-exact-division($doc, $divisionId))) then
            (: id() tokenizes its argument on whitespace, so "d1 d3" resolves to two
               elements and "d1 " to one -- the first crashed root($doc) with a raw
               XPTY0004 and the second served d1's page under a second URL. Anything
               that is not exactly one element whose xml:id is the requested id is a
               miss. :)
            error($errors:NOT_FOUND, "no division " || $divisionId || " in " || $publicationId)
        else if (hsgapi:is-attachment($doc)) then
            (: Attachments have no page of their own: they are rendered inline in
               the document that xincludes them, and the reference site 404s their
               URL. The data disagrees -- each carries a relatedItem type="canonical"
               advertising this very URL -- but the reference site is authoritative
               here. Their notes belong to the parent's consolidated footnote list,
               so a standalone page could not render them anyway. :)
            error($errors:NOT_FOUND, "division " || $divisionId || " is an attachment of "
                || hsgapi:attachment-parent($doc) || " and has no page of its own")
        else if (hsgapi:is-pending($doc)) then
            (: A division of an anticipated (uncleared) volume: the v2 data
               ships chapter-title scaffolding with frus-division-type
               'chapter-pending'/'section-pending' before publication.
               hsg-shell 404'd interior divs of volumes not at least
               partially published (its config.xqm select-section); per
               division here, same contract (OP#1337). :)
            error($errors:NOT_FOUND, "division " || $divisionId || " of "
                || $publicationId || " is not yet published")
        else
            vapi:view(map:put($request, "parameters", map:merge((
                $request?parameters,
                map {
                    "docid": substring-after(document-uri(root($doc)), $config:data-root || '/')
                }
            ))))
};

(:~
 : Whether a division is unpublished scaffolding: its per-division TEI header
 : carries a frus-division-type ending in '-pending' (chapter-pending,
 : section-pending, document-pending; OP#1337).
 :)
declare %private function hsgapi:is-pending($doc as element()?) as xs:boolean {
    exists($doc) and
    ends-with(normalize-space((root($doc)//tei:teiHeader//tei:bibl[@type = 'frus-division-type'])[1]), '-pending')
};

(:~
 : Whether id() resolved to exactly the requested division. Guards two ways
 : id()'s whitespace tokenization bites: several ids in one path segment
 : ("d1%20d3") resolve to several elements, and a trailing or leading space
 : ("d1%20") still resolves to the division itself.
 :)
declare function hsgapi:is-exact-division($doc as node()*, $divisionId as xs:string) as xs:boolean {
    count($doc) eq 1 and $doc/@xml:id = $divisionId
};

(:~
 : An attachment is encoded with a non-empty frus-attachment-label. Its
 : frus-document-number bibl is present but empty, so testing the number would
 : need normalize-space() and would not distinguish it from a numbering gap.
 :)
declare function hsgapi:is-attachment($doc as node()?) as xs:boolean {
    exists($doc) and
    normalize-space(root($doc)//tei:bibl[@type='frus-attachment-label']) != ''
};

declare function hsgapi:attachment-parent($doc as node()?) as xs:string {
    (root($doc)//tei:relatedItem[@type='attachment-source']/@target/string(), "its parent")[1]
};
