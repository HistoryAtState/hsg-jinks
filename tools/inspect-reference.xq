xquery version "3.1";

(:~
 : Inspect a page on the reference site history.state.gov — server-side.
 :
 : Fetches the production page the epic-518 work must reproduce and reports
 : its heading structure, breadcrumb, and link sample, for comparing against
 : the hsg-jinks rendering (tools/inspect-page.xq / dump-page.xq). Runs inside
 : the container, so it needs outbound network access.
 :
 :   xst run -f tools/inspect-reference.xq \
 :     -b '{"path":"historicaldocuments/frus1981-88v05/comp"}'
 :
 : Parameters (required in -b):
 :   path  page path relative to https://history.state.gov, no leading slash
 :)

declare namespace hc = "http://expath.org/ns/http-client";

declare variable $path external;

let $url := "https://history.state.gov/" || $path
let $resp := hc:send-request(<hc:request method="GET" href="{$url}"/>)
(: never address $resp positionally: eXist may reorder the send-request
   result (document node first) once $resp is also navigated with `//` :)
let $headings := $resp//*[local-name() = ("h1", "h2", "h3", "h4")]
let $crumbs := ($resp//*[local-name() = 'nav'][contains(@class, 'breadcrumb')])[1]
    //*[local-name() = 'li']
let $links := ($resp//*[local-name() = 'a'][starts-with(@href, '/' || $path)])
return
    serialize(
        map {
            "url": "https://history.state.gov/" || $path,
            "http-status": string($resp/self::hc:response/@status),
            "headings": array {
                $headings ! ("[" || local-name(.) || " class=" || @class || "] "
                    || normalize-space(.))
            },
            "breadcrumb": array {
                $crumbs ! normalize-space(.)
            },
            "same-section-links": map {
                "count": count($links),
                "sample": array {
                    subsequence($links, 1, 8)
                        ! (normalize-space(.) || " -> " || @href)
                }
            }
        },
        map { "method": "json", "indent": true() }
    )
