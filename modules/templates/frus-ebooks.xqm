xquery version "3.1";

(:~
 : Templating functions for the Foreign Relations Ebooks page (OP#1293).
 :
 : Ports hsg-shell's fh:volumes-with-ebooks / fh:frus-ebooks-catalog /
 : fh:frus-history-ebook-entry (modules/frus-html.xqm) plus their app.xqm
 : helpers (app:bytes-to-readable, app:format-date-month-long-day-year) to
 : this repo's jinks templating conventions and the frus-v2-data encoding,
 : where a volume's ebook relatedItems live in the volume root document's
 : teiHeader/notesStmt rather than in a monolithic volume file.
 :)
module namespace ebooks="https://history.state.gov/ns/templates/frus-ebooks";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace xi="http://www.w3.org/2001/XInclude";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "../config.xqm";

(:~
 : Database path of the frus-history monograph, published by the separately
 : installed frus-history data package. The catalog's monograph entry is
 : gated on this document's availability (see ebooks:frus-history-entry),
 : so an instance without the package just renders the volume list.
 :)
declare variable $ebooks:frus-history-monograph := "/db/apps/frus-history/monograph/frus-history.xml";

(:~
 : Resolve one fragment of a volume header by name (titleStmt, seriesStmt,
 : publicationStmt): inline at the chapter/compilation level, but xincluded
 : from the volume's shared *_includes.xml at the volume-root level
 : (frus-unbound-alpha), where plain descendant steps don't see across the
 : unexpanded xi:include. Local copy of hsg:resolve-include
 : (modules/templates/hsg.xqm), which is %private there.
 :)
declare %private function ebooks:resolve-include($header as element()?, $name as xs:string) as element()? {
    let $inline := $header/tei:fileDesc/*[local-name() = $name]
    return
        if (exists($inline)) then $inline
        else
            let $inc := $header//xi:include[@xpointer = $name]
            return
                if (not(exists($inc))) then ()
                else id($name, doc(util:collection-name($inc) || '/' || $inc/@href))
};

(:~
 : Every volume root that carries a volume-scoped epub relatedItem.
 : Reference parity with fh:volumes-with-ebooks, with the v2 twist that a
 : volume's notesStmt also carries relatedItems for *associated files*
 : (frus1958-60v05mSupp has one type="pdf" entry per microfiche document),
 : told apart from the volume's own ebook solely by @corresp pointing at
 : the volume id -- the same gate hsg:volume-ways-to-explore and
 : hsg-shell's fh:exists-epub apply.
 :)
declare function ebooks:volumes-with-ebooks() as element(tei:TEI)* {
    for $vol in collection($config:data-default)//tei:relatedItem[@type eq "epub"]/root(.)/tei:TEI
    where exists($vol/tei:teiHeader//tei:notesStmt/tei:relatedItem[@type eq "epub"][@corresp = "#" || $vol/@xml:id])
    return $vol
};

(:~
 : Format a byte count the way hsg-shell's app:bytes-to-readable does: over
 : 1,000,000 bytes as N.NNmb, over 1,000 as Nkb (same rounding). The
 : sub-kilobyte fallback returns the raw count instead of the reference's
 : empty sequence, so a link label can never end up as "EPUB ()".
 :)
declare %private function ebooks:bytes-to-readable($bytes as xs:integer?) as xs:string {
    if (empty($bytes)) then 'unknown'
    else if ($bytes gt 1000000) then (round($bytes div 10000) div 100) || 'mb'
    else if ($bytes gt 1000) then round($bytes div 1000) || 'kb'
    else $bytes || ' bytes'
};

(:~
 : "December 8, 2020"-style date, ported from app:format-date-month-long-day-year.
 : The v2 relatedItem publication dates are dateTimes with a timezone
 : (e.g. 2020-12-08T15:19:49.000Z), so dateTime and date are both handled,
 : normalized to UTC first -- same as the reference helper.
 :)
declare function ebooks:format-date-month-long-day-year($date) as xs:string {
    typeswitch($date)
    case xs:dateTime return
        $date
        => adjust-dateTime-to-timezone(xs:dayTimeDuration("PT0H"))
        => format-dateTime('[MNn] [D], [Y0001]', 'en', (), 'US')
    case xs:date return
        $date
        => adjust-date-to-timezone(xs:dayTimeDuration("PT0H"))
        => format-date('[MNn] [D], [Y0001]', 'en', (), 'US')
    default return
        if ($date castable as xs:dateTime) then
            ebooks:format-date-month-long-day-year(xs:dateTime($date))
        else if ($date castable as xs:date) then
            ebooks:format-date-month-long-day-year(xs:date($date))
        else
            error(xs:QName('ebooks:format-date'), 'Could not recognise "' || $date || '" as a date')
};

(:~
 : One EPUB/Mobi/PDF download link, styled as a USWDS outline button (this
 : repo's chrome) instead of hsg-shell's hsg-link-button. Rendered only when
 : the format's relatedItem exists, so a volume missing one format omits
 : that link rather than emitting an empty href (deliberate divergence from
 : the reference, which renders both links unconditionally).
 :)
declare %private function ebooks:download-link($item as element(tei:relatedItem)?, $label as xs:string) as element(li)? {
    if (not(exists($item))) then ()
    else
        let $url := ($item//tei:ref/@target/string())[1]
        let $size := ebooks:bytes-to-readable(($item//tei:measure/@quantity)[1] ! xs:integer(.))
        return
            <li>
                <a class="usa-button usa-button--outline" href="{$url}">{$label} ({$size})</a>
            </li>
};

(:~
 : The ebook catalog: count line, one entry per volume with an epub (cover
 : thumb, linked title, last-updated date, download buttons, hr separator),
 : then the frus-history monograph entry when its package is installed.
 : Reference parity with fh:frus-ebooks-catalog, including the count line's
 : "+ 1" for the monograph -- applied only when the monograph entry
 : actually renders, so the number always matches the list.
 :
 : Titles come from the resolved seriesStmt rather than the reference's
 : whole-document title scan (the v2 volume root xincludes its seriesStmt;
 : see ebooks:resolve-include), joined exactly like the reference:
 : italicized series title, then sub-series/volume-number/volume joined
 : with ", " -- including an empty slot when a volume has no volume-number
 : (frus1861 renders "..., 1861, , At the Commencement ...", same as the
 : live reference page).
 :)
declare function ebooks:catalog($context as map(*)) as element(div) {
    let $vols-with-ebooks := ebooks:volumes-with-ebooks()
    let $frus-history-entry := ebooks:frus-history-entry($context)
    return
        <div id="catalog">
            <p>The following {count($vols-with-ebooks) + count($frus-history-entry)} volumes are currently available:</p>
            {
            for $vol in $vols-with-ebooks
            let $vol-id := $vol/@xml:id/string()
            let $seriesStmt := ebooks:resolve-include($vol/tei:teiHeader, 'seriesStmt')
            let $title-series := normalize-space($seriesStmt/tei:title[@type eq "series"][1])
            let $title-rest := string-join(
                $seriesStmt/tei:title[@type = ("sub-series", "volume-number", "volume")] ! normalize-space(.), ", ")
            let $related := $vol/tei:teiHeader//tei:notesStmt/tei:relatedItem[@corresp = "#" || $vol-id]
            let $epub := ($related[@type eq "epub"])[1]
            let $mobi := ($related[@type eq "mobi"])[1]
            let $ebook-last-updated := ebooks:format-date-month-long-day-year(($epub//tei:date/@when)[1])
            order by $vol-id
            return
                (
                <div id="{$vol-id}">
                    <img src="https://static.history.state.gov/frus/{$vol-id}/covers/{$vol-id}-thumb.jpg"
                        alt="Book cover of {$title-series}, {$title-rest}"
                        style="width: 67px; height: 100px; float: left; padding-right: 10px"/>
                    <a href="{$context?context-path}/historicaldocuments/{$vol-id}"><em>{$title-series}</em>, {$title-rest}</a>
                    <p>Ebook last updated: {$ebook-last-updated}</p>
                    <ul class="hsg-ebook-list">
                        {ebooks:download-link($epub, 'EPUB')}
                        {ebooks:download-link($mobi, 'Mobi')}
                    </ul>
                </div>
                ,
                <hr class="space"/>
                )
            ,
            if (exists($frus-history-entry)) then ($frus-history-entry, <hr class="space"/>) else ()
            }
        </div>
};

(:~
 : The FRUS History monograph's catalog entry, appended after the volume
 : list. Reference parity with fh:frus-history-ebook-entry, guarded on the
 : monograph document's availability so an instance without the
 : frus-history package omits the entry (and its "+ 1" in the count line)
 : cleanly. The complete title is rendered inline (tei:hi[@rend='italic']
 : as <em>) rather than through the reference's ODD pipeline -- app chrome,
 : not TEI content rendering.
 :)
declare %private function ebooks:frus-history-entry($context as map(*)) as element(div)? {
    if (not(doc-available($ebooks:frus-history-monograph))) then ()
    else
        let $book := doc($ebooks:frus-history-monograph)
        let $book-title := ($book//tei:title[@type eq 'complete'])[1]/node() ! ebooks:title-html(.)
        let $relatedItems := $book//tei:relatedItem
        let $epub-item := ($relatedItems[@type eq "epub"])[1]
        let $mobi-item := ($relatedItems[@type eq "mobi"])[1]
        let $pdf-item := ($relatedItems[@type eq "pdf"])[1]
        let $last-updated := ebooks:format-date-month-long-day-year(($epub-item//tei:date/@when)[1])
        return
            <div id="frus-history">
                <img src="https://static.history.state.gov/frus-history/covers/frus-history-thumb.png"
                    alt="Book cover of the FRUS History monograph"
                    style="width: 67px; height: 100px; float: left; padding-right: 10px"/>
                <a href="{$context?context-path}/historicaldocuments/frus-history">{$book-title}</a>
                <p>Ebook last updated: {$last-updated}.</p>
                <ul class="hsg-ebook-list">
                    {ebooks:download-link($epub-item, 'EPUB')}
                    {ebooks:download-link($mobi-item, 'Mobi')}
                    {ebooks:download-link($pdf-item, 'PDF')}
                </ul>
            </div>
};

(:~ Minimal inline rendering of the monograph title: italic hi as <em>,
 : any other markup flattened to its text. :)
declare %private function ebooks:title-html($node as node()) {
    typeswitch ($node)
    case text() return $node
    case element(tei:hi) return <em>{$node/node() ! ebooks:title-html(.)}</em>
    case element() return $node/node() ! ebooks:title-html(.)
    default return ()
};
