xquery version "3.1";

module namespace hsgapi="http://teipublisher.com/api/hsg";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace errors="http://e-editiones.org/roaster/errors";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

declare function hsgapi:view($request as map(*)) {
    let $publicationId := $request?parameters?publicationId
    let $_ := util:log("INFO", "publicationId: " || $publicationId)
    return
        vapi:view(map:merge((
            $request,
            map {
                "parameters": map:merge((
                    $request?parameters,
                    map {
                        "docid": "Publications/" || $publicationId || "/" || $publicationId || ".xml"
                    }
                ))
            }
        )))
};

declare function hsgapi:view-interior($request as map(*)) {
    let $publicationId := $request?parameters?publicationId
    let $divisionId := $request?parameters?divisionId
    let $_ := util:log("INFO", "publicationId: " || $publicationId || " divisionId: " || $divisionId)
    let $doc := collection($config:data-default || "/" || $publicationId)/id($divisionId)
    return
        if (hsgapi:is-attachment($doc)) then
            (: Attachments have no page of their own: they are rendered inline in
               the document that xincludes them, and the reference site 404s their
               URL. The data disagrees -- each carries a relatedItem type="canonical"
               advertising this very URL -- but the reference site is authoritative
               here. Their notes belong to the parent's consolidated footnote list,
               so a standalone page could not render them anyway. :)
            error($errors:NOT_FOUND, "division " || $divisionId || " is an attachment of "
                || hsgapi:attachment-parent($doc) || " and has no page of its own")
        else
            vapi:view(map:merge((
                $request,
                map {
                    "parameters": map:merge((
                        $request?parameters,
                        map {
                            "docid": substring-after(document-uri(root($doc)), $config:data-root || '/')
                        }
                    ))
                }
            )))
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

(:~
 : Wrap the jinks-owned vapi:handle-error, which renders the error page but
 : hardcodes HTTP 200, so a missing page still reports success to crawlers and
 : link checkers. Keep its markup, correct the status.
 :)
declare function hsgapi:handle-error($error as map(*)) {
    let $response := vapi:handle-error($error)
    return
        if ($error?code eq $errors:NOT_FOUND) then
            map:put($response, xs:QName("router:RESPONSE_CODE"), 404)
        else
            $response
};