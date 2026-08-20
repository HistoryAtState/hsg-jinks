xquery version "3.1";

(:~
 : The /services section (OP#1106, #1208-#1210): two machine endpoints, XML
 : in/out, consumed by the FRUS asset-publishing tooling (hsg-publish's
 : admin upload action, the frus repo's ID/asset QA checks) rather than by
 : any page — the only section with zero rendering concern.
 :
 : Deliberate tightenings over the hsg-shell originals, both flagged in the
 : analysis tickets: the bare .xql forwards accepted any method and any
 : trailing path segments with HTTP 200 (now schema-enforced GET on the
 : exact paths), and volume-images answered a missing volume parameter with
 : HTTP 200 carrying &lt;error&gt; (now a real 400, enforced by the required
 : query parameter).
 :)
module namespace servicesapi = "https://history.state.gov/api/services";

import module namespace config = "http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace errors = "http://e-editiones.org/roaster/errors";
import module namespace roaster = "http://e-editiones.org/roaster";
import module namespace hc = "http://expath.org/ns/http-client";

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace s3xml = "http://s3.amazonaws.com/doc/2006-03-01/";

(:~
 : Base URL of an S3-compatible listing endpoint for the static assets
 : bucket. The production bucket denies anonymous ListObjects (hsg-shell
 : signs its requests with its private aws/s3 library), so a deployment
 : must supply either a listing-enabled endpoint/proxy or the bucket URL of
 : an environment where anonymous listing is allowed. Unset (the
 : devcontainer default) the endpoint degrades to HTTP 503 instead of
 : pretending an empty volume, so the QA tooling can tell "not configured"
 : from "no assets".
 :)
declare variable $servicesapi:s3-endpoint as xs:string? :=
    environment-variable("HSG_S3_LIST_ENDPOINT")[. ne ''];

(:~
 : GET /services/volume-ids (OP#1209): every volume id in the FRUS
 : collection, sorted, in the hsg-shell response shape. In the
 : frus-unbound-alpha data model each volume is a collection of division
 : documents that are themselves tei:TEI roots, so the volume roots are
 : identified per collection ({volume}/{volume}.xml) rather than by matching
 : every TEI document.
 :)
declare function servicesapi:volume-ids($request as map(*)) {
    let $start-time := util:system-time()
    let $hits :=
        for $child in xmldb:get-child-collections($config:data-default)
        let $root := $config:data-default || "/" || $child || "/" || $child || ".xml"
        where doc-available($root)
        return doc($root)/tei:TEI/@xml:id/string()
    let $hitcount := count($hits)
    let $runtime := (util:system-time() - $start-time) div xs:dayTimeDuration('PT1S')
    return
        roaster:response(200, "application/xml",
            <results>
                <summary>
                    <volumes>{$hitcount}</volumes>
                    <time>{$runtime} seconds</time>
                    <datetime-retrieved>{current-dateTime()}</datetime-retrieved>
                </summary>
                <volume-ids>{
                    for $hit in $hits
                    order by $hit
                    return
                        <volume-id>{$hit}</volume-id>
                }</volume-ids>
            </results>)
};

(:~
 : GET /services/volume-images?volume= (OP#1210): the image assets stored
 : for one volume, from an S3 ListObjects call on the frus/{volume}/ prefix,
 : filtered to non-.txt/.xml files like the reference.
 :)
declare function servicesapi:volume-images($request as map(*)) {
    let $volume := normalize-space($request?parameters?volume)
    return
        if ($volume eq '') then
            error($errors:BAD_REQUEST, "missing volume parameter")
        else if (empty($servicesapi:s3-endpoint)) then
            roaster:response(503, "application/xml",
                <error>no object-store listing endpoint configured (HSG_S3_LIST_ENDPOINT)</error>)
        else
            let $start-time := util:system-time()
            let $prefix := "frus/" || $volume || "/"
            let $url := $servicesapi:s3-endpoint || "?list-type=2&amp;delimiter=/&amp;prefix="
                || encode-for-uri($prefix)
            let $response := hc:send-request(<hc:request method="GET" href="{$url}"/>)
            let $status := xs:integer($response[1]/@status)
            return
                if ($status ne 200) then
                    roaster:response(502, "application/xml",
                        <error>object-store listing failed with HTTP {$status}</error>)
                else
                    let $contents := $response[2]//s3xml:Contents[s3xml:Key ne $prefix]
                    let $hits :=
                        for $item in $contents
                        let $filename := tokenize($item/s3xml:Key, '/')[last()]
                        where not(matches($filename, '(?:\.txt|\.xml)$'))
                        return $filename
                    let $runtime := (util:system-time() - $start-time) div xs:dayTimeDuration('PT1S')
                    return
                        roaster:response(200, "application/xml",
                            <results>
                                <summary>
                                    <images>{count($hits)}</images>
                                    <time>{$runtime} seconds</time>
                                    <datetime-retrieved>{current-dateTime()}</datetime-retrieved>
                                </summary>
                                <images>{
                                    for $hit in $hits
                                    return
                                        <image>{$hit}</image>
                                }</images>
                            </results>)
};

(: No x-error-handler for this section, deliberately: it is machine-only, and
   roaster's default error handling already answers schema violations (the
   required volume parameter) and unmatched paths with correct status codes
   and plain bodies — exactly right for the QA tooling. The themed hsg-errors
   pages (OP#1309) are for human-facing sections. :)
