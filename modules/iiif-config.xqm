(:~
 : Settings for generating a IIIF presentation manifest for a document.
 :)
module namespace iiifc="https://e-editiones.org/api/iiif/config";

import module namespace iiif="https://e-editiones.org/api/iiif" at "lib/api/iiif.xql";
import module namespace nav="http://www.tei-c.org/tei-simple/navigation" at "navigation.xql";
import module namespace global="http://e-editiones.org/tei-publisher/odd-global" at "odd-global.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : Base URI of the IIIF image API service to use for the images: the FRUS
 : Cantaloupe instance, shared with the ODD pb model and the pb-facsimile
 : viewers via odd-global.xqm (OP#1335). No trailing slash: iiif.xql joins
 : base and identifier with "/".
 :)
declare variable $iiifc:IMAGE_API_BASE := replace($global:iiif-image-api, "/+$", "");

(:~
 : URL prefix to use for the canvas id
 :)
declare variable $iiifc:CANVAS_ID_PREFIX := "https://e-editiones.org/canvas/";

(:~
 : Return all milestone elements pointing to images, usually pb or milestone.
 :
 : @param $doc the document root node to scan
 :)
declare function iiifc:milestones($doc as node()) {
    $doc//tei:pb
};

(:~
 : Extract the image path from the milestone element: the same
 : frus%2F{volume}%2Ftiff%2F{facs}.tif identifier the ODD pb model emits
 : (odd-global.xqm, OP#1335). The default implementation stripped a prefix
 : before a colon, which does not fit the FRUS data's bare image numbers
 : (facs="0347").
 :)
declare function iiifc:milestone-id($milestone as element()) {
    global:iiif-facs-id((), $milestone)
};

(:~
 : Provide general metadata fields for the object. The result will be merged into the
 : root of the presentation manifest. 
 :)
declare function iiifc:metadata($doc as element(), $id as xs:string) as map(*) {
    map {
        "label": nav:get-metadata($doc, "title")/string(),
        "metadata": [
            map { "label": "Title", "value": nav:get-metadata($doc, "title")/string() },
            map { "label": "Creator", "value": nav:get-metadata($doc, "author")/string() },
            map { "label": "Language", "value": nav:get-metadata($doc, "language") },
            map { "label": "Date", "value": nav:get-metadata($doc, "date")/string() }
        ],
        "license": nav:get-metadata($doc, "license"),
        "rendering": [
            map {
                "@id": iiif:link("print/" || encode-for-uri($id)),
                "label": "Print preview",
                "format": "text/html"
            },
            map {
                "@id": iiif:link("api/document/" || encode-for-uri($id) || "/epub"),
                "label": "ePub",
                "format": "application/epub+zip"
            }
        ]
    }
};