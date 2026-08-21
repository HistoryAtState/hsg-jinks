xquery version "3.1";

(:~
 : Extension functions the canonical FRUS ODD's processing models call.
 :
 : resources/odd/frus.odd is authored upstream (frus-tei-guidelines, vendored by
 : tools/sync-frus-guidelines.sh) and its models invoke a set of "ext:" helpers
 : that the consuming application is expected to supply -- the ODD deliberately
 : declares no xmlns:ext, leaving the prefix to be bound by the consumer's
 : resources/odd/configuration.xml, which is where this module is registered.
 :
 : NONE of upstream's helpers is currently reachable from the compiled
 : transforms, and this module is deliberately kept anyway.
 :
 : resources/odd/hsg-jinks.odd derives from frus.odd, and TEI Publisher's
 : odd:merge REPLACES a parent elementSpec wholesale when the child redeclares
 : it with models. hsg-jinks.odd redeclares every upstream spec carrying an ext:
 : call: sixteen of the seventeen sit on specs it already overrode (div, title,
 : anchor, note, ...), and the seventeenth, ext:get-division-subtype on "item",
 : is displaced by the guard hsg-jinks.odd has to apply there so that upstream's
 : item model does not emit invalid HTML under this app's list. See that guard's
 : comment for the reasoning.
 :
 : The binding stays because an unbound "ext" prefix is a STATIC XQuery error:
 : it does not merely break the affected element, it takes down the whole
 : compiled transform module and every page with it. It must therefore already
 : be in place at the moment a guideline sync, or a lifted guard, makes any ext:
 : helper reachable again. Keeping the module costs an unused import; getting
 : the order wrong costs a fully broken app. When that happens, add the helpers
 : upstream calls for in the same change.
 :)
module namespace ext="http://history.state.gov/ns/frus/odd-ext";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : The FRUS division subtype of the division containing $node, or "" when there
 : is none.
 :
 : Upstream's "item" models use this to detect index divisions, which render as
 : blocks rather than list items. FRUS carries the value as a teiHeader bibl
 : rather than an attribute -- the same idiom as modules/templates/hsg.xqm
 : ("index", "preface", "table-of-contents", "historical-document", ...).
 :
 : Each division is its own TEI document, so the nearest ancestor TEI is the one
 : to ask -- "[last()]" on the parenthesized (document-order) sequence, i.e. the
 : INNERMOST. That matters in modes that render a division inside its assembled
 : volume: there the outer TEI is the volume, whose header carries no
 : frus-division-subtype, and only the inner one answers. root($node) is the
 : fallback for a bare in-memory fragment with no ancestor TEI at all.
 :)
declare function ext:get-division-subtype($node as node()?) as xs:string {
    let $tei := ($node/ancestor-or-self::tei:TEI)[last()]
    return
        if ($tei) then
            normalize-space(($tei/tei:teiHeader//tei:bibl[@type = 'frus-division-subtype'])[1])
        else
            normalize-space((root($node)//tei:teiHeader//tei:bibl[@type = 'frus-division-subtype'])[1])
};
