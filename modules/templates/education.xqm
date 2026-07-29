xquery version "3.1";

module namespace edu="https://history.state.gov/ns/templates/education";

import module namespace page="http://teipublisher.com/ns/templates/page" at "page.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : Retired "Education Resources" section (#1100): the epic's "no-ODD"
 : record-rendering concern (#1171's data-transformation decision) applied to
 : a tiny, frozen dataset -- 8 flat, unnamespaced <module> records (not TEI),
 : joined by tei-document-name to 7 small single-division TEI introduction
 : documents. Same technique as departmenthistory's POCOM section
 : (modules/templates/departmenthistory.xqm), just at a much smaller scale:
 : plain collection() scans, HTML built via direct element constructors, no
 : ODD <model> involved for the record side. The TEI intro documents
 : themselves render via page:transform (#1171's "option 1: keep TEI, render
 : with global ODD"), invoked from the module template the same way
 : dh:monograph-section-content does -- not via vapi:view/$context?doc: a
 : vapi:view route's default hsg-content.html breadcrumb block
 : ($context?doc truthy) wins over a leaf template's own [% template
 : breadcrumb %] override in this templating engine (confirmed live:
 : hsg:collection-breadcrumbs' generic "historicaldocuments" fallback
 : rendered instead of edu:breadcrumb). departmenthistory never hits this
 : because every one of its routes, including its TEI monograph pages, goes
 : through vapi:html with content re-resolved from request parameters
 : instead -- the same proven pattern this module follows for the module
 : detail page too.
 :)
declare variable $edu:MODULES_COL := "/db/apps/other-publications/education/modules";
declare variable $edu:INTROS_COL := "/db/apps/other-publications/education/introductions";

(:~
 : Every published module, ordered by year-published descending. Single
 : shared sort point -- both the sidebar and the full listing call this (or
 : a thin wrapper), fixing hsg-shell's own logged bug (#1169): its
 : edu:modules-sidebar iterated the record collection in document order while
 : edu:list-modules-full sorted by year-published descending, so the two
 : lists on the same page disagreed. The in-preparation module
 : (published-status = 'in-preparation') is excluded here, at the one shared
 : source, rather than filtered separately by each caller.
 :)
declare function edu:published-modules() as element(module)* {
    for $module in collection($edu:MODULES_COL)/modules/module[published-status eq 'published']
    order by xs:integer($module/year-published) descending
    return $module
};

(:~
 : moduleId is the module record's tei-document-name (e.g. "documents-intro"),
 : NOT its own id field (e.g. "documents-on-diplomacy") -- the two are
 : unrelated slugs. The in-preparation module has an empty tei-document-name,
 : so it can never match a non-empty $moduleId here -- the 404 in
 : eduapi:view-module falls out for free, no special-cased guard needed.
 :)
declare function edu:module-by-tei-document-name($moduleId as xs:string) as element(module)? {
    edu:published-modules()[tei-document-name eq $moduleId]
};

declare function edu:intro-doc-path($module as element(module)) as xs:string {
    $edu:INTROS_COL || "/" || $module/tei-document-name || ".xml"
};

declare function edu:module-intro-doc($module as element(module)) as document-node() {
    doc(edu:intro-doc-path($module))
};

(:~
 : Sidebar list, year-descending -- same order as edu:list-modules-full,
 : the #1169 ordering-bug fix.
 :)
declare function edu:modules-sidebar($context as map(*)) as element(ul) {
    <ul class="usa-sidenav">
    {
        for $module in edu:published-modules()
        return
            <li class="usa-sidenav__item">
                <a href="{$context?context-path}/education/modules/{$module/tei-document-name}">{$module/title/string()}</a>
            </li>
    }
    </ul>
};

(:~
 : Abbreviated prose list for the landing page, ported directly from
 : hsg-shell's edu:list-modules-brief: "Title (year); Title (year); and
 : Title (year)." -- semicolon between items, "; and" before the last, a
 : period after the last.
 :)
declare function edu:list-modules-brief($context as map(*)) as element(ol) {
    let $modules := edu:published-modules()
    let $last := count($modules)
    return
        <ol>
        {
            for $module at $pos in $modules
            let $punctuation :=
                if ($pos = $last - 1) then
                    "; and"
                else if ($pos = $last) then
                    "."
                else
                    ";"
            return
                <li><strong>{$module/title/string()}</strong> ({$module/year-published/string()}){$punctuation}</li>
        }
        </ol>
};

(:~
 : Availability/download line shared by the full listing (teaser) and the
 : module detail page (full block): mail-order link when
 : availability-status = 'available', "out of print" text when
 : 'out-of-print'. Neither value appears empty among the 7 live records
 : (verified 2026-07-29 against the seeded devcontainer), but an empty/other
 : value renders no availability text rather than guessing.
 :)
declare %private function edu:availability-text($module as element(module)) as item()* {
    let $status := $module/availability-status/string()
    return
        if ($status eq 'available') then
            (<a href="http://videodirect.state.gov/">Available for mail order</a>, text { "." })
        else if ($status eq 'out-of-print') then
            text { "Sorry, this title is out of print." }
        else
            ()
};

(:~
 : Full module listing (#1169), usa-collection markup -- same shape as
 : departmenthistory's person/secretaries listings
 : (modules/templates/departmenthistory.xqm). Teaser text is the first
 : paragraph of the module's own TEI introduction, joined by
 : tei-document-name (same join hsg-shell's edu:list-modules-full performed).
 :)
declare function edu:list-modules-full($context as map(*)) as element(ul) {
    <ul class="usa-collection">
    {
        for $module in edu:published-modules()
        let $intro := edu:module-intro-doc($module)
        let $teaser := normalize-space($intro//tei:body/tei:div[1]/tei:p[1])
        return
            <li class="usa-collection__item">
                <div class="usa-collection__body">
                    <h3 class="usa-collection__heading">
                        <a href="{$context?context-path}/education/modules/{$module/tei-document-name}">{$module/title/string()}</a>
                    </h3>
                    {if ($teaser != '') then <p class="usa-collection__description">{$teaser}</p> else ()}
                    <p class="usa-collection__meta">
                        Published in {$module/year-published/string()}.
                        {edu:availability-text($module)}
                    </p>
                </div>
            </li>
    }
    </ul>
};

(:~
 : Download URL convention ported from hsg-shell's edu:module-introduction:
 : static.history.state.gov/edu-modules/{file/name}, an inline literal
 : string prefix -- this repo has no shared $s3static-equivalent variable,
 : other sections' ODDs inline the same static.history.state.gov prefix
 : directly, so this follows suit rather than inventing one for just this
 : module.
 :)
declare variable $edu:S3_EDU_MODULES := "https://static.history.state.gov/edu-modules/";

(:~
 : Module detail page's availability/download block (#1170), usa-summary-box
 : markup: heading + body text + download link built from the module
 : record's own files/file/name+label. See doc/... USWDS reference for
 : usa-summary-box markup shape -- first use of this component in this repo.
 :)
declare function edu:module-availability-block($module as element(module)) as element(div) {
    <div class="usa-summary-box" role="region" aria-labelledby="edu-availability-heading">
        <div class="usa-summary-box__body">
            <h3 class="usa-summary-box__heading" id="edu-availability-heading">Availability</h3>
            <div class="usa-summary-box__text">
                <p>{edu:availability-text($module)}</p>
                {
                    let $file := $module/files/file
                    return
                        if (exists($file)) then
                            <p>Download the <a href="{$edu:S3_EDU_MODULES}{$file/name/string()}">{$file/label/string()}</a>.</p>
                        else
                            ()
                }
            </div>
        </div>
    </div>
};

(:~
 : Static section breadcrumb: Home > Education Resources > $trail. Same
 : pattern as dh:breadcrumb (modules/templates/departmenthistory.xqm):
 : $trail as a sequence of maps { "label": ..., "href": ... }, NOT an array
 : -- an array literal's closing "]]" collides with this templating engine's
 : "[[ ... ]]" expression delimiter.
 :)
declare function edu:breadcrumb($context as map(*), $trail as map(*)*) as element(li)+ {
    (
        <li>
            <a href="{$context?context-path}/">
                <pb-i18n key="breadcrumb.home">Home</pb-i18n>
            </a>
        </li>,
        if (empty($trail)) then
            <li aria-current="page">Education Resources</li>
        else
            <li>
                <a href="{$context?context-path}/education">Education Resources</a>
            </li>,
        for $crumb at $pos in $trail
        return
            if ($pos = count($trail)) then
                <li aria-current="page">{$crumb?label}</li>
            else
                <li>
                    <a href="{$context?context-path}{$crumb?href}">{$crumb?label}</a>
                </li>
    )
};

(:~
 : Resolves the requesting module from the moduleId request parameter --
 : re-resolved independently at each template call site, same reason
 : dh:current-section documents: there is no way to share a `let` binding
 : across separate [% template %] blocks.
 :)
declare function edu:current-module($context as map(*)) as element(module)? {
    edu:module-by-tei-document-name($context?request?parameters?moduleId)
};

(:~
 : Module detail page's TEI body (#1170), same technique
 : dh:monograph-section-content uses: page:transform on the whole
 : introduction document, global ODD, "division" mode -- there is no
 : interior division route for this section (every intro is one flat
 : tei:div), so this renders the complete document rather than resolving to
 : a specific division.
 :)
declare function edu:module-content($context as map(*)) as element()* {
    let $module := edu:current-module($context)
    let $doc := edu:module-intro-doc($module)
    return page:transform($doc, map { "mode": "division" })
};
