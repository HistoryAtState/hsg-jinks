xquery version "3.1";

module namespace opdsapi="http://teipublisher.com/api/opds";

import module namespace roaster="http://e-editiones.org/roaster";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace opds="https://history.state.gov/ns/templates/opds-catalog" at "templates/opds-catalog.xqm";

(:~
 : The key roaster reads the status code from. Rebuilt here rather than
 : imported: roaster.xqm does not re-export $router:RESPONSE_CODE. Same
 : approach as hsgapi:handle-error / countryapi:handle-error / dhapi's
 : redirect+handle-error.
 :)
declare namespace router="http://e-editiones.org/roaster/router";

(:~ Serialize an Atom feed and return it with the exact OPDS-profile
 : Content-Type for its kind -- the concrete fix over hsg-shell's live
 : behavior, which serves every one of these as plain text/xml regardless of
 : what its own internal &lt;link type="..."&gt; values claim. :)
declare %private function opdsapi:atom-response($feed as element(), $mediaType as xs:string) as map(*) {
    roaster:response(200, $mediaType, serialize($feed, map { "method": "xml" }))
};

declare function opdsapi:catalog($request as map(*)) {
    opdsapi:atom-response(opds:catalog-feed(), "application/atom+xml;profile=opds-catalog;kind=navigation")
};

declare function opdsapi:all($request as map(*)) {
    opdsapi:atom-response(opds:all-feed(), "application/atom+xml;profile=opds-catalog;kind=acquisition")
};

(:~
 : Rework item (#1202): hsg-shell casts $n straight to xs:integer with no
 : validation, so a non-numeric value throws an uncaught FORG0001 (an
 : unhandled 500). Validate first and raise BAD_REQUEST instead.
 :)
declare function opdsapi:recent($request as map(*)) {
    let $n := $request?parameters?n
    return
        if (not($n castable as xs:integer) or xs:integer($n) < 1) then
            error($errors:BAD_REQUEST, "n must be a positive integer, got: " || $n)
        else
            opdsapi:atom-response(opds:recent-feed(xs:integer($n)), "application/atom+xml;profile=opds-catalog;kind=acquisition")
};

(:~
 : Rework item (#1203): hsg-shell's unknown-tag response is an ad hoc HTML
 : page (opds:tag-not-found-error), the only non-Atom response in the whole
 : section. Raise NOT_FOUND instead so opdsapi:handle-error produces the
 : same JSON error body every other failure in this section uses.
 :)
declare function opdsapi:browse($request as map(*)) {
    let $tag := $request?parameters?tag
    return
        if ($tag and not(opds:tag-exists($tag))) then
            error($errors:NOT_FOUND, "no such tag: " || $tag)
        else
            (: browse's entry mix (navigation-only vs navigation+acquisition)
             : is genuinely data-dependent, so its Content-Type carries no
             : fixed kind -- matches the OpenAPI spec's own declared shape. :)
            opdsapi:atom-response(opds:browse-feed($tag), "application/atom+xml;profile=opds-catalog")
};

(:~
 : Rework item (#1204): hsg-shell wraps ft:query() in `catch * { () }`,
 : silently swallowing every error (not just malformed Lucene syntax) into
 : an empty result feed -- the source's own TODO calls this out. Catch here
 : and raise BAD_REQUEST instead, so a caller learns their query was invalid
 : rather than getting a feed that silently has no hits.
 :)
declare function opdsapi:search($request as map(*)) {
    let $q := $request?parameters?q
    let $hits :=
        if ($q) then
            try {
                opds:taxonomy-tag-hits($q)
            } catch * {
                error($errors:BAD_REQUEST, "malformed search query: " || $q)
            }
        else
            ()
    return
        opdsapi:atom-response(opds:search-feed($q, $hits), "application/atom+xml;profile=opds-catalog;kind=navigation")
};

(:~
 : This section is pure machine API (no HTML anywhere), so unlike
 : hsgapi:handle-error / dhapi:handle-error (which wrap vapi:handle-error's
 : rendered error page and only patch its status code), this builds the
 : response by hand -- the same raw router:RESPONSE_* QName technique
 : dhapi:redirect already uses -- producing a uniform
 : {"code": ..., "description": ...} JSON body for every failure, matching
 : this section's OpenAPI spec. "code" is the error QName's own local name
 : (e.g. "NOT_FOUND", "BAD_REQUEST"), not the HTTP status number. Expected
 : 4xx responses keep their message; a 500 is deliberately generic.
 :)
declare function opdsapi:handle-error($error as map(*)) as map(*) {
    (: FORG0001 is not one of roaster's own $errors:* QNames: it's the plain
     : XPath cast error Roaster's own OpenAPI-schema-driven parameter
     : coercion raises when a query param declared "type": "integer" (n,
     : here) can't be cast, BEFORE opdsapi:recent's own body ever runs --
     : confirmed live (?n=abc). Without this, that case would fall to the
     : 500 branch below despite being exactly the "malformed input" case
     : #1202 asks to turn into a 400. :)
    let $localName := local-name-from-QName($error?code)
    let $status :=
        if ($error?code eq $errors:NOT_FOUND) then 404
        else if ($error?code eq $errors:BAD_REQUEST or $localName eq "FORG0001") then 400
        else 500
    let $body := map {
        "code": if ($status = 500) then "INTERNAL_SERVER_ERROR" else $localName,
        "description":
            if ($status = 500) then
                "The server could not complete the request"
            else
                $error?description
    }
    return
        map {
            xs:QName("router:RESPONSE_CODE"): $status,
            xs:QName("router:RESPONSE_TYPE"): "application/json",
            xs:QName("router:RESPONSE_HEADERS"): map {},
            (: NOT pre-serialized: router:write-response does its own
             : method=json serialization of RESPONSE_BODY based on
             : RESPONSE_TYPE -- handing it an already-serialized JSON
             : string double-encodes it (confirmed live: the response body
             : came back as a JSON string literal containing escaped JSON
             : text, not a bare JSON object). :)
            xs:QName("router:RESPONSE_BODY"): $body
        }
};
