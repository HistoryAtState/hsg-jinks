xquery version "3.1";

(:~
 : Run the hsg-jinks ODD web transform on one stored division, without HTTP.
 :
 : The fastest loop for ODD work: edit resources/odd/hsg-jinks.odd, upload it
 : (xst upload ... /db/apps/hsg-jinks/resources/odd), run
 : `jinks run hsg-jinks fix-odds`, then run this to see exactly what the
 : transform emits for a given mode — no page template, layout, or browser in
 : between. (tools/inspect-page.xq / dump-page.xq show the full page instead.)
 :
 :   xst run -f tools/transform-division.xq \
 :     -b '{"volume":"frus1981-88v05","id":"d1","mode":"division"}'
 :
 :   xst run -f tools/transform-division.xq \
 :     -b '{"volume":"frus1981-88v05","id":"ch1","mode":"volume-interior"}'
 :
 : Parameters (all required in -b):
 :   volume  volume id, e.g. frus1981-88v05
 :   id      division xml:id (d1, ch1, comp, preface, ...) — or the volume id
 :           itself for the volume file
 :   mode    ODD mode: division, volume-interior, volume-landing, breadcrumb,
 :           ... or "" for the default (behaviour="document", emits a full
 :           HTML document)
 :)

import module namespace pm-config = "http://www.tei-c.org/tei-simple/pm-config"
    at "/db/apps/hsg-jinks/modules/pm-config.xql";

declare variable $volume external;
declare variable $id external;
declare variable $mode external;

let $base := "/db/apps/frus-data-jinks/data/Publications"
let $hit :=
    if ($id = $volume)
    then doc($base || "/" || $volume || "/" || $volume || ".xml")/*
    else collection($base || "/" || $volume)/id($id)/ancestor-or-self::*[last()]
let $params := if ($mode = "") then map {} else map { "mode": $mode }
return
    if (empty($hit)) then
        "ERROR: no element with id '" || $id || "' in " || $base || "/" || $volume
    else
        serialize(
            $pm-config:web-transform($hit, $params, "hsg-jinks.odd"),
            map { "method": "xml", "indent": true() }
        )
