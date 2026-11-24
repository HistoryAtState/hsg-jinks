xquery version "3.1";

(:~
 : Precompiled jinks templates.
 :
 : tmpl:process tokenizes, parses and generates XQuery from a template, then
 : compiles and runs it, on every request (~300 ms of a page). The generated
 : code is the same for every request that renders a template with the same
 : configuration, so pc:compile-all stores it once per template as a main
 : module, and pc:process runs the stored module through util:eval with the
 : cache flag: eXist's XQueryPool then also keeps the compiled form.
 :
 : The stored code is what tmpl:generate emits, with two changes: an import
 : of this module, and tmpl:include calls redirected to pc:include, so
 : included templates run precompiled too. Its free variables ($context,
 : $_resolver, $_modules, $_namespaces) are bound by pc:eval's parameters,
 : as tmpl:eval binds them. Declaring them external does not work with the
 : XQueryPool: a reused instance keeps the first call's values, and fails
 : with XPST0008 in later requests.
 :
 : A stored module is keyed by the template text and the configuration, so a
 : changed template no longer matches its stored version. It is only used if
 : none of the templates it extends changed since; otherwise pc:process falls
 : back to tmpl:process. Run pc:compile-all after changing a template, layout
 : or block library.
 :
 : tmpl:generate binds every top-level context key to a variable of the same
 : name. The stored code binds only the unprefixed variables it refers to,
 : whatever keys the context has when it runs.
 :)
module namespace pc = "http://history.state.gov/ns/site/hsg/precompiled-templates";

import module namespace tmpl = "http://e-editiones.org/xquery/templates";
import module namespace config = "http://www.tei-c.org/tei-simple/config" at "config.xqm";

declare variable $pc:COLLECTION := $config:app-root || "/compiled-templates";

(: tmpl: the generated code calls tmpl:valueOf and tmpl:content, which it
   finds in scope when tmpl:eval runs it. :)
declare variable $pc:IMPORT :=
    'import module namespace tmpl = "http://e-editiones.org/xquery/templates";&#10;'
    || 'import module namespace pc = "http://history.state.gov/ns/site/hsg/precompiled-templates" at "xmldb:exist://' || $config:app-root || '/modules/precompile.xqm";';

declare variable $pc:CONFIG_MODULE := map {
    "http://www.tei-c.org/tei-simple/config": map { "prefix": "config", "at": "modules/config.xqm" }
};

(:~ The configurations the app's tmpl:process callers use, without the
 : resolver: vapi:html and vapi:view, vapi:handle-error, hsg-errors:render.
 : $files limits a variant to the templates rendered with it. :)
declare variable $pc:VARIANTS := (
    map {
        "files": (),
        "config": map {
            "plainText": false(),
            "modules": $pc:CONFIG_MODULE,
            "namespaces": map { "tei": "http://www.tei-c.org/ns/1.0" }
        }
    },
    map {
        "files": "templates/error-page.html",
        "config": map {
            "plainText": false(),
            "modules": $pc:CONFIG_MODULE,
            "ignoreImports": true(),
            "ignoreUse": true()
        }
    },
    map {
        "files": ("templates/error-400.html", "templates/error-404.html", "templates/error-500.html", "templates/error-request.html"),
        "config": map {
            "plainText": false(),
            "modules": map:merge(($pc:CONFIG_MODULE, map {
                "http://teipublisher.com/ns/templates/page": map { "prefix": "page", "at": "modules/templates/page.xqm" }
            })),
            "ignoreImports": true(),
            "ignoreUse": true()
        }
    }
);

(: Variables pc:eval binds itself, see the module doc. :)
declare variable $pc:BOUND := ("context", "_resolver", "_modules", "_namespaces");

(: ============== shared ============== :)

declare function pc:resolver($relPath as xs:string) as map(*)? {
    let $path := $config:app-root || "/" || $relPath
    let $content :=
        if (util:binary-doc-available($path)) then
            util:binary-doc($path) => util:binary-to-string()
        else if (doc-available($path)) then
            doc($path) => serialize()
        else
            ()
    return
        if ($content) then map { "path": $path, "content": $content } else ()
};

(:~ The key of a template text rendered with a configuration. :)
declare function pc:key($template as xs:string, $config as map(*)) as xs:string {
    let $modules := $config?modules
    let $canonical := string-join((
        $template,
        string($config?plainText), string($config?ignoreImports), string($config?ignoreUse),
        if (exists($modules)) then
            for $uri in map:keys($modules) order by $uri return $uri || "=" || $modules($uri)?prefix || "@" || $modules($uri)?at
        else (),
        if (exists($config?namespaces)) then
            for $prefix in map:keys($config?namespaces) order by $prefix return $prefix || "=" || $config?namespaces($prefix)
        else ()
    ), "&#10;")
    return string(util:hash($canonical, "md5"))
};

(:~ The frontmatter of a template and of every template it extends, in the
 : order tmpl:to-ast merges them, with the paths of the extended templates. :)
declare function pc:frontmatter-chain($template as xs:string, $resolver as function(*)) as map(*)* {
    let $frontmatter := tmpl:frontmatter($template)
    let $extends := $frontmatter?templating?extends
    return (
        map { "frontmatter": $frontmatter, "path": () },
        if ($extends) then
            let $base := $resolver($extends)
            return
                if (exists($base)) then
                    let $chain := pc:frontmatter-chain($base?content, $resolver)
                    return (map { "frontmatter": head($chain)?frontmatter, "path": $base?path }, tail($chain))
                else
                    ()
        else
            ()
    )
};

(:~ The context tmpl:to-ast hands to tmpl:generate: each level's frontmatter
 : merged over the previous, "extends" and "use" removed. :)
declare function pc:context($params as map(*), $frontmatters as map(*)*) as map(*) {
    fold-left($frontmatters, $params, function($ctx, $local) {
        let $context := tmpl:merge-deep(($ctx, $local))
        return
            map:merge((
                $context,
                if (map:contains($context, "templating")) then
                    map { "templating": map:remove(map:remove($context?templating, "extends"), "use") }
                else
                    ()
            ), map { "duplicates": "use-last" })
    })
};

(: ============== compile ============== :)

(:~ Every .html under templates/, relative to the app root. Listed rather than
 : taken from collection(): templates that are not well-formed XML on their
 : own (sidebars, banner, menu fragments) are stored as binary resources. :)
declare function pc:templates() as xs:string* {
    let $list := function($self, $collection) {
        xmldb:get-child-resources($collection)[ends-with(., ".html")] ! ($collection || "/" || .),
        xmldb:get-child-collections($collection) ! $self($self, $collection || "/" || .)
    }
    for $path in $list($list, $config:app-root || "/templates")
    order by $path
    return substring-after($path, $config:app-root || "/")
};

(: tmpl:to-ast takes templating.use and the template modules from it. :)
declare %private function pc:compile-params() as map(*) {
    parse-json(util:binary-to-string(util:binary-doc($config:app-root || "/context.json")))
};

(:~ The unprefixed variables the code refers to, other than pc:eval's. Names
 : the code binds itself are included too: a let bound outside is shadowed. :)
declare %private function pc:variables($code as xs:string) as xs:string* {
    distinct-values(
        analyze-string($code, "\$([A-Za-z_][A-Za-z0-9_.\-]*)(:[A-Za-z_][A-Za-z0-9_.\-]*)?")
            //fn:match[empty(fn:group[@nr = 2])]/fn:group[@nr = 1]/string()
    )[not(. = $pc:BOUND)]
};

(:~ tmpl:process up to the generated code, as it runs it; also returns what
 : pc:process needs to run the code without it. :)
declare %private function pc:generate($template as xs:string, $params as map(*), $config as map(*)) as map(*) {
    (: HTML comments are dropped from the template and from what it extends
       or uses; in text mode they are content :)
    let $strip := if ($config?plainText) then function($s) { $s } else replace(?, "<!--.*?-->", "", "s")
    let $config := map:put($config, "resolver", function($path) {
        let $source := $config?resolver($path)
        return if (exists($source)) then map:put($source, "content", $strip($source?content)) else ()
    })
    let $ast := tmpl:to-ast($strip($template), $params, $config, ())
    let $modules := map:merge((
        $config?modules,
        if (not($config?ignoreImports) and exists($ast?context?templating)) then $ast?context?templating?modules else (),
        for $import in $ast?ast/import
        return map { string($import/@uri): map { "prefix": string($import/@as), "at": string($import/@at) } }
    ), map { "duplicates": "use-last" })
    let $namespaces := map:merge((
        $config?namespaces,
        if (exists($ast?context?templating)) then $ast?context?templating?namespaces else ()
    ), map { "duplicates": "use-last" })
    let $mode := if ($config?plainText) then $tmpl:TEXT_MODE else $tmpl:XML_MODE
    (: tmpl:generate emits a let for each key of the map it is given: first
       none, to find the variables the code refers to, then those :)
    let $generate := tmpl:generate($mode, $ast?ast, ?, $modules, $namespaces, $config?resolver, $ast?blocks)
    let $variables := pc:variables($generate(map {}))
    let $code := $generate(map:merge($variables ! map:entry(., ())))
    return map {
        "code": $pc:IMPORT || "&#10;" || replace($code, "tmpl:include\(", "pc:include("),
        "variables": array { $variables },
        "modules": $modules,
        "namespaces": $namespaces
    }
};

(:~ What the generated code was built from besides the template itself: the
 : templates it extends, the block libraries of templating.use, and
 : context.json, which declares those and the template modules. :)
declare %private function pc:depends($chain as map(*)*, $params as map(*)) as xs:string* {
    distinct-values((
        $chain?path,
        ($params?templating?use?*, $chain?frontmatter?templating?use?*) ! pc:resolver(.)?path,
        $config:app-root || "/context.json"
    ))
};

declare %private function pc:compile($relPath as xs:string, $variant as map(*), $params as map(*)) as map(*) {
    let $source := pc:resolver($relPath)
    let $config := map:merge(($variant?config, map { "resolver": pc:resolver#1 }))
    let $key := pc:key($source?content, $config)
    return
        try {
            let $generated := pc:generate($source?content, $params, $config)
            let $chain := pc:frontmatter-chain($source?content, pc:resolver#1)
            (: not checked with util:compile-query: that compiles the module on
               its own, where the free variables are undeclared; pc:process
               falls back on static errors instead :)
            return
                    let $module := xmldb:store($pc:COLLECTION, $key || ".xq",
                        "(: __template: " || $relPath || " :)&#10;" || $generated?code, "application/xquery")
                    let $meta := map:merge((
                        map { "__template": $relPath },
                        map {
                            "variables": $generated?variables,
                            "frontmatter": array { $chain ! ?frontmatter },
                            "depends": array { pc:depends($chain, $params) ! map { "path": ., "modified": string(pc:modified(.)) } },
                            "modules": $generated?modules,
                            "namespaces": $generated?namespaces
                        }
                    ))
                    let $json := xmldb:store($pc:COLLECTION, $key || ".json",
                        serialize($meta, map { "method": "json" }), "application/json")
                    return (
                        sm:chmod(xs:anyURI($module), "rwxr-xr-x"),
                        sm:chmod(xs:anyURI($json), "rw-r--r--"),
                        map { "template": $relPath, "status": "compiled", "key": $key }
                    )[last()]
        } catch * {
            map { "template": $relPath, "status": "failed", "error": $err:code || " " || $err:description }
        }
};

(:~
 : Compiles every template under templates/ with every configuration it is
 : rendered with, replacing what was stored before. Run it in post-install
 : and after changing any template.
 :)
declare function pc:compile-all() as map(*) {
    let $start := util:system-time()
    let $reset := (
        if (xmldb:collection-available($pc:COLLECTION)) then xmldb:remove($pc:COLLECTION) else (),
        xmldb:create-collection($config:app-root, "compiled-templates"),
        sm:chmod(xs:anyURI($pc:COLLECTION), "rwxr-xr-x")
    )
    let $templates := pc:templates()
    let $params := pc:compile-params()
    let $results :=
        for $variant in $pc:VARIANTS
        for $relPath in if (exists($variant?files)) then $variant?files[. = $templates] else $templates
        return pc:compile($relPath, $variant, $params)
    return map {
        "compiled": count($results[?status = "compiled"]),
        "failed": array { $results[?status = "failed"] },
        "ms": round((util:system-time() - $start) div xs:dayTimeDuration("PT0.001S"))
    }
};

(: ============== render ============== :)

declare %private function pc:modified($path as xs:string) as xs:dateTime? {
    let $collection := replace($path, "/[^/]+$", "")
    let $name := replace($path, "^.*/", "")
    return xmldb:last-modified($collection, $name)
};

(: The generated code refers to these parameter names, see the module doc. :)
declare %private function pc:eval($module as xs:anyURI, $context as map(*), $_resolver as function(*)?,
        $_modules as map(*)*, $_namespaces as map(*)?) {
    util:eval($module, true())
};

(:~ Drop-in for tmpl:process. :)
declare function pc:process($template as xs:string, $params as map(*), $config as map(*)) {
    pc:process($template, $params, $config, ())
};

declare function pc:process($template as xs:string, $params as map(*), $config as map(*), $blocks as element(template)*) {
    let $key := pc:key($template, $config)
    let $metaPath := $pc:COLLECTION || "/" || $key || ".json"
    let $meta := if (empty($blocks) and not($config?debug) and util:binary-doc-available($metaPath)) then json-doc($metaPath) else ()
    let $context := if (exists($meta)) then pc:context($params, $meta?frontmatter?*) else ()
    let $stale := $meta?depends?*[not(string(pc:modified(?path)) eq ?modified)]
    return
        if (empty($meta) or exists($stale)) then (
            if (exists($meta)) then
                util:log("info", "pc: " || $meta?__template || " falls back to tmpl:process: changed " || string-join($stale?path, ", "))
            else
                (),
            tmpl:process($template, $params, $config, $blocks)
        ) else
            try {
                pc:eval(xs:anyURI($pc:COLLECTION || "/" || $key || ".xq"), $context, $config?resolver, $meta?modules, $meta?namespaces)
            } catch err:XPST0008 | err:XPST0017 | err:XPST0081 | err:XQST0059 {
                (: a static error of the stored module, e.g. a function only the
                   including template's modules provide :)
                util:log("warn", "pc: " || $meta?__template || " falls back to tmpl:process: " || $err:code || " " || $err:description),
                tmpl:process($template, $params, $config, $blocks)
            }
};

(:~ Drop-in for tmpl:include, which the generated code calls. :)
declare function pc:include($path as xs:string, $resolver as function(*)?, $params as map(*),
    $plainText as xs:boolean?, $modules as map(*)*, $namespaces as map(*)?, $blocks as element()*) {
    let $template := if (exists($resolver)) then $resolver($path) else ()
    let $config := map {
        "plainText": $plainText, "resolver": $resolver, "debug": false(),
        "modules": $pc:CONFIG_MODULE, "namespaces": map { "tei": "http://www.tei-c.org/ns/1.0" }
    }
    let $meta :=
        if (exists($template) and empty($blocks)) then
            let $metaPath := $pc:COLLECTION || "/" || pc:key($template?content, $config) || ".json"
            return if (util:binary-doc-available($metaPath)) then json-doc($metaPath) else ()
        else ()
    return
        if (exists($meta)) then
            pc:process($template?content, $params, $config)
        else
            tmpl:include($path, $resolver, $params, $plainText, $modules, $namespaces, $blocks)
};
