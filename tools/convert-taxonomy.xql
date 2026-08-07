xquery version "3.1";

(:~
 : One-off conversion (#1177): re-encode the HistoryAtState/tags package's
 : bespoke, non-TEI /db/apps/tags/taxonomy/taxonomy.xml (512 category/tag
 : entries) as native TEI -- tei:taxonomy/tei:category/tei:catDesc -- per
 : ticket #1177's decision, so tei:keywords terms elsewhere in the app become
 : formally resolvable against one TEI vocabulary and /tags/all + definitions
 : become ODD-renderable.
 :
 : Mapping: category/tag -> tei:category[@xml:id], created-by/created-date ->
 : @resp/@when, label -> catDesc/term, definition -> catDesc prose (ptr kept
 : as tei:ptr, target rewritten "id" -> "#id"; the one bare <a href> in the
 : source -> tei:ref), usage-hint -> a separate tei:note[@type="usage-hint"]
 : (staff-only editorial guidance; the rendering layer must not surface it
 : publicly), nesting preserved as nested tei:category.
 :
 : Persists the result via xmldb:store (a real stored document with its own
 : base-uri), not just returned in memory -- an unstored, detached node was
 : found during #1096 to break page:transform's base-uri()-dependent graphic/
 : collection resolution, so this must be a real document from the start.
 :
 :   xst --config .xstrc execute -f tools/convert-taxonomy.xql
 :
 : No parameters; source and target collections are fixed below. Re-run
 : whenever the upstream taxonomy.xml is refreshed to a newer tags package
 : release.
 :)

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace convert = "http://history.state.gov/ns/tools/convert-taxonomy";

declare variable $convert:SOURCE := "/db/apps/tags/taxonomy/taxonomy.xml";
declare variable $convert:TARGET_COL := "/db/apps/hsg-jinks/data/tags";
declare variable $convert:TARGET_NAME := "taxonomy.xml";

(:~ Convert one <definition> or <usage-hint>'s mixed content to TEI prose. :)
declare function convert:prose-content($nodes as node()*) as node()* {
    for $n in $nodes
    return
        typeswitch ($n)
            case text() return $n
            case element(ptr) return
                <tei:ptr target="#{$n/@target}"/>
            case element(a) return
                <tei:ref target="{$n/@href}">{convert:prose-content($n/node())}</tei:ref>
            default return
                convert:prose-content($n/node())
};

declare function convert:category($entry as element()) as element(tei:category) {
    let $id := $entry/id/string()
    let $label := $entry/label/string()
    let $definition := $entry/definition
    let $usageHint := $entry/usage-hint
    let $children := $entry/(category|tag)
    return
        <tei:category xml:id="{$id}" resp="{$entry/@created-by/string()}" when="{$entry/@created-date/string()}">
            <tei:catDesc>
                <tei:term>{$label}</tei:term>
                {
                    if (exists($definition)) then
                        <tei:p>{convert:prose-content($definition/node())}</tei:p>
                    else ()
                }
            </tei:catDesc>
            {
                if (exists($usageHint)) then
                    <tei:note type="usage-hint">{convert:prose-content($usageHint/node())}</tei:note>
                else ()
            }
            {
                for $child in $children
                return convert:category($child)
            }
        </tei:category>
};

let $source := doc($convert:SOURCE)/taxonomy
let $tei :=
    <tei:TEI>
        <tei:teiHeader>
            <tei:fileDesc>
                <tei:titleStmt>
                    <tei:title>{$source/title/string()}</tei:title>
                </tei:titleStmt>
                <tei:publicationStmt>
                    <tei:p>Converted from HistoryAtState/tags taxonomy.xml by tools/convert-taxonomy.xql (#1177).</tei:p>
                </tei:publicationStmt>
                <tei:sourceDesc>
                    {
                        for $p in $source/description/p
                        return <tei:p>{convert:prose-content($p/node())}</tei:p>
                    }
                </tei:sourceDesc>
            </tei:fileDesc>
            <tei:encodingDesc>
                <tei:classDecl>
                    <tei:taxonomy xml:id="hsg-tags">
                        {
                            for $cat in $source/category
                            return convert:category($cat)
                        }
                    </tei:taxonomy>
                </tei:classDecl>
            </tei:encodingDesc>
        </tei:teiHeader>
    </tei:TEI>

let $collection := xmldb:create-collection("/db/apps/hsg-jinks/data", "tags")
let $stored := xmldb:store($convert:TARGET_COL, $convert:TARGET_NAME, $tei)
let $storedDoc := doc($stored)
return
    serialize(
        map {
            "source-ids": count($source//id),
            "stored-document": $stored,
            "stored-categories": count($storedDoc//tei:category),
            "stored-ids-match-source": count($storedDoc//tei:category/@xml:id) eq count($source//id)
        },
        map { "method": "json", "indent": true() }
    )
