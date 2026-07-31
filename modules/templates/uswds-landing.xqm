xquery version "3.1";

(:~
 : USWDS landing-page templating helpers.
 :
 : Theme-owned companion to the landing-page profile's `landing:section`.
 : Two entry points used by `templates/index.html`:
 :
 : * `uswds:section` renders a single authored landing band and emits the
 : `<section class="usa-section …">` wrapper itself, returning the empty
 : sequence when the requested `tei:div[@type=$name]` is absent. That keeps
 : optional bands (highlights, team, about, …) from leaving an empty,
 : padded `usa-section` behind, and lets legacy consumers keep authoring
 : only the bands they use.
 :
 : * `uswds:cards` is the hybrid-data entry point for the card bands
 : (publications, news): it renders a caller-supplied `tei:item*` sequence
 : when given one, otherwise falls back to the items authored in the landing
 : document. Either way the chosen items are wrapped — together with the
 : authored band chrome (head, section-link, bottom action) — into an
 : in-memory `tei:div` and pushed through the same `uswds-landing.odd`
 : rendering path, so dynamic and static content share one layout.
 :)
module namespace uswds = "https://e-editiones.org/ns/templates/uswds";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

import module namespace page = "http://teipublisher.com/ns/templates/page" at "page.xqm";

declare variable $uswds:DEFAULT-ODD := "uswds-landing.odd";

(:~
 : Locate the authored band for $name, honouring the request language.
 :)
declare %private function uswds:band (
    $context as map(*),
    $name as xs:string,
    $root as node()
) as element(tei:div)? {
    let $lang := page:resolve-language($context)
    return head(
        (
            $root//tei:div[@type = $name][@xml:lang = $lang],
            $root//tei:div[@type = $name],
            $root/id($name)
        )
    )
};

declare %private function uswds:render ($context as map(*), $nodes as node()*, $odd as xs:string?) {
    page:transform(
        $nodes,
        map {"browse-url": $context?defaults?browse},
        head(($odd, $uswds:DEFAULT-ODD))
    )
};

(:~
 : Render authored landing band $name inside its own `usa-section` wrapper.
 : Returns () when the band is not authored, so no empty band is emitted.
 :)
declare function uswds:section (
    $context as map(*),
    $name as xs:string,
    $root as node(),
    $odd as xs:string?,
    $classes as xs:string?
) {
    let $band := uswds:band($context, $name, $root)
    return if (empty($band)) then (
    ) else
        <section class="usa-section { normalize-space($classes) }">
            { uswds:render($context, $band, $odd) }
        </section>
};

(:~
 : Hybrid card band. Uses $items when non-empty, else the items authored under
 : `list[@type=$type]/item` of the band. The chosen items plus the authored
 : chrome (head, section-link, bottom action) are re-wrapped into an in-memory
 : `tei:div[@type=$type]` and rendered through the ODD. Returns () when there is
 : nothing to show.
 :)
declare function uswds:cards (
    $context as map(*),
    $type as xs:string,
    $root as node(),
    $odd as xs:string?,
    $items as element()*
) {
    let $band := uswds:band($context, $type, $root)
    let $chosen := if (exists($items)) then
        $items
    else
        $band/tei:list[@type = $type]/tei:item
    return if (empty($chosen)) then (
    ) else
        let $wrapper := <tei:div type="{ $type }">
            {
                $band/tei:head,
                $band/tei:ref[@type = "section-link"],
                <tei:list type="{ $type }">{ $chosen }</tei:list>,
                $band/tei:ref[@type = "action"]
            }
        </tei:div>
        return <section class="usa-section section-{ $type }">
            { uswds:render($context, $wrapper, $odd) }
        </section>
};
