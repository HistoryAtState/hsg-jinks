xquery version "3.1";

(:~
 : Inspect the stored TEI of one FRUS division (document, chapter, comp,
 : front/back matter) — the raw data behind a /historicaldocuments URL.
 :
 : Resolves the division the same way the app does
 : (collection(Publications/{volume})/id({id})) and reports everything the
 : rendering work needs: file location, titles by @type, sourceDesc bibls
 : (frus-volume-id / frus-division-id / -type / -subtype / document-number),
 : the body div's attributes and child elements, frusGen processing
 : instructions (heading/dateline placeholders), standOff notes, the setting
 : (place/date), and xi:includes. Stored docs keep xincludes UNEXPANDED.
 :
 :   xst run -f tools/inspect-division.xq \
 :     -b '{"volume":"frus1981-88v05","id":"d1"}'
 :
 : Parameters (all required in -b):
 :   volume  volume id, e.g. frus1981-88v05
 :   id      division xml:id, e.g. d1, ch1, comp, preface, app — or the
 :           volume id itself for the volume file
 :)

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace xi = "http://www.w3.org/2001/XInclude";

declare variable $volume external;
declare variable $id external;

let $base := "/db/apps/frus-data-jinks/data/Publications"
let $hit :=
    if ($id = $volume)
    then doc($base || "/" || $volume || "/" || $volume || ".xml")/*
    else collection($base || "/" || $volume)/id($id)
let $root := root($hit)
let $div := $root//tei:text/tei:body/tei:div
let $includes := $root//xi:include
return
    if (empty($hit)) then
        serialize(map { "error": "no element with id '" || $id || "' in " || $base || "/" || $volume },
            map { "method": "json" })
    else
        serialize(
            map {
                "file": document-uri($root),
                "titles": array {
                    $root//tei:teiHeader//tei:titleStmt/tei:title
                        ! map { "type": string(@type), "text": normalize-space(.) }
                },
                "bibls": array {
                    $root//tei:sourceDesc//tei:bibl
                        ! (string(@type) || "=" || normalize-space(.))
                },
                "body-div": array {
                    $div ! map {
                        "attributes": string-join(@* ! (name(.) || "=" || .), " "),
                        "children": string-join(*/name(), ", ")
                    }
                },
                "processing-instructions": array {
                    (: local-name(), NOT name(): name() on a stored PI node
                       triggers an NPE in eXist's XML-RPC layer :)
                    $root//processing-instruction() ! (local-name(.) || "[" || string(.) || "]")
                },
                "standoff-notes": map {
                    "count": count($root//tei:standOff//tei:note),
                    "types": array { distinct-values($root//tei:standOff//tei:note/@type/string()) }
                },
                "setting": array {
                    $root//tei:settingDesc/tei:setting/*
                        ! (local-name(.) || "=" || normalize-space(.))
                },
                "xincludes": map {
                    "count": count($includes),
                    "sample": array {
                        subsequence($includes, 1, 10)
                            ! (string(@href) || (if (@xpointer) then "#" || @xpointer else ()))
                    }
                }
            },
            map { "method": "json", "indent": true() }
        )
