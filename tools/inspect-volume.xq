xquery version "3.1";

(:~
 : Inspect a FRUS volume's structure and landing-page metadata — the raw data
 : behind /historicaldocuments/{volume} (WP #1080).
 :
 : Reports the front/body/back xi:include structure (what the volume TOC must
 : be generated from), the database sub-collections/resources, titles by
 : @type, editors by @role, publisher + publication date, and the cover /
 : ebook relatedItems from notesStmt. Stored docs keep xincludes UNEXPANDED.
 :
 :   xst run -f tools/inspect-volume.xq -b '{"volume":"frus1981-88v05"}'
 :
 : Parameters (required in -b):
 :   volume  volume id, e.g. frus1981-88v05
 :)

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace xi = "http://www.w3.org/2001/XInclude";
declare namespace xmldb = "http://exist-db.org/xquery/xmldb";

declare variable $volume external;

let $base := "/db/apps/frus-data-jinks/data/Publications/" || $volume
let $doc := doc($base || "/" || $volume || ".xml")
return
    serialize(
        map {
            "file": $base || "/" || $volume || ".xml",
            "titles": array {
                $doc//tei:fileDesc/tei:titleStmt/tei:title
                    ! map { "type": string(@type), "text": normalize-space(.) }
            },
            "editors": array {
                $doc//tei:fileDesc/tei:titleStmt/tei:editor
                    ! (string(@role) || "=" || normalize-space(.))
            },
            "publication": map {
                "publisher": normalize-space(($doc//tei:publicationStmt/tei:publisher)[1]),
                "pubPlace": normalize-space(($doc//tei:publicationStmt/tei:pubPlace)[1]),
                "dates": array {
                    $doc//tei:publicationStmt/tei:date
                        ! (string(@type) || "=" || normalize-space(.))
                }
            },
            "related-items": array {
                $doc//tei:notesStmt/tei:relatedItem
                    ! (string(@type) || " -> " || string(.//tei:ref/@target))
            },
            "text-structure": array {
                for $part in $doc/tei:TEI/tei:text/*
                return map {
                    "part": local-name($part),
                    "includes": array {
                        $part//xi:include
                            ! (string(@href) || (if (@xpointer) then "#" || @xpointer else ()))
                    }
                }
            },
            "collections": array { xmldb:get-child-collections($base) },
            "resources": array { xmldb:get-child-resources($base) }
        },
        map { "method": "json", "indent": true() }
    )
