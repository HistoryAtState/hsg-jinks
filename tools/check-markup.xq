xquery version "3.1";

(:~
 : Smoke-check rendered hsg-jinks pages for structural sanity — server-side.
 :
 : For each page: HTTP status, whether any document element (html/head/body)
 : leaks into <main> (the defect fixed for non-chapter divisions via the
 : "division" ODD mode; guarded browser-side by
 : test/cypress/e2e/gui/valid-markup.cy.js), and content volume indicators
 : (sections, paragraphs, text length) to spot pages that render empty.
 : Ports/env: see the header of tools/inspect-page.xq.
 :
 :   xst run -f tools/check-markup.xq \
 :     -b '{"paths":"historicaldocuments/frus1981-88v05,historicaldocuments/frus1981-88v05/comp,historicaldocuments/frus1981-88v05/ch1,historicaldocuments/frus1981-88v05/d1"}'
 :
 : Parameters (required in -b):
 :   paths  comma-separated page paths relative to the app root
 :)

declare namespace hc = "http://expath.org/ns/http-client";

declare variable $paths external;

let $base := "http://localhost:8080/exist/apps/hsg-jinks"
return
    serialize(
        array {
            for $path in tokenize($paths, ",") ! normalize-space(.)
            let $resp := hc:send-request(<hc:request method="GET" href="{$base || '/' || $path}"/>)
            let $main := ($resp//*[local-name() = 'main'])[1]
            return map {
                "path": $path,
                (: self axis, not $resp[1]: eXist may reorder the send-request
                   result once $resp is also navigated with `//` :)
                "http-status": string($resp/self::hc:response/@status),
                "invalid-doc-els-in-main": exists($main//*[local-name() = ('html', 'head', 'body')]),
                "sections": count($main//*[local-name() = 'section']),
                "paragraphs": count($main//*[local-name() = 'p']),
                "text-chars": string-length(normalize-space(string-join($main//text(), ' ')))
            }
        },
        map { "method": "json", "indent": true() }
    )
