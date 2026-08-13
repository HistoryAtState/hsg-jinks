xquery version "3.1";

(:~
 : Status of the Foreign Relations Series report (OP#1292), a port of
 : hsg-shell's fh:load-status-of-the-series and its rendering helpers
 : (modules/frus-html.xqm): the volume sets are computed once from the FRUS
 : volumes' revision metadata (teiHeader/revisionDesc), and each section is
 : rendered only when its set is non-empty -- the same toggling hsg-shell did
 : with request attributes and templates:if-parameter-set, kept in XQuery
 : here because jinks templates have no equivalent mechanism.
 :
 : v2 data adaptations (frus-v2-data, one collection per volume):
 : - revisionDesc and its change entries live inline in the volume root
 :   document (<volid>/<volid>.xml), so the reference's change/@status/@when/
 :   @to/@corresp queries carry over unchanged.
 : - titleStmt/seriesStmt are xincluded from the volume's shared
 :   *_includes.xml rather than inline, so the complete title is resolved
 :   through the same follow-the-include pattern as hsg:resolve-include in
 :   hsg.xqm (private there, replicated here).
 : - a chapter referenced by change/@corresp="#chN" is its own TEI document
 :   in the volume collection (identified by bibl[@type='frus-division-id']),
 :   not a div resolvable with $vol/id() as in the monolithic v1 volumes.
 :)
module namespace status="https://history.state.gov/ns/templates/frus-status";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace xi="http://www.w3.org/2001/XInclude";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "../config.xqm";

declare variable $status:SERIES-PREFIX := "Foreign Relations of the United States, ";

(:~
 : The full report: every conditional section of the page, in reference
 : order. Ported from fh:load-status-of-the-series; the section wrapper divs
 : match the reference markup (where templates:if-parameter-set left the
 : wrapping div in place around each h2 + list). "Volumes in Progress" is
 : the one unconditional heading, as in the reference.
 :)
declare function status:report($context as map(*)) as element()* {
    let $this-year := xs:string(year-from-date(current-date()))
    let $last-year := xs:string(year-from-date(current-date()) - 1)
    let $data := collection($config:data-default)
    let $published-this-year := $data//tei:change[@status eq "published"][starts-with(@when, $this-year)]/root(.)/tei:TEI
    let $published-last-year := $data//tei:change[@status eq "published"][starts-with(@when, $last-year)]/root(.)/tei:TEI
    let $anticipated-this-year := $data//tei:change[@status eq "being-cleared"][starts-with(@to, $this-year)]/root(.)/tei:TEI
    let $chapters-outstanding := $data//tei:revisionDesc[@status eq "partially-published"]/root(.)/tei:TEI
    let $being-cleared := $data//tei:change[@status eq "being-cleared"]/root(.)/tei:TEI
    let $being-researched := $data//tei:change[@status eq "being-researched"]/root(.)/tei:TEI
    let $planned := $data//tei:change[@status eq "planned"]/root(.)/tei:TEI
    let $being-digitized := $data//tei:revisionDesc[@status eq "being-digitized"]/root(.)/tei:TEI
    return (
        if (exists($published-last-year)) then
            <div>
                <h2>Published in {$last-year}</h2>
                {status:list-published-volumes($context, $published-last-year, $last-year)}
            </div>
        else (),
        if (exists($published-this-year)) then
            <div>
                <h2>Published in {$this-year}</h2>
                {status:list-published-volumes($context, $published-this-year, $this-year)}
            </div>
        else (),
        if (exists($anticipated-this-year)) then
            <div>
                <h2>Anticipated in {$this-year}</h2>
                {status:list-anticipated-volumes($context, $anticipated-this-year)}
            </div>
        else (),
        if (exists($chapters-outstanding)) then
            <div>
                <h2>Volumes with Chapters Outstanding</h2>
                {status:volumes-with-chapters-outstanding($context, $chapters-outstanding)}
            </div>
        else (),
        <h2>Volumes in Progress</h2>,
        if (exists($being-cleared)) then
            <div>
                <h3>Being Cleared</h3>
                {status:list-in-production-volumes($context, $being-cleared)}
            </div>
        else (),
        if (exists($being-researched)) then
            <div>
                <h3>Being Researched</h3>
                {status:list-in-production-volumes($context, $being-researched)}
            </div>
        else (),
        if (exists($planned)) then
            <div>
                <h3>Planned</h3>
                {status:list-in-production-volumes($context, $planned)}
            </div>
        else (),
        if (exists($being-digitized)) then
            <div>
                <h2>Published Volumes Being Digitized</h2>
                {status:list-in-production-volumes($context, $being-digitized)}
            </div>
        else ()
    )
};

(:~
 : Volumes published in a given year, ordered by publication date then id,
 : each with its publication date -- or, for an incrementally published
 : volume (one with chapter-level change entries), a disc sub-list of the
 : chapters published in that year. Port of fh:list-published-volumes.
 :)
declare %private function status:list-published-volumes($context as map(*),
        $volumes as element(tei:TEI)*, $year as xs:string?) as element(ol) {
    <ol>{
        for $vol in $volumes
        let $vol-id := $vol/@xml:id/string()
        let $vol-title := status:short-title($vol)
        let $vol-published := ($vol//tei:change[@corresp eq "#" || $vol-id])[1]
        let $vol-published-date := status:published-date-to-english($vol-published/@when/string())
        let $chapters := $vol//tei:change[starts-with(@corresp, "#ch")]
        let $published-chapters := $chapters[@status eq "published"]
        let $chapters-to-list :=
            if (exists($year)) then $published-chapters[starts-with(@when, $year)]
            else $published-chapters
        order by $vol-published/@when, $vol-id
        return
            if (empty($chapters)) then
                <li>
                    <a href="{$context?context-path}/historicaldocuments/{$vol-id}">{$vol-title}</a>
                    {if (exists($vol-published-date)) then " (" || $vol-published-date || ")" else ()}
                </li>
            else
                <li>
                    <a href="{$context?context-path}/historicaldocuments/{$vol-id}">{$vol-title}</a>
                    <ul>{
                        for $chapter in $chapters-to-list
                        let $div-id := substring-after($chapter/@corresp, "#")
                        let $division := status:division($vol-id, $div-id)
                        let $published-date := status:published-date-to-english($chapter/@when/string())
                        where exists($division)
                        return
                            <li>
                                <a href="{$context?context-path}/historicaldocuments/{$vol-id}/{$div-id}">{status:division-title($division)}</a>
                                {if (exists($year) and exists($published-date)) then " (" || $published-date || ")" else ()}
                            </li>
                    }</ul>
                </li>
    }</ol>
};

(:~
 : Volumes with a publication anticipated this year, each with a disc
 : sub-list of the chapters awaiting release (@status "being-cleared" with a
 : non-empty @to); chapter entries link to their chapter page only when some
 : of the volume is already published. Port of fh:list-anticipated-volumes.
 :)
declare %private function status:list-anticipated-volumes($context as map(*),
        $volumes as element(tei:TEI)*) as element(ol) {
    <ol>{
        for $vol in $volumes
        let $vol-id := $vol/@xml:id/string()
        let $vol-title := status:short-title($vol)
        let $chapters := $vol//tei:change[starts-with(@corresp, "#ch")]
        let $some-published := $vol//tei:revisionDesc[@status = ("published", "partially-published")]
        let $chapters-anticipated := $chapters[@status eq "being-cleared"][@to ne ""]
        order by $vol-id
        return
            if (empty($chapters)) then
                <li>
                    <a href="{$context?context-path}/historicaldocuments/{$vol-id}">{$vol-title}</a>
                </li>
            else
                <li>
                    <a href="{$context?context-path}/historicaldocuments/{$vol-id}">{$vol-title}</a>
                    {status:chapter-sublist($context, $vol-id, $chapters-anticipated, exists($some-published))}
                </li>
    }</ol>
};

(:~
 : Volumes at one stage of production (being cleared / being researched /
 : planned / being digitized); an incrementally published volume gets a disc
 : sub-list of its chapters still in clearance. Port of
 : fh:list-in-production-volumes.
 :)
declare %private function status:list-in-production-volumes($context as map(*),
        $volumes as element(tei:TEI)*) as element(ol) {
    <ol>{
        for $vol in $volumes
        let $vol-id := $vol/@xml:id/string()
        let $vol-title := status:short-title($vol)
        let $chapters := $vol//tei:change[starts-with(@corresp, "#ch")]
        let $some-published := $vol//tei:revisionDesc[@status = ("published", "partially-published")]
        let $chapters-anticipated := $chapters[@status eq "being-cleared"]
        order by $vol-id
        return
            if (empty($chapters)) then
                <li>
                    <a href="{$context?context-path}/historicaldocuments/{$vol-id}">{$vol-title}</a>
                </li>
            else
                <li>
                    <a href="{$context?context-path}/historicaldocuments/{$vol-id}">{$vol-title}</a>
                    {status:chapter-sublist($context, $vol-id, $chapters-anticipated, exists($some-published))}
                </li>
    }</ol>
};

(:~
 : A volume entry's chapter sub-list (shared by the anticipated and
 : in-production lists, whose reference implementations differ only in how
 : they select the chapters): the chapter title, linked to the chapter page
 : when part of the volume is already published (so the route resolves),
 : plain text otherwise. The reference's style="list-style-type: disc" is
 : dropped -- disc is the ul default.
 :)
declare %private function status:chapter-sublist($context as map(*), $vol-id as xs:string,
        $chapters as element(tei:change)*, $linked as xs:boolean) as element(ul) {
    <ul>{
        for $chapter in $chapters
        let $div-id := substring-after($chapter/@corresp, "#")
        let $division := status:division($vol-id, $div-id)
        where exists($division)
        return
            <li>{
                if ($linked) then
                    <a href="{$context?context-path}/historicaldocuments/{$vol-id}/{$div-id}">{status:division-title($division)}</a>
                else
                    status:division-title($division)
            }</li>
    }</ul>
};

(:~
 : The partially released volumes as a bordered 3-column table (volume /
 : chapters in clearance / chapters published), the chapter cells grouped by
 : year -- clearance chapters by @from, published chapters by the year of
 : @when. Port of fh:volumes-with-chapters-outstanding; hsg-shell's
 : hsg-table-bordered becomes USWDS's usa-table. The reference's guard that
 : @corresp resolve to a real div maps to the division document existing in
 : the volume collection -- which also drops the volume-level published
 : change (@corresp "#<vol-id>") from the published column, as the
 : reference's div check did.
 :)
declare %private function status:volumes-with-chapters-outstanding($context as map(*),
        $volumes as element(tei:TEI)*) as element(table) {
    <table class="usa-table">
        <thead>
            <tr>
                <th>Volume title</th>
                <th>Chapters in Clearance</th>
                <th>Chapters Published</th>
            </tr>
        </thead>
        <tbody>{
            for $vol in $volumes
            let $vol-id := $vol/@xml:id/string()
            let $vol-title := status:short-title($vol)
            let $chapters-in-clearance := $vol//tei:change[@status eq "being-cleared"]
            let $chapters-published := $vol//tei:change[@status eq "published"]
            order by $vol-id
            return
                <tr>
                    <td>
                        <a href="{$context?context-path}/historicaldocuments/{$vol-id}">{$vol-title}</a>
                    </td>
                    <td>{
                        for $chapter-group in $chapters-in-clearance
                        group by $year := $chapter-group/@from/string()
                        return status:chapter-year-group($context, $vol-id, $year, $chapter-group)
                    }</td>
                    <td>{
                        for $chapter-group in $chapters-published
                        group by $year := substring($chapter-group/@when, 1, 4)
                        return status:chapter-year-group($context, $vol-id, $year, $chapter-group)
                    }</td>
                </tr>
        }</tbody>
    </table>
};

(:~ One year group inside a table cell: the year, then the resolvable
 : chapters of that year as linked list items. :)
declare %private function status:chapter-year-group($context as map(*), $vol-id as xs:string,
        $year as xs:string, $chapters as element(tei:change)*) as element(div) {
    <div>
        <u>{$year}</u>
        <ul>{
            for $chapter in $chapters
            let $div-id := substring-after($chapter/@corresp, "#")
            let $division := status:division($vol-id, $div-id)
            where exists($division)
            return
                <li>
                    <a href="{$context?context-path}/historicaldocuments/{$vol-id}/{$div-id}">{status:division-title($division)}</a>
                </li>
        }</ul>
    </div>
};

(:~
 : Resolve one fragment of a volume root's header by name (titleStmt,
 : seriesStmt, ...): inline when present, otherwise followed through the
 : xi:include pointing at the volume's shared *_includes.xml. Same pattern
 : as hsg:resolve-include in hsg.xqm (private there); see its comment on why
 : the specific include is followed directly rather than util:expand()ing
 : the header (which would also try to resolve encodingDesc's remote
 : https:// include).
 :)
declare %private function status:resolve-include($header as element()?, $name as xs:string) as element()? {
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
 : The volume title shown in every list and table: the complete title with
 : the leading series name stripped ("1977-1980, Volume XXVII, Western
 : Europe"). In the v2 headers title[@type='complete'] lives in the
 : xincluded seriesStmt, not titleStmt. Where the reference's published list
 : applied substring-after unconditionally (yielding an empty title for a
 : volume outside the main series, e.g. frus1861), the fallback to the full
 : complete title that the reference's other lists already used is applied
 : everywhere here.
 :)
declare %private function status:short-title($vol as element(tei:TEI)) as xs:string {
    let $seriesStmt := status:resolve-include($vol/tei:teiHeader, "seriesStmt")
    let $complete := normalize-space(($seriesStmt/tei:title[@type eq "complete"])[1])
    return
        if (starts-with($complete, $status:SERIES-PREFIX)) then
            substring-after($complete, $status:SERIES-PREFIX)
        else
            $complete
};

(:~
 : The division document a change/@corresp chapter id names: in the v2 data
 : each division is its own TEI file inside the volume collection, keyed by
 : bibl[@type='frus-division-id'] in its header -- the id() lookup the
 : reference used inside the monolithic volume does not apply. An
 : unresolvable id (including the volume-level "#<vol-id>" change entries)
 : returns empty, which callers use as the reference's div-existence guard.
 :)
declare %private function status:division($vol-id as xs:string, $div-id as xs:string) as element(tei:TEI)? {
    (collection($config:data-default || "/" || $vol-id)
        /tei:TEI[tei:teiHeader//tei:bibl[@type eq "frus-division-id"] = $div-id])[1]
};

(:~ A division's display title, from its own titleStmt (which equals its
 : body head in this corpus, e.g. "Canada"); joined without a separator as
 : hsg:toc-entries does for split titles. :)
declare %private function status:division-title($division as element(tei:TEI)) as xs:string {
    normalize-space(string-join($division//tei:fileDesc//tei:titleStmt/tei:title, ''))
};

(:~
 : "December 1" from 2020-12-01: port of fh:published-date-to-english,
 : hardened for the v2 corpus, where a change/@when is not always a full
 : date (frus1958-60v05mSupp has @when="", frus1861 has @when="1861" --
 : both would make the reference's xs:date() cast fail): a non-date @when
 : yields empty, and callers omit the parenthesized date.
 :)
declare %private function status:published-date-to-english($when as xs:string?) as xs:string? {
    if ($when castable as xs:date) then
        let $date := xs:date($when)
        let $english-months := ('January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December')
        return $english-months[month-from-date($date)] || ' ' || day-from-date($date)
    else ()
};
