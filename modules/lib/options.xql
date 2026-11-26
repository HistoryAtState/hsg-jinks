xquery version "3.1";

(:~
 : Answers OPTIONS with the methods the matched route defines
 : (eeditiones/roaster#89). Without it the servlet answers every path with
 : "GET, HEAD, POST, PUT, DELETE, TRACE, OPTIONS".
 :
 : The specs and their order are those of the built api.xql: config.json's
 : "api" entries in reverse (build.xml drops modules/lib/api.json from the
 : routes, target app-routes). A route is chosen as
 : Roaster 1.13 chooses one: the longest pattern, then the earlier spec.
 : HEAD is listed wherever GET is, since controller.xql serves HEAD as GET
 : (eeditiones/roaster#181).
 :)

declare variable $local:param := "\{[^\}]+\}";

(:~ Roaster 1.13's router:create-regex: a parameter matches one segment,
 : or everything that follows when it is the last one. :)
declare function local:regex($pattern as xs:string) as xs:string {
    let $components := substring-after($pattern, "/") => replace("(\.|\$|\^|\+|\*)", "\\$1") => tokenize("/")
    let $last := count($components)
    return "^/" || string-join(
        for $component at $i in $components
        return replace($component, $local:param, if ($i = $last) then "(.+)" else "([^/]+)"),
        "/")
};

let $path := request:get-attribute("$exist:path")
let $root := repo:get-root() || "/" || request:get-attribute("$exist:controller") || "/"
let $specs := reverse(json-doc($root || "config.json")?api?*?spec) ! ("modules/" || .)
let $route := head(
    for $spec at $priority in $specs
    let $paths := json-doc($root || $spec)?paths
    for $pattern in map:keys($paths)
    where matches($path, local:regex($pattern))
    order by string-length(replace($pattern, $local:param, "?")) descending, $priority
    return $paths($pattern)
)
(: The catch-all route of hsg-api.json answers 404 for any method. :)
let $methods :=
    map:keys($route)[. = ("get", "post", "put", "delete", "patch")][$route(.)?operationId ne "hsgapi:not-found"]
let $allow := string-join(
    sort(distinct-values(($methods, "get"[$methods = "get"] ! "head", "options")) ! upper-case(.)),
    ", ")
return
    if (empty($methods)) then
        response:set-status-code(404)
    else (
        response:set-header("Allow", $allow),
        response:set-header("Access-Control-Allow-Methods", $allow),
        response:set-status-code(204)
    )
