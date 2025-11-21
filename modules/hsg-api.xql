xquery version "3.1";

module namespace hsgapi="http://teipublisher.com/api/hsg";

import module namespace vapi="http://teipublisher.com/api/view" at "lib/api/view.xql";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";

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
    let $doc := collection($config:data-default || "/" || $publicationId)/id($divisionId)
    return
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