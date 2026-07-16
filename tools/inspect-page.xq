xquery version "3.1";

(:~
 : Inspect the rendered HTML of a deployed hsg-jinks page — server-side.
 :
 : Fetches a page from the app *inside* the eXist container (localhost:8080)
 : via the EXPath http-client and returns it as parsed nodes, so you can assert
 : on the real rendered markup (by CSS class) instead of regexing a curl dump on
 : the host. Handy for iterating on breadcrumb / page-markup changes: edit the
 : ODD or templates, redeploy, then re-run this to see what actually rendered.
 :
 : Run it from the host shell, pointing xst at the host port (8080 by default;
 : if you remapped it, see "Remapping ports" in the README, use yours). All
 : three parameters MUST be bound with -b (xst requires every declared external
 : variable to be provided; and a `:= default` on an external is NOT overridden
 : by -b, so we declare them bare and bind explicitly every run):
 :
 :   export EXISTDB_SERVER=http://localhost:8080/exist EXISTDB_USER=admin EXISTDB_PASS=""
 :
 :   # check the breadcrumb title of document d1, assert the "test:" debug prefix is gone
 :   xst run -f tools/inspect-page.xq \
 :     -b '{"path":"historicaldocuments/frus1981-88v05/d1","select":"breadcrumb","find":"test:"}'
 :
 :   # any other page + any CSS-class selector + any assertion string
 :   xst run -f tools/inspect-page.xq \
 :     -b '{"path":"historicaldocuments/frus1981-88v05","select":"document card","find":"TODO"}'
 :
 : Two ports are in play (see doc/uswds-profile-integration.md):
 :   - EXISTDB_SERVER = host port  (host -> container, used by xst itself)
 :   - $base below    = 8080       (the app as seen from inside the container —
 :                                  always 8080, regardless of any host remap)
 :
 : Parameters (all required in -b):
 :   path    page path relative to the app root, no leading slash
 :   select  CSS-class substring to extract, OR the alias "breadcrumb"
 :           (= tei-teiHeader3, the current-document breadcrumb title)
 :   find    literal string to count across the whole page (0 == absent)
 :
 : Output (JSON): the resolved url, HTTP status, resolved selector, the find
 : string and its occurrence count, and the normalized text of every matched
 : element.
 :
 : Note: httpclient:get is NOT registered on this instance; use EXPath hc.
 :)

declare namespace hc = "http://expath.org/ns/http-client";

declare variable $path external;
declare variable $select external;
declare variable $find external;

let $base := "http://localhost:8080/exist/apps/hsg-jinks"
let $class := if ($select = "breadcrumb") then "tei-teiHeader3" else $select
let $req := <hc:request method="GET" href="{$base || '/' || $path}"/>
let $resp := hc:send-request($req)
(: never address $resp positionally: eXist may reorder the send-request
   result (document node first) once $resp is also navigated with `//` :)
let $body := string-join($resp[. instance of document-node()], "")
let $matches := $resp//*[contains(@class, $class)]
return
    serialize(
        map {
            "url": $base || "/" || $path,
            "http-status": string($resp/self::hc:response/@status),
            "selector": $class,
            "find": $find,
            "find-count": count(analyze-string($body, $find)//*:match),
            "match-count": count($matches),
            "matches": array {
                for $m in $matches
                return normalize-space(string-join($m//text(), " "))
            }
        },
        map { "method": "json", "indent": true() }
    )
