xquery version "3.1";

(:~
 : Dump every breadcrumb nav of a rendered hsg-jinks page — server-side.
 :
 : Returns all nav[@aria-label='breadcrumb'] elements as serialized markup, so
 : you can see crumb order, labels, and hrefs at once — including the known
 : duplicate empty nav from the USWDS profile (see WP #1082). Ports/env: see
 : the header of tools/inspect-page.xq.
 :
 :   xst run -f tools/dump-breadcrumb.xq \
 :     -b '{"path":"historicaldocuments/frus1981-88v05/d1"}'
 :
 : Parameters (required in -b):
 :   path  page path relative to the app root, no leading slash
 :)

declare namespace hc = "http://expath.org/ns/http-client";

declare variable $path external;

let $base := "http://localhost:8080/exist/apps/hsg-jinks"
let $resp := hc:send-request(<hc:request method="GET" href="{$base || '/' || $path}"/>)
let $navs := $resp//*[local-name() = 'nav'][@aria-label = 'breadcrumb']
return
    serialize(
        map {
            "path": $path,
            (: self axis, not $resp[1]: eXist may reorder the send-request
               result once $resp is also navigated with `//` :)
            "http-status": string($resp/self::hc:response/@status),
            "nav-count": count($navs),
            "navs": array { $navs ! serialize(., map { "indent": true() }) }
        },
        map { "method": "json", "indent": true() }
    )
