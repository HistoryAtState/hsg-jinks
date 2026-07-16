xquery version "3.1";

(:~
 : Dump (part of) the rendered HTML of a deployed hsg-jinks page — server-side.
 :
 : Complements tools/inspect-page.xq: where that one asserts on CSS classes,
 : this one returns the actual markup for eyeballing, e.g. after an ODD or
 : template change. Ports/env: see the header of tools/inspect-page.xq.
 :
 :   # the <main> element of the comp page
 :   xst run -f tools/dump-page.xq \
 :     -b '{"path":"historicaldocuments/frus1981-88v05/comp","element":"main"}'
 :
 :   # the whole page
 :   xst run -f tools/dump-page.xq \
 :     -b '{"path":"historicaldocuments/frus1981-88v05/d1","element":""}'
 :
 : Parameters (all required in -b):
 :   path     page path relative to the app root, no leading slash
 :   element  local-name of the element to extract (first match), e.g. "main",
 :            "aside", "footer" — or "" for the full page
 :)

declare namespace hc = "http://expath.org/ns/http-client";

declare variable $path external;
declare variable $element external;

let $base := "http://localhost:8080/exist/apps/hsg-jinks"
let $resp := hc:send-request(<hc:request method="GET" href="{$base || '/' || $path}"/>)
(: never address $resp positionally: eXist may reorder the send-request
   result (document node first) once $resp is also navigated with `//` :)
let $target :=
    if ($element = "") then $resp[. instance of document-node()]
    else ($resp//*[local-name() = $element])[1]
return (
    "STATUS: " || string($resp/self::hc:response/@status),
    serialize($target, map { "method": "xml", "indent": true() })
)
