xquery version "3.1";

(:~
 : Roaster middleware enforcing the OpenAPI schema constraints roaster 1.13
 : ignores (it casts parameters by "type" only): "pattern", "maxLength",
 : "minLength" and "enum" on path and query parameters.
 :
 : Runs after roaster's own parameter middlewares, so $request?parameters
 : holds the decoded, cast values. A path parameter that fails answers 404,
 : like an id that does not exist; a query parameter answers 400.
 :)
module namespace schema-constraints="https://history.state.gov/ns/site/hsg/schema-constraints";

import module namespace errors="http://e-editiones.org/roaster/errors";

declare function schema-constraints:use($request as map(*), $response as map(*)) as map(*)+ {
    (: these FLWOR expressions return an empty sequence, if all parameters are valid :)
    for $param in $request?config?parameters?*[?in = "path"]
    let $violations := schema-constraints:check($request, $param)
    where exists($violations)
    return error($errors:NOT_FOUND, schema-constraints:message($param, $violations))
    ,
    for $param in $request?config?parameters?*[?in = "query"]
    let $violations := schema-constraints:check($request, $param)
    where exists($violations)
    return error($errors:BAD_REQUEST, schema-constraints:message($param, $violations))
    ,
    (: continue with validated parameters :)
    $request,
    $response
};

(:~
 : Roaster passes an "array" parameter as an XQuery array; its members are
 : checked against the "items" schema.
 :)
declare %private function schema-constraints:check($request as map(*), $param as map(*)) as xs:string* {
    let $value := $request?parameters?($param?name)
    return
        if ($param?schema?type = "array") then
            schema-constraints:violations($value?*, $param?schema?items)
        else
            schema-constraints:violations($value, $param?schema)
};

(:~
 : One description per constraint a value breaks, e.g.
 : value "../x" does not match pattern "^[a-z]+$".
 : OpenAPI "pattern" is an unanchored regular expression, as with matches().
 :)
declare %private function schema-constraints:violations($values as item()*, $schema as map(*)?) as xs:string* {
    for $value in $values ! string(.)
    let $quoted := 'value "' || $value || '"'
    return (
        if (exists($schema?pattern) and not(matches($value, $schema?pattern))) then
            $quoted || ' does not match pattern "' || $schema?pattern || '"'
        else (),
        if (exists($schema?maxLength) and string-length($value) gt $schema?maxLength) then
            $quoted || " is longer than " || $schema?maxLength || " characters"
        else (),
        if (exists($schema?minLength) and string-length($value) lt $schema?minLength) then
            $quoted || " is shorter than " || $schema?minLength || " characters"
        else (),
        if (exists($schema?enum) and not($value = $schema?enum?*)) then
            $quoted || " is not one of " || string-join($schema?enum?* ! ('"' || . || '"'), ", ")
        else ()
    )
};

(: e.g. path parameter "documentId": value "../x" does not match pattern "^[a-z]+$" :)
declare %private function schema-constraints:message($param as map(*), $violations as xs:string+) as xs:string {
    $param?in || ' parameter "' || $param?name || '": ' || string-join($violations, "; ")
};
