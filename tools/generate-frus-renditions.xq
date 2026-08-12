xquery version "3.1";

(:~
 : Regenerate resources/css/frus-renditions.css from the FRUS rendition
 : vocabulary (PR #32 review: "Is there a pipeline that regenerates these CSS
 : rules from encodingDesc").
 :
 : The canonical vocabulary is the 42 tei:rendition definitions in
 : hsg-jinks-data's frus-tei-guidelines-resources/frus-encodingDesc.xml. TEI
 : Publisher would normally generate the matching CSS at render time, by
 : resolving each @rendition token's definition with id() in the rendered
 : document -- but division files reference the encodingDesc only by its remote
 : canonical URL and the view pipeline does not expand XIncludes, so id() finds
 : nothing and every document_* class renders unstyled. This script closes that
 : gap ahead of time instead, against the copy of the encodingDesc the data
 : package deploys.
 :
 : Run it against this worktree's own eXist (never host port 8080, the
 : read-only reference mirror -- see CLAUDE.md), redirecting to the stylesheet
 : it generates:
 :
 :   xst --config .xstrc run -f tools/generate-frus-renditions.xq \
 :     > resources/css/frus-renditions.css
 :
 : Parameters (optional in -b):
 :   encodingDesc  path to the deployed frus-encodingDesc.xml
 :
 : The section comments come from the encodingDesc's own grouping comments, so
 : they follow the vocabulary too. Only the element-context refinements below
 : are written here: they implement what that file's own prose prescribes but
 : CSS text properties cannot express from a bare class ("#center on a table or
 : figure is margin-left/right auto"), so they have no rendition to generate
 : from. Add any further hand-written rule to $refinements rather than to the
 : generated stylesheet, which this script overwrites wholesale.
 :)

declare namespace tei = "http://www.tei-c.org/ns/1.0";

declare variable $encodingDesc external :=
    "/db/apps/frus-data-jinks/data/frus-tei-guidelines-resources/frus-encodingDesc.xml";

declare variable $refinements :=
    string-join((
        "/*",
        " * seg[rendition~=&quot;#center&quot;] needs display:block: text-align cannot center an",
        " * inline &lt;seg&gt; (rendered as &lt;span class=&quot;tei-seg&quot;&gt;). 68,393 of 68,395 legacy",
        " * #center uses are opener segs. Flagged in hsg-jinks-data PR #8.",
        " */",
        ".tei-seg.document_center { display: block; }",
        "",
        "/*",
        " * The encodingDesc's own block comment prescribes element-context refinements:",
        " * &quot;#center on a table or figure is margin-left/right auto&quot; (text-align cannot",
        " * center the box itself).",
        " */",
        "table.document_center,",
        ".tei-figure.document_center { margin-left: auto; margin-right: auto; }"
    ), "&#10;");

(:~ A rendition's CSS body, normalized onto one line. :)
declare function local:rule($rendition as element(tei:rendition)) as xs:string {
    ".document_" || $rendition/@xml:id || " { " || normalize-space($rendition) || " }"
};

(:~ Greedy word wrap, so a long grouping comment stays readable in the
 : generated file rather than running to one 250-character line. :)
declare function local:wrap($text as xs:string, $width as xs:integer) as xs:string* {
    fold-left(tokenize(normalize-space($text), " "), (), function($lines, $word) {
        let $last := $lines[last()]
        return
            if (empty($last) or string-length($last) + string-length($word) + 1 gt $width) then
                ($lines, $word)
            else
                ($lines[position() lt last()], $last || " " || $word)
    })
};

(:~ The encodingDesc's grouping comments become section comments, so the
 : stylesheet keeps the source vocabulary's own structure. :)
declare function local:section($comment as comment()) as xs:string {
    let $lines := local:wrap(string($comment), 72)
    return
        if (count($lines) eq 1) then
            "&#10;/* " || $lines || " */"
        else
            "&#10;/* " || string-join($lines, "&#10;   ") || " */"
};

let $doc :=
    if (doc-available($encodingDesc)) then
        doc($encodingDesc)
    else
        error(xs:QName("local:not-found"), "no encodingDesc at " || $encodingDesc)
let $tagsDecl := $doc//tei:teiHeader/tei:encodingDesc/tei:tagsDecl
let $renditions := $tagsDecl/tei:rendition[@xml:id]
let $rules :=
    for $node in $tagsDecl/node()
    return
        typeswitch ($node)
            case comment() return local:section($node)
            case element(tei:rendition) return
                if ($node/@xml:id) then local:rule($node) else ()
            default return ()
return
    string-join((
        "/*",
        " * FRUS rendition styles -- GENERATED, do not edit by hand.",
        " *",
        " * Regenerate with tools/generate-frus-renditions.xq (see its header for why",
        " * this is generated ahead of time rather than resolved at render time, and",
        " * for how to run it).",
        " *",
        " * Source vocabulary: the " || count($renditions) || " tei:rendition definitions in",
        " * hsg-jinks-data's frus-tei-guidelines-resources/frus-encodingDesc.xml, one",
        " * &quot;.document_&lt;id&gt;&quot; rule each -- the class name TEI Publisher's",
        " * useSourceRendition emits for @rendition=&quot;#&lt;id&gt;&quot; (css:get-rendition in",
        " * tei-publisher-lib).",
        " */",
        $rules,
        "",
        $refinements,
        ""
    ), "&#10;")
