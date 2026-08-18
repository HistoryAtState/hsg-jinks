xquery version "3.1";

(:~
 : Pre-1861 U.S. Congressional Serial Set pages (OP#1303-#1305), a port of
 : hsg-shell's modules/serial-set-html.xqm. The data is one TEI document of
 : bibliographic records (listBibl/bibl, each carrying region/subject terms)
 : in the other-publications data package -- already installed in every
 : container, so no new data provisioning. hsg-shell's hsg-table-bordered
 : becomes USWDS's usa-table (precedent: frus-status.xqm), its
 : hsg-list-unstyled the USWDS unstyled-list classes.
 :)
module namespace sset="https://history.state.gov/ns/templates/serial-set";

declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace page="http://teipublisher.com/ns/templates/page" at "page.xqm";

declare variable $sset:doc := doc("/db/apps/other-publications/serial-set/pre-1861.xml");

declare variable $sset:bibls := $sset:doc//tei:listBibl/tei:bibl;

declare variable $sset:regions := distinct-values($sset:bibls/tei:term[@type = 'region']);

declare variable $sset:subjects := distinct-values($sset:bibls/tei:term[@type = 'subject']);

declare function sset:regions-count($context as map(*)) as xs:integer {
    count($sset:regions)
};

declare function sset:subjects-count($context as map(*)) as xs:integer {
    count($sset:subjects)
};

declare function sset:bibls-count($context as map(*)) as xs:integer {
    count($sset:bibls)
};

(:~
 : The introduction division of the serial-set document, rendered through the
 : app's default ODD. hsg-shell transformed the same nodes with the frus ODD
 : (its own comment calls that a quick hack); the content is plain TEI prose,
 : which the default ODD covers.
 :)
declare function sset:introduction($context as map(*)) {
    page:transform($sset:doc/id('introduction')/tei:head/following-sibling::node())
};

(:~
 : The landing page's browse list: every region with its subjects, each
 : linking into the browse page, with entry counts. Port of
 : ssh:region-subject-list.
 :)
declare function sset:region-subject-list($context as map(*)) as element(ul) {
    <ul class="usa-list usa-list--unstyled">{
        for $region in $sset:regions
        let $regional-subject-entries := $sset:bibls[tei:term[@type = 'region'] = $region]/tei:term[@type = 'subject']
        order by $region
        return
            <li>
                <a href="{$context?context-path}/historicaldocuments/pre-1861/serial-set/browse?region={encode-for-uri($region)}">{$region}</a>
                {" (" || count($regional-subject-entries) || ")"}
                <ul>{
                    for $subject in distinct-values($regional-subject-entries)
                    let $subject-entries := $regional-subject-entries[../tei:term[@type = 'subject'] = $subject]
                    order by $subject
                    return
                        <li>
                            <a href="{$context?context-path}/historicaldocuments/pre-1861/serial-set/browse?region={encode-for-uri($region)}&amp;subject={encode-for-uri($subject)}">{$subject}</a>
                            {" (" || count($subject-entries) || ")"}
                        </li>
                }</ul>
            </li>
    }</ul>
};

(:~
 : The bibl records selected by the browse page's region/subject query
 : parameters: both narrow to records carrying both terms, region alone to
 : the region, neither to the whole set (the /all page and a parameterless
 : /browse). Port of the request-type switch shared by ssh:bibls-filtered-
 : table and ssh:bibls-filtered-count.
 :)
declare %private function sset:filtered-bibls($region as xs:string?, $subject as xs:string?) as element(tei:bibl)* {
    if (exists($region) and exists($subject)) then
        $sset:bibls[tei:term[@type = 'region'] = $region][tei:term[@type = 'subject'] = $subject]
    else if (exists($region)) then
        $sset:bibls[tei:term[@type = 'region'] = $region]
    else
        $sset:bibls
};

declare function sset:filtered-count($context as map(*)) as xs:integer {
    count(sset:filtered-bibls($context?request?parameters?region, $context?request?parameters?subject))
};

(:~
 : The browse page's heading name: "Subject (Region)" when both parameters
 : are set, the region alone otherwise. Port of ssh:region-and-or-subject-name.
 :)
declare function sset:region-and-or-subject-name($context as map(*)) as xs:string? {
    let $region := $context?request?parameters?region
    let $subject := $context?request?parameters?subject
    return
        if (exists($region) and exists($subject)) then
            $subject || " (" || $region || ")"
        else
            $region
};

(:~
 : The browse page's trailing breadcrumbs: the region linking to its browse
 : page, then the subject when set. Port of ssh:region-and-subject-link.
 :)
declare function sset:browse-breadcrumbs($context as map(*)) as element(li)* {
    let $region := $context?request?parameters?region
    let $subject := $context?request?parameters?subject
    let $region-url := $context?context-path || "/historicaldocuments/pre-1861/serial-set/browse?region=" || encode-for-uri(($region, "")[1])
    return (
        if (exists($region)) then
            <li>
                <a href="{$region-url}">{$region}</a>
            </li>
        else
            (),
        if (exists($subject)) then
            <li aria-current="page">{$subject}</li>
        else
            ()
    )
};

(:~
 : The record table, in chronological order. Region/subject columns are
 : dropped when the corresponding query parameter already fixes their value,
 : as the reference did. Port of ssh:bibls-to-table; tolerates an empty
 : selection (header-only table) where the reference required at least one
 : record.
 :)
declare function sset:filtered-table($context as map(*)) as element(table) {
    let $region := $context?request?parameters?region
    let $subject := $context?request?parameters?subject
    let $bibls := sset:filtered-bibls($region, $subject)
    let $cols-to-exclude := (
        if (exists($region)) then 'Region' else (),
        if (exists($region) and exists($subject)) then 'Subject' else ()
    )
    return
        <table class="usa-table">
            <thead>
                <tr>{
                    for $head in ('Region', 'Subject', 'Title', 'Date', 'Citation', 'Pages')[not(. = $cols-to-exclude)]
                    return
                        <th>{$head}</th>
                }</tr>
            </thead>
            <tbody>{
                let $ordered-bibls :=
                    for $bibl in $bibls
                    order by $bibl/tei:date/@when/string()
                    return $bibl
                for $bibl in $ordered-bibls
                let $bibl-region := $bibl/tei:term[@type = 'region']/string()
                let $bibl-subject := $bibl/tei:term[@type = 'subject']/string()
                let $date := $bibl/tei:date/@when/string()
                return
                    <tr>
                        {
                        if ($cols-to-exclude = 'Region') then () else
                            <td>
                                <a href="{$context?context-path}/historicaldocuments/pre-1861/serial-set/browse?region={encode-for-uri($bibl-region)}">{$bibl-region}</a>
                            </td>,
                        if ($cols-to-exclude = 'Subject') then () else
                            <td>
                                <a href="{$context?context-path}/historicaldocuments/pre-1861/serial-set/browse?region={encode-for-uri($bibl-region)}&amp;subject={encode-for-uri($bibl-subject)}">{$bibl-subject}</a>
                            </td>
                        }
                        <td>{$bibl/tei:title/string()}</td>
                        <td>{
                            if ($date castable as xs:date) then
                                format-date(adjust-date-to-timezone(xs:date($date), ()), '[MNn] [D], [Y]')
                            else
                                $date
                        }</td>
                        <td>{$bibl/tei:bibl/string()}</td>
                        <td>{$bibl/tei:extent/tei:measure/@quantity/string()}</td>
                    </tr>
            }</tbody>
        </table>
};
