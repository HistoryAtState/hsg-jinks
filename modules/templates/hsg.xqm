xquery version "3.1";

module namespace hsg="https://history.state.gov/ns/templates/hsg";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace xi="http://www.w3.org/2001/XInclude";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "../config.xqm";
import module namespace page="http://teipublisher.com/ns/templates/page" at "page.xqm";
import module namespace global="http://e-editiones.org/tei-publisher/odd-global" at "../odd-global.xqm";

(:~
 : Build an absolute, externally-resolvable URL for a path relative to this
 : app's own root -- for content consumed outside any browser/page context
 : (OPDS feed ids and links, and anything else that must not emit a
 : root-relative href). Central home per PR #26 review: use this instead of
 : re-deriving scheme/host/port at the call site. Mirrors the technique of
 : modules/lib/api/iiif.xql's iiif:link (scheme + server-name + non-default
 : port + $config:context-path); that file is jinks-managed and so keeps its
 : own private copy rather than importing from here.
 :)
declare function hsg:absolute-url($relpath as xs:string) as xs:string {
    let $host := request:get-scheme() || "://" || request:get-server-name()
    let $port :=
        if (request:get-server-port() = (80, 443)) then
            ()
        else
            ":" || request:get-server-port()
    return
        string-join(($host, $port, replace($config:context-path || "/" || $relpath, "//", "/")))
};

(:~
 : Resolve one fragment of a header by name (titleStmt, publicationStmt,
 : seriesStmt): inline at the volume root's chapter/compilation level, but
 : xincluded from the volume's shared *_includes.xml at the volume-root
 : level (frus-unbound-alpha) -- so check for an inline child first. Plain
 : descendant steps like // don't see across an unexpanded xi:include; this
 : follows the specific include named by $name directly (doc() + id(), the
 : same pattern already used for footnotes in resources/odd/hsg-jinks.odd
 : and hsg:document-range below) rather than util:expand()ing the whole
 : header, which would also expand (and so attempt to resolve) teiHeader's
 : unrelated encodingDesc include -- a remote https:// URL -- for callers
 : that only want a title.
 :)
declare %private function hsg:resolve-include($header as element()?, $name as xs:string) as element()? {
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
 : The full title of the publication a division belongs to, resolved from the
 : volume root document (whose titleStmt is xincluded from the shared
 : *_includes.xml; see hsg:resolve-include). Shared by
 : hsg:collection-trail and hsg:navigation-title, and public for
 : tags.xqm's resource listings (the direct titleStmt lookup #1101 used
 : misses the xincluded titleStmt of the v2 volume roots).
 :)
(:~
 : Whether every breadcrumb trail starts with Home. The one place that
 : decides it (OP#1437): dropping Home site-wide is flipping this.
 :)
declare variable $hsg:BREADCRUMB-HOME := true();

(:~
 : The root crumb of each site section, keyed by its first path step. A
 : section's trail starts with it (hsg:section-trail). Labels without an
 : i18n key render as plain text, as they always have.
 :)
declare variable $hsg:SECTION-CRUMBS := map {
    "about": map { "i18n": "breadcrumb.about", "label": "About Us" },
    "conferences": map { "i18n": "breadcrumb.conferences", "label": "Conferences" },
    "countries": map { "i18n": "breadcrumb.countries", "label": "Countries" },
    "departmenthistory": map { "i18n": "breadcrumb.departmenthistory", "label": "Department History" },
    "developer": map { "i18n": "breadcrumb.developer", "label": "Developer Resources" },
    "education": map { "label": "Education" },
    "historicaldocuments": map { "i18n": "breadcrumb.historicaldocuments", "label": "Historical Documents" },
    "milestones": map { "i18n": "milestones.title", "label": "Milestones" },
    "open": map { "i18n": "breadcrumb.open", "label": "Open Government Initiative" },
    "search": map { "i18n": "search.search", "label": "Search" },
    "tags": map { "i18n": "breadcrumb.tags", "label": "Tags" }
};

(:~
 : One crumb: a label (text or nodes, e.g. a pb-i18n) and an optional href,
 : a path relative to the app root that hsg:breadcrumbs prefixes with the
 : context path. A "class" entry is copied onto the crumb's li.
 :)
declare function hsg:crumb($label as item()*, $href as xs:string?) as map(*) {
    map {
        "label": $label,
        "href": $href
    }
};

(:~
 : The app's English translations, for hsg:crumb-i18n.
 :)
declare variable $hsg:i18n := json-doc($config:app-root || "/resources/i18n/app/en.json");

(:~
 : A crumb whose label is translated from an i18n key, with an English
 : fallback. A key the app translates becomes data-i18n, which pb-page
 : inserts as HTML, so the translation may carry markup (the italic Foreign
 : Relations; pb-i18n renders text only, tei-publisher-components#406).
 : data-i18n has no fallback, it shows a missing key as is, so any other key
 : stays pb-i18n, which shows the English label.
 :)
declare function hsg:crumb-i18n($key as xs:string, $label as xs:string?, $href as xs:string?) as map(*) {
    let $translation := fold-left(tokenize($key, '\.'), $hsg:i18n, function($maybe-translation-map, $next) {
        if (empty($maybe-translation-map)) then () else $maybe-translation-map?($next)
    })
    let $element :=
        if (empty($translation)) then
            <pb-i18n key="{$key}">{$label}</pb-i18n>
        else
            <span data-i18n="{$key}">{$label}</span>
    return
        hsg:crumb($element, $href)
};

(:~
 : The trail of a page inside a site section: the section's root crumb
 : (from $hsg:SECTION-CRUMBS, linking to /$section), then $trail. The
 : section modules build their trails on this instead of each rendering
 : "Home, section, trail" themselves (OP#1437).
 :)
declare function hsg:section-trail($section as xs:string, $trail as map(*)*) as map(*)+ {
    let $root := $hsg:SECTION-CRUMBS($section)
    return (
        if (exists($root?i18n)) then
            hsg:crumb-i18n($root?i18n, $root?label, "/" || $section)
        else
            hsg:crumb($root?label, "/" || $section),
        $trail
    )
};

(:~
 : Render a breadcrumb trail: the one place breadcrumb markup is built
 : (OP#1437). Pages fill the layout's breadcrumb slot with this and only
 : supply their trail (hsg:crumb maps, below Home).
 :
 : - Home first, if $hsg:BREADCRUMB-HOME.
 : - Every crumb links to its href except the last, the current page,
 :   which gets aria-current="page" and no link, href or not.
 : - schema.org RDFa on every trail (OP#1334; reference parity with
 :   hsg-shell): the list is a BreadcrumbList, each crumb a
 :   ListItem/itemListElement, each link a WebPage/item.
 :)
declare function hsg:breadcrumbs($context as map(*), $trail as map(*)*) as element(li)? {
    let $crumbs := (
        if (not($hsg:BREADCRUMB-HOME)) then () else hsg:crumb-i18n("breadcrumb.home", "Home", "/"),
        $trail
    )
    return
        if (empty($trail)) then ()
        else
            <li>
                <nav aria-label="breadcrumb">
                    <ul typeof="BreadcrumbList" vocab="http://schema.org/">
                    {
                        for $crumb at $pos in $crumbs
                        let $current := $pos = count($crumbs)
                        return
                            <li typeof="ListItem" property="itemListElement">
                            {
                                $crumb?class ! attribute class { . },
                                if (not($current)) then () else
                                    attribute aria-current { "page" },
                                if ($current or empty($crumb?href)) then
                                    $crumb?label
                                else
                                    <a href="{$context?context-path}{$crumb?href}" typeof="WebPage" property="item">{$crumb?label}</a>
                            }
                            </li>
                    }
                    </ul>
                </nav>
            </li>
};

(:~
 : The document <title> for a page: "<page> - Office of the Historian", or
 : just the site name when no page title applies (OP#1333; reference parity
 : with hsg-shell, whose every page carried this pattern). Page templates
 : pass their own heading; hsg:frus-page-title derives one for the
 : doc-backed volume pages the layout defaults cover.
 :)
declare function hsg:page-title($page as xs:string?) as xs:string {
    string-join((normalize-space($page)[. ne ''], "Office of the Historian"), " - ")
};

(:~
 : Page-title text for a FRUS volume/division page: the section title
 : "Historical Documents", exactly as the reference system serves for every
 : volume, chapter and document page (verified against the mirror and
 : production). hsg-shell carries an unwired richer design (its
 : pages:generate-title tests expect "<head> - Historical Documents - ...");
 : if that is ever wanted here, this is the function to change. Empty for
 : non-FRUS doc-backed pages (conferences etc.), which declare their own
 : titles.
 :)
declare function hsg:frus-page-title($context as map(*)) as xs:string? {
    if (empty($context?doc) or empty(hsg:volume-title($context?doc?content)[. ne ''])) then ()
    else "Historical Documents"
};

declare function hsg:volume-title($doc as node()?) as xs:string? {
    if (empty($doc)) then ()
    else (
        let $publication := config:get-relpath($doc, $config:data-default) => tokenize("/") => head()
        return hsg:publication-title($publication)
    )
};

(:~
 : The same volume title resolved from the publication id alone, for pages
 : that render without a context document (the pg_* facsimile page, OP#1335,
 : whose only handle on the volume is the id threaded through
 : $context?facsimile).
 :)
declare function hsg:publication-title($publication as xs:string?) as xs:string? {
    if (empty($publication) or $publication = '') then ()
    else
        let $volume := doc($config:data-default || "/" || $publication || "/" || $publication || ".xml")
        let $titleStmt := hsg:resolve-include($volume//tei:teiHeader, 'titleStmt')
        return normalize-space(head($titleStmt/tei:title))
};

(:~
 : The volume-title heading rendered above the content of every interior
 : division page (chapter, document, section). Reference parity with
 : hsg-shell's pages:navigation-title, which puts this h2 on all
 : volume-interior pages.
 :)
declare function hsg:navigation-title($context as map(*)) as element(h2)? {
    let $title := hsg:volume-title($context?doc?content)
    return
        if (empty($title)) then () else
            <h2 class="hsg-navigation-title" id="navigation-title">{$title}</h2>
};

(:~
 : The volume's table of contents, as a USWDS side navigation (#1089).
 :
 : Shape (reference parity): front matter flat, then each compilation as a node
 : with its chapters nested beneath, then the back matter. Documents are never
 : listed. The print table of contents (front/toc.xml) is omitted.
 :
 : Rendered into the layout's `before` block, so it appears on the volume
 : landing and on the comp, chapter and document pages (and, via
 : hsg:facsimile-toc, the pg_* page): one TOC for the whole volume. Keep this
 : the only traversal.
 :)
declare function hsg:volume-toc($context as map(*)) {
    let $doc := $context?doc?content
    let $publication := ($doc//tei:bibl[@type='frus-volume-id'])[1]/string()
    return
    if (empty($doc)) then ()
    else if ($publication != '') then
        hsg:volume-toc-nav(
            $publication,
            ($doc//tei:bibl[@type='frus-division-id'])[1]/string(),
            ($doc//tei:bibl[@type='frus-division-type'])[1] = 'document',
            $context
        )
    else
        (: The volume root carries no typed bibl ids; it is {volume}/{volume}.xml
           in the data collection. Its landing page gets the same TOC, with no
           current entry, unless the volume is unpublished (OP#1337). :)
        let $path := tokenize(config:get-relpath($doc, $config:data-default), '/')
        return
            if (not(count($path) eq 2 and $path[2] eq $path[1] || '.xml' and hsg:volume-published($path[1]))) then ()
            else hsg:volume-toc-nav($path[1], (), false(), $context)
};

(:~
 : The same table of contents on the pg_* facsimile page (#1445), which has no
 : context document, only the publication id in $context?facsimile. No entry
 : is marked current: the reference's TOC never matches a page id either.
 :)
declare function hsg:facsimile-toc($context as map(*)) as element(nav)? {
    let $publication := $context?facsimile?publication
    return
        if (empty($publication)) then () else
            hsg:volume-toc-nav($publication, (), false(), $context)
};

declare %private function hsg:volume-toc-nav(
    $publication as xs:string,
    $current as xs:string?,
    $current-is-document as xs:boolean,
    $context as map(*)
) as element(nav) {
    let $volume := doc($config:data-default || "/" || $publication || "/" || $publication || ".xml")
    let $divisions := hsg:toc-divisions($publication)
    return
        <nav aria-label="Side navigation" class="toc">
            <ul class="usa-sidenav">
                {hsg:toc-entries($volume/tei:TEI, $divisions, $publication, $current, $current-is-document, $context)}
            </ul>
        </nav>
};

(:~
 : Every division of a volume that the table of contents can list, keyed by id.
 :
 : Fetched in one collection scan rather than by resolving each xi:include in
 : turn: a volume has ~16 listable divisions but ~340 documents, and opening
 : every document only to discover it is a document cost ~4.8s per page against
 : ~95ms for this.
 :
 : Documents are excluded because they are never listed, and the print table of
 : contents by its subtype rather than by hardcoding front/toc.xml, so both
 : generalise to other volumes.
 :)
declare %private function hsg:toc-divisions($publication as xs:string) as map(*) {
    map:merge(
        (: Keep only listable divisions: those carrying a frus-division-type that
           is neither 'document' nor 'document-pending'. Excluding only
           'document' let a pending chapter's 71 document-pending includes leak
           into the table of contents as "Document 1..71" child entries. The
           empty-string guard also drops the volume root (and anything else with
           no frus-division-type), which carries no frus-division-id either and
           would give map:entry below an empty key -- exactly what the original
           '!= "document"' comparison excluded implicitly. :)
        for $division in collection($config:data-default || "/" || $publication)/tei:TEI
        let $division-type := normalize-space(head($division/tei:teiHeader//tei:bibl[@type='frus-division-type']))
        where $division-type != ''
            and not(starts-with($division-type, 'document'))
            and normalize-space(head($division//tei:bibl[@type='frus-division-subtype'])) != 'table-of-contents'
        return
            map:entry(head($division//tei:bibl[@type='frus-division-id'])/string(), $division)
    )
};

(:~
 : One level of the table of contents: the divisions a division includes.
 :
 : Walks the parent's xi:include order -- which is where document order comes
 : from -- and looks each @xpointer up in $divisions. Anything absent from the
 : map is a document (or the print TOC) and is skipped without opening it, so a
 : chapter's ~50 document includes cost 50 map lookups and no I/O.
 :
 : Recursion stops for the same reason: a chapter's includes are all documents,
 : so it yields no children. Volumes with several compilations, with none, or
 : with subchapters need no special casing -- though the loaded fixture has
 : exactly one compilation and cannot exercise those variants.
 :)
(:~
 : A division title for display (OP#1085): frus-unbound-alpha splits a
 : chapter/compilation title into a date-range title plus a descriptive
 : subtitle, which read as a run-on when merely concatenated. The reference
 : renders a line break between them (its tei-lb br) everywhere the title
 : appears as a block -- heading, TOCs, document list -- so this returns
 : (title, <br/>, subtitle) for the split case and the plain title otherwise.
 : Breadcrumbs, which cannot break lines, join with a space instead.
 :
 : normalize-space is load-bearing, not noise (PR #47 review): 1431 of the
 : 2714 titleStmt titles in the loaded corpus carry line wraps from TEI
 : source indentation, which would otherwise pass through into the emitted
 : markup and into exact-text assertions as raw newline-plus-indent runs.
 :)
declare %private function hsg:split-title($titles as element(tei:title)*) {
    if (count($titles) gt 1) then (
        head($titles) => normalize-space(),
        <br/>,
        tail($titles) => string-join(' ') => normalize-space()
    ) else (
        $titles => normalize-space()
    )
};

declare %private function hsg:toc-entries($division as element(tei:TEI)?, $divisions as map(*),
        $publication as xs:string, $current as xs:string?, $current-is-document as xs:boolean,
        $context as map(*)) {
    for $include in $division//tei:text//xi:include
    let $id := $include/@xpointer/string()
    where map:contains($divisions, $id)
    let $included := $divisions($id)
    (: A chapter/compilation title may be split across two title elements (a
       date range plus a descriptive subtitle, frus-unbound-alpha); show both
       with the reference's line break between them (OP#1085). :)
    let $title := hsg:split-title($included//tei:fileDesc//tei:titleStmt/tei:title)
    (: current when it is the page being viewed, or -- on a document page, where
       the document itself is not listed -- when it is the division including it :)
    let $is-current :=
        $id = $current or
        ($current-is-document and exists($included//tei:text//xi:include[@xpointer = $current]))
    (: An unpublished division ('chapter-pending', 'section-pending', ...) is
       listed but marked li.pending, exactly as the reference site lists a
       partially-published volume's pending chapters (OP#1337 review;
       frus1977-80v27 on the mirror). Fully anticipated volumes never get
       this far: their landing suppresses the TOC wholesale and their
       interior pages 404 on the volume-level gate in hsg-api.xql. :)
    let $is-pending := ends-with(normalize-space(head($included//tei:bibl[@type='frus-division-type'])), '-pending')
    (: Document range "(Documents N-M)" inside the entry's link, after its
       title, as hsg-shell's sidebar shows it, for divisions that contain
       documents. :)
    let $range-label := hsg:document-range-label(hsg:document-range($included))
    let $children := hsg:toc-entries($included, $divisions, $publication, $current, $current-is-document, $context)
    return
        <li>
        {
            attribute class {
                (
                    "usa-sidenav__item",
                    if (not($is-pending)) then () else 'pending'
                )
                => string-join(" ")
            },
            element a {
                attribute href {
                    $context?context-path || "/historicaldocuments/" || $publication || "/" || $id
                },
                if (not($is-current)) then () else (
                    attribute class {"usa-current"},
                    attribute aria-current {"page"}
                ),
                $title,
                if (empty($range-label)) then () else (
                    <span class="toc-range">{$range-label}</span>
                )
            }
        }
        {
            if (empty($children)) then () else
                <ul class="usa-sidenav__sublist">{$children}</ul>
        }
        </li>
};

(:~
 : List every volume in the Historical Documents section as linked list items.
 :
 : Scaffolding for the section landing (#1084): barebones navigation, nothing
 : more. There is one volume today.
 :
 : A volume is a child collection of the data root holding a TEI file named
 : after it (frus1981-88v05/frus1981-88v05.xml) -- the same shape
 : hsg:collection-trail() relies on -- so this discovers volumes rather
 : than listing them anywhere.
 :)
declare function hsg:volume-list($context as map(*)) {
    for $volume in xmldb:get-child-collections($config:data-default)
    let $path := $config:data-default || "/" || $volume || "/" || $volume || ".xml"
    where doc-available($path)
    (: titleStmt lives in a shared *_includes.xml, xincluded rather than
       duplicated inline (frus-unbound-alpha) -- see hsg:resolve-include. :)
    let $titleStmt := hsg:resolve-include(doc($path)//tei:teiHeader, 'titleStmt')
    let $title := normalize-space(head($titleStmt/tei:title))
    order by $title
    return
        <li>
            <a href="{$context?context-path}/historicaldocuments/{$volume}">{$title}</a>
        </li>
};

(:~
 : The administrations taxonomy (frus-data-jinks, OP#1214): one category per
 : administration slug, one catDesc per presidency. Its xml:id is the target
 : the volume headers' keywords scheme "#frus-administration-coverage" point
 : at, so the slugs here and the terms in the volumes are one vocabulary.
 :)
declare %private function hsg:administrations() as element(tei:taxonomy)? {
    doc($config:data-root || "/administrations/administrations.xml")
        //tei:taxonomy[@xml:id = 'frus-administration-coverage']
};

declare function hsg:administration($admin-id as xs:string) as element(tei:category)? {
    hsg:administrations()/tei:category[@xml:id = $admin-id]
};

(:~
 : The recent administrations of the Administrations panel, with the panel's
 : short labels, newest last. Kept here because the taxonomy has neither the
 : short labels nor a notion of "recent" (OP#1475).
 :)
declare variable $hsg:recent-administrations := (
    ["kennedy", "Kennedy Administration"],
    ["johnson", "Johnson Administration"],
    ["nixon-ford", "Nixon-Ford Administrations"],
    ["carter", "Carter Administration"],
    ["reagan", "Reagan Administration"],
    ["bush-ghw", "G.H.W. Bush Administration"],
    ["clinton", "Clinton Administration"],
    ["bush-gw", "G.W. Bush Administration"]
);

(:~
 : The Administrations panel of the Historical Documents sidebar (OP#1467),
 : as on the reference: an intro, the recent administrations, a link to all
 : of them. An administration missing from the taxonomy has no page and is
 : left out (G.W. Bush, for now).
 :)
declare function hsg:administrations-panel($context as map(*)) as element()+ {
    <h2 class="usa-in-page-nav__heading">Administrations</h2>,
    <p>Browse official documents from the <em>Foreign Relations of the United States</em> series.</p>,
    <h3 class="usa-in-page-nav__heading">Recent Administrations</h3>,
    <ul class="usa-in-page-nav__list">
    {
        for $admin in $hsg:recent-administrations
        where exists(hsg:administration($admin?1))
        return
            <li class="usa-in-page-nav__item usa-in-page-nav__item--primary">
                <a href="{$context?context-path}/historicaldocuments/{$admin?1}">{$admin?2}</a>
            </li>
    }
        <li class="usa-in-page-nav__item usa-in-page-nav__item--primary">
            <a href="{$context?context-path}/historicaldocuments">All Administrations</a>
        </li>
    </ul>
};

(:~
 : Every volume root TEI classified under the given administration.
 :
 : Membership lives in each volume's own header (keywords scheme
 : "#frus-administration-coverage"), so this walks the volume collections the
 : same way hsg:volume-list does rather than querying a registry; there is no
 : bibliography collection in the v2 data.
 :)
declare %private function hsg:volumes-in-administration($admin-id as xs:string) as element(tei:TEI)* {
    for $volume in xmldb:get-child-collections($config:data-default)
    let $path := $config:data-default || "/" || $volume || "/" || $volume || ".xml"
    where doc-available($path)
    let $root := doc($path)/tei:TEI
    where $root/tei:teiHeader//tei:keywords[@scheme = '#frus-administration-coverage']/tei:term = $admin-id
    return $root
};

(:~
 : The section landing's administration grid: one card per presidency, in the
 : taxonomy's chronological order, reference parity with hsg-shell's
 : pages/historicaldocuments/index.xml thumbnails. A catDesc without a
 : portrait ptr (pre-truman, the nixon-ford combined heading entry) is not a
 : card. Both Nixon and Ford link to the shared nixon-ford page, and the two
 : Cleveland terms stay separate, matching the slugs the volume headers use.
 :)
declare function hsg:administration-cards($context as map(*)) {
    for $category in hsg:administrations()/tei:category
    for $presidency in $category/tei:catDesc[tei:ptr[@type = 'portrait']]
    let $name := normalize-space($presidency/tei:term)
    let $short-name := replace($name, ' Administration$', '')
    let $dates := normalize-space($presidency/tei:date[@type = 'coverage'])
    return
        <li class="usa-card hsg-admin-card">
            <div class="usa-card__container">
                <div class="usa-card__media">
                    <div class="usa-card__img">
                        <img src="{$presidency/tei:ptr[@type = 'portrait']/@target}"
                            alt="{$short-name}" loading="lazy"/>
                    </div>
                </div>
                <div class="usa-card__header">
                    <h2 class="usa-card__heading">
                        <a href="{$context?context-path}/historicaldocuments/{$category/@xml:id}">{$short-name}</a>
                    </h2>
                    <p class="hsg-admin-card__type">Administration</p>
                </div>
                <div class="usa-card__body">
                    <span class="usa-tag usa-tag--big">{$dates}</span>
                </div>
            </div>
        </li>
};

(:~
 : Cards for the "Historical documents" nav band mounted by
 : templates/layouts/historicaldocuments-content.html (OP#1400). Same 8
 : destinations as templates/pages/historicaldocuments/sidebar.html's
 : usa-sidenav list -- kept as a second hardcoded copy here because sidebar.html
 : itself is plain hardcoded markup with no shared data source; if either
 : list changes, check the other. Order matches the Figma design, which
 : differs slightly from sidebar.html's order. The last card links back to
 : the section root (sidebar.html's "Foreign Relations of the United
 : States" target) under the new design's "All Historical Documents" label
 : and gets a highlight modifier class for its CTA treatment.
 :)
declare function hsg:historicaldocuments-nav-cards($context as map(*)) {
    let $root := $context?context-path || "/historicaldocuments"
    for $item in (
        map { "label": "About the Foreign Relations Series", "href": $root || "/about-frus" },
        map { "label": "Status of the Foreign Relations Series", "href": $root || "/status-of-the-series" },
        map { "label": "History of the Foreign Relations Series", "href": $root || "/frus-history" },
        map { "label": "Other Electronic Resources", "href": $root || "/other-electronic-resources" },
        map { "label": "Guide to Sources on Vietnam, 1969-1975", "href": $root || "/guide-to-sources-on-vietnam-1969-1975" },
        map { "label": "Citing the Foreign Relations series", "href": $root || "/citing-frus" },
        map { "label": "Foreign Relations Ebooks", "href": $root || "/ebooks" },
        map { "label": "All Historical Documents", "href": $root, "highlight": true() }
    )
    return
        <li class="usa-card hsg-historicaldocuments-nav-card{if ($item?highlight) then ' hsg-historicaldocuments-nav-card--highlight' else ''}">
            <div class="usa-card__container">
                <div class="usa-card__header">
                    <h3 class="usa-card__heading">
                        <a href="{$item?href}">{$item?label}</a>
                    </h3>
                </div>
                <div class="usa-card__body">
                    <span class="hsg-historicaldocuments-nav-card__arrow" aria-hidden="true"></span>
                </div>
            </div>
        </li>
};

(:~
 : Administration page heading, reference parity with hsg-shell's
 : frus:administration-name: "Ronald Reagan Administration (1981-1989)" with
 : the term-of-office dates, not the coverage dates the landing cards show.
 : nixon-ford uses its combined catDesc; a category without a term date
 : (pre-truman) falls back to its coverage date.
 :)
declare function hsg:administration-heading($context as map(*)) as xs:string {
    let $category := hsg:administration($context?administration-id)
    let $head := ($category/tei:catDesc[@n = 'combined'], $category/tei:catDesc)[1]
    let $date := ($head/tei:date[@type = 'term'], $head/tei:date[@type = 'coverage'])[1]
    return normalize-space($head/tei:term) || " (" || normalize-space($date) || ")"
};

(:~
 : The administrations whose volumes predate administration-organized
 : sub-series (the series was organized by year for 1861-1951 and
 : triennially for 1952-1963), reference parity with the closed list in
 : hsg-shell's fh:administration-listing-note. Their pages carry an
 : explanatory note; administration-organized pages carry none (hsg-shell
 : has that branch commented out, and the reference site renders nothing).
 :)
declare %private variable $hsg:pre-administration-subseries-admins := (
    "lincoln", "johnson-a", "grant", "hayes", "garfield", "arthur",
    "cleveland-22", "harrison", "cleveland-24", "mckinley", "roosevelt-t",
    "taft", "wilson", "harding", "coolidge", "hoover", "roosevelt-fd",
    "truman", "kennedy"
);

(:~
 : The FRUS production tracks, reference parity with the
 : frus-production-tracks taxonomy in hsg-shell's code table
 : (frus repo, shared/frus-production.xml). frus-data-jinks carries no code
 : table, and the vocabulary is closed and stable (three fixed categories),
 : so the ids and display labels live here. Order is the taxonomy's, which
 : fixes the order of the per-track headings on administration pages.
 :)
declare %private variable $hsg:production-tracks := (
    map { "id": "regular", "label": "Regular" },
    map { "id": "accelerated", "label": "Accelerated" },
    map { "id": "retrospective", "label": "Retrospective" }
);

(:~
 : The production track under which a volume covers the given
 : administration. The volume's #frus-administration-coverage terms carry
 : xml:ids, and its #frus-production-priority terms point back at them, so a
 : retrospective volume spanning several administrations can be Regular for
 : one and Retrospective for another. Most volumes point via @corresp; a few
 : v2 headers use @ana for the same relation (e.g. frus1977-80v27), so both
 : are accepted.
 :)
declare %private function hsg:production-track($root as element(tei:TEI), $admin-id as xs:string) as xs:string? {
    let $admin-terms := $root/tei:teiHeader//tei:keywords[@scheme = '#frus-administration-coverage']
        /tei:term[. = $admin-id]
    let $refs := $admin-terms/@xml:id ! ("#" || .)
    let $tracks := $root/tei:teiHeader//tei:keywords[@scheme = '#frus-production-priority']
        /tei:term[(@corresp, @ana) = $refs]
    return ($tracks ! string(.))[1]
};

(:~
 : The production tracks in use among an administration's volumes, in order
 : of first appearance with the volumes sorted by id. That matches what the
 : reference site's group-info sentence shows (hsg-shell's order-by there
 : compares against an attribute that does not exist on categories, so its
 : groups keep first-appearance order), while the per-track headings below
 : use the taxonomy order instead, same as the reference.
 :)
declare %private function hsg:tracks-in-use($roots as element(tei:TEI)*, $admin-id as xs:string) as xs:string* {
    let $per-volume :=
        for $root in $roots
        order by $root/@xml:id
        return hsg:production-track($root, $admin-id)
    return distinct-values($per-volume)
};

(:~
 : The explanatory note on pages of administrations that predate
 : administration-organized sub-series, reference parity with hsg-shell's
 : fh:administration-listing-note and the pre-administration-based-subseries
 : paragraph in its administrations.xml.
 :)
declare function hsg:administration-listing-note($context as map(*)) as element(p)? {
    if (not($context?administration-id = $hsg:pre-administration-subseries-admins)) then ()
    else
        <p id="pre-administration-based-subseries-note">
            <strong>Note:</strong> The volumes listed
            below contain at least one document from the period of this presidential
            administration; {hsg:administration-search-link($context)}. The <em>Foreign
            Relations</em> series was organized by year for the volumes covering
            1861–1951, triennially for 1952–1963, and by presidential administration
            for 1964 onward—with some exceptions.</p>
};

(:~
 : "view and search within the available documents", a search scoped to the
 : president's term of office, reference parity with hsg-shell's
 : fh:admin-search-href. Term dates come from the travels data package's
 : presidents register; the taxonomy position + 14 maps an administration to
 : its president's ordinal, which is sound for every administration that
 : gets the note (one category per president up to kennedy; the combined
 : nixon-ford category sits after them and never renders it).
 :)
declare %private function hsg:administration-search-link($context as map(*)) as element(a) {
    let $ordinal := index-of(
            hsg:administrations()/tei:category/@xml:id/string(),
            $context?administration-id
        ) + 14
    let $president := doc("/db/apps/travels/presidents/presidents.xml")//president[@n = $ordinal]
    return
        <a href="{$context?context-path}/search?within=documents&amp;start-date={$president/took-office-date}&amp;end-date={$president/left-office-date}&amp;sort=date-asc"
            >view and search within the available documents</a>
};

(:~
 : "Volumes are grouped into X and Y categories." with in-page links, shown
 : only when more than one production track is in use, reference parity with
 : hsg-shell's fh:group-info including its list punctuation (Oxford comma
 : from three items up).
 :)
declare function hsg:administration-group-info($context as map(*)) as element(p)? {
    let $admin-id := $context?administration-id
    let $tracks := hsg:tracks-in-use(hsg:volumes-in-administration($admin-id), $admin-id)
    return
        if ($admin-id eq 'pre-truman' or count($tracks) le 1) then ()
        else
            <p>Volumes are grouped into {
                for $track at $n in $tracks
                return (
                    <a href="#{$track}-volumes">{
                        $hsg:production-tracks[?id = $track]?label
                    }</a>,
                    if ($n eq count($tracks)) then ()
                    else
                        concat(
                            if (count($tracks) le 2) then () else ', ',
                            if ($n ne count($tracks) - 1) then () else ' and '
                        )
                )
            } categories.</p>
};

(:~
 : The volumes of one administration, reference parity with hsg-shell's
 : administrations.xml rendering chain: when several production tracks are
 : in use (nixon-ford, kennedy, ...), an h2 per track ("Regular volumes",
 : anchor {track}-volumes) in taxonomy order, each holding the track's
 : volumes grouped by sub-series; otherwise the sub-series groups alone. A
 : sub-series group is an h3 ("Foreign Relations of the United States,
 : 1981-1988") over a list of volumes with availability notices, ordered by
 : the sub-series' @n. pre-truman instead gets the reference's flat
 : chronological list of complete titles (frus:volumes-pre-truman); its
 : volumes predate administration-based sub-series, so sub-series grouping
 : would just repeat each title.
 :)
declare function hsg:administration-volumes($context as map(*)) {
    let $admin-id := $context?administration-id
    let $roots := hsg:volumes-in-administration($admin-id)
    return
        if (empty($roots)) then
            <p class="hsg-admin__empty">No volumes for this administration are available in this
                instance's data set.</p>
        else if ($admin-id = 'pre-truman') then
            <ol class="hsg-admin__volumes">
                {
                    for $root in $roots
                    let $title := normalize-space((hsg:resolve-include($root/tei:teiHeader, 'titleStmt')/tei:title)[1])
                    order by $root/@xml:id
                    return hsg:admin-volume-item($context, $root, $title)
                }
            </ol>
        else if (count(hsg:tracks-in-use($roots, $admin-id)) gt 1) then
            for $track in $hsg:production-tracks
            let $track-roots := $roots[hsg:production-track(., $admin-id) = $track?id]
            where exists($track-roots)
            return (
                <h2 id="{$track?id}-volumes" class="hsg-admin__track">{$track?label} volumes</h2>,
                hsg:sub-series-groups($context, $track-roots)
            )
        else
            hsg:sub-series-groups($context, $roots)
};

(:~
 : Sub-series groups over a set of volume roots: an h3 per sub-series in
 : sub-series order (@n), each over its volumes ordered by id, reference
 : parity with hsg-shell's fh:volumes-by-group / fh:volumes-by-administration
 : (including the "Other" fallback label for a volume without series titles).
 :)
declare %private function hsg:sub-series-groups($context as map(*), $roots as element(tei:TEI)*) {
    for $root in $roots
    let $seriesStmt := hsg:resolve-include($root/tei:teiHeader, 'seriesStmt')
    let $group := normalize-space(string-join((
            $seriesStmt/tei:title[@type = 'series'],
            $seriesStmt/tei:title[@type = 'sub-series']
        )[. != ''], ", "))
    group by $group
    order by ($seriesStmt/tei:title[@type = 'sub-series']/@n/string())[1]
    return (
        <h3 class="hsg-admin__sub-series">{($group[. != ''], 'Other')[1]}</h3>,
        <ul class="hsg-admin__volumes">
            {
                for $vol-root in $root
                let $volStmt := hsg:resolve-include($vol-root/tei:teiHeader, 'seriesStmt')
                let $label := normalize-space(string-join((
                        $volStmt/tei:title[@type = 'volume-number'],
                        $volStmt/tei:title[@type = 'volume']
                    )[. != ''], ", "))
                let $label := if ($label != '') then
                        $label
                    else
                        normalize-space(($volStmt/tei:title[@type = 'sub-series'])[1])
                order by $vol-root/@xml:id
                return hsg:admin-volume-item($context, $vol-root, $label)
            }
        </ul>
    )
};

declare %private function hsg:admin-volume-item($context as map(*), $root as element(tei:TEI), $label as xs:string) {
    <li>
        <a href="{$context?context-path}/historicaldocuments/{$root/@xml:id}">{$label}</a>
        {" "}
        <span class="hsg-status-notice">{hsg:volume-availability($root)}</span>
    </li>
};

(:~
 : Availability notice per volume, reference parity with hsg-shell's
 : fh:volume-availability-summary: published volumes list their formats, any
 : other revisionDesc status is shown humanized ("(Being Cleared)"). Full
 : text means the volume has a body collection; the v2 corpus also carries
 : root-only volumes without one.
 :)
declare %private function hsg:volume-availability($root as element(tei:TEI)) as xs:string {
    let $status := $root/tei:teiHeader//tei:revisionDesc/@status/string()
    return
        if ($status = 'published') then
            let $formats := (
                "Full Text"[xmldb:collection-available(util:collection-name($root) || "/body")],
                "Ebook"[$root/tei:teiHeader//tei:relatedItem[@type = 'epub']],
                "PDF"[$root/tei:teiHeader//tei:relatedItem[@type = 'pdf']]
            )
            return
                if (exists($formats)) then
                    "(Published and available in " || string-join($formats, ", ") || ")"
                else
                    "(Published)"
        else
            "(" ||
            string-join(
                for $word in tokenize(translate($status, '-', ' '), '\s+')
                return upper-case(substring($word, 1, 1)) || substring($word, 2),
                " ")
            || ")"
};

(:~
 : Trail of a FRUS volume page: Historical Documents > volume title. The
 : volume title is the current crumb only on the volume landing page; on
 : any interior page it links back there and the division itself is the
 : current crumb, on a line of its own (.breadcrumb-current, #1082):
 : "Document <n>" for a document, otherwise the division's own title (the
 : reference site labels every interior page this way). Empty without a
 : context document, so the layout default renders no breadcrumb then.
 :)
declare function hsg:collection-trail($context as map(*)) as map(*)* {
    if (empty($context?doc)) then ()
    else
        let $content := $context?doc?content
        let $components := config:get-relpath($content, $config:data-default) => tokenize("/")
        let $publication := $components[1]
        let $is-landing := count($components) = 2
        let $volume-title := hsg:volume-title($content)
        return hsg:section-trail("historicaldocuments", (
            hsg:crumb($volume-title, if ($is-landing) then () else "/historicaldocuments/" || $publication),
            if ($is-landing) then ()
            else map:merge((hsg:crumb(hsg:division-crumb-label($content), ()), map { "class": "breadcrumb-current" }))
        ))
};

(:~
 : Label of a FRUS division's own crumb: "Document <n>" for a numbered
 : document (see hsg:document-number), otherwise the division's title
 : (chapters, compilations, front and back matter, unnumbered documents).
 : See hsg:split-title: the title may be split into a date range and a
 : subtitle; a breadcrumb cannot break lines, so join with a space, as the
 : reference breadcrumb does.
 :)
declare %private function hsg:division-crumb-label($content as node()) as xs:string {
    let $number := hsg:document-number($content)
    return
        if (($content//tei:bibl[@type = 'frus-division-type'])[1] = 'document' and exists($number)) then
            "Document " || $number
        else
            $content//tei:titleStmt/tei:title => string-join(' ') => normalize-space()
};

(:~
 : The data the volume landing page's markup (templates/pages/volume/
 : landing.html) is built from: the volume root, its id and title, and its
 : titleStmt and publicationStmt, resolved once. None without a volume.
 :)
declare function hsg:volume-landing($context as map(*)) as map(*)? {
    let $doc := $context?doc?content
    return
    if (not(exists($doc))) then ()
    else
        (: titleStmt/publicationStmt are xincluded from the volume's shared
           *_includes.xml; see hsg:resolve-include. :)
        let $header := $doc//tei:teiHeader
        let $titleStmt := hsg:resolve-include($header, 'titleStmt')
        return map {
            "doc": $doc,
            "id": config:get-relpath($doc, $config:data-default) => tokenize("/") => head(),
            "title": normalize-space(($titleStmt/tei:title)[1]),
            "titleStmt": $titleStmt,
            "publicationStmt": hsg:resolve-include($header, 'publicationStmt')
        }
};

(:~
 : The tags above a volume's title: the administrations it covers, as USWDS
 : tags each linking to its administration page. Labels come from the
 : administrations taxonomy: the combined entry where there is one ("Richard
 : M. Nixon and Gerald R. Ford Administrations"), else the single presidency's.
 :)
declare function hsg:volume-card-tags($doc as node(), $context as map(*)) as element(ul)? {
    let $admin-terms := $doc//tei:keywords[@scheme = '#frus-administration-coverage']/tei:term
    let $tags :=
        for $term in $admin-terms
        let $admin := hsg:administration(string($term))
        let $id := $admin/@xml:id
        let $relevantCatDesc := head((
            $admin/tei:catDesc[@n = 'combined'],
            $admin/tei:catDesc
        ))
        return
            <li><a class="usa-tag" href="{$context?context-path}/historicaldocuments/{$id}">{
                string($relevantCatDesc/tei:term)
            }</a></li>

    return
        if (empty($tags)) then ()
        else <ul class="hsg-frus__tags">{$tags}</ul>
};

(:~
 : The volume's cover image in its square frame, if it has one. Reference
 : parity with hsg-shell (fh:cover-uri): the URL is built from the volume id
 : rather than read from notesStmt's own @target -- matches the data in
 : practice, and is what the reference site does. Gated on the *volume-scoped* jpg relatedItem's
 : existence (@corresp = "#" || the volume id, as fh:exists-cover-image
 : does; see hsg:volume-ways-to-explore on why the bare @type is not
 : enough), not the constructed URL's reachability, so a volume with no
 : cover renders no <img>, same as hsg-shell.
 :)
declare function hsg:volume-cover($doc as node(), $volume-id as xs:string, $title as xs:string) as element(div)? {
    if (empty($doc//tei:notesStmt/tei:relatedItem[@type = 'jpg'][@corresp = '#' || $volume-id])) then (
        (: No cover image available :)
    ) else (
        <div class="hsg-frus__cover-frame">
            <img class="hsg-frus__cover"
                src="https://static.history.state.gov/frus/{$volume-id}/covers/{$volume-id}.jpg"
                alt="Book Cover of {$title}"/>
        </div>
    )
};

(:~
 : Editor / General Editor rows of the metadata list. Reference parity with
 : hsg-shell: titleStmt/editor[@role='primary'] labeled "Editor:"
 : ("Editors:" if more than one), editor[@role='general'] labeled "General
 : Editor:", one dd per name. Takes the titleStmt hsg:volume-landing
 : resolved.
 :)
declare function hsg:volume-editors($titleStmt as element(tei:titleStmt)?) {
    let $primary := $titleStmt/tei:editor[@role = 'primary']
    let $general := $titleStmt/tei:editor[@role = 'general']
    return (
        if (empty($primary)) then () else (
            <dt>{if (count($primary) gt 1) then 'Editors:' else 'Editor:'}</dt>,
            hsg:render-volume-editor($primary)
        ),
        if (empty($general)) then () else (
            <dt>General Editor:</dt>,
            hsg:render-volume-editor($general)
        )
    )
};

declare %private function hsg:render-volume-editor($editors as element(tei:editor)*) as element(dd)* {
    $editors ! <dd>{string(.)}</dd>
};

(:~
 : Publisher (with its place) and publication year rows of the metadata
 : list. Reference parity with hsg-shell: publicationStmt/publisher,
 : /pubPlace, /date[@type='publication-date'] -- not the content-date range,
 : which hsg-shell doesn't show here either.
 :)
declare function hsg:volume-published-info($publicationStmt as element(tei:publicationStmt)?) {
    let $publisher := normalize-space($publicationStmt/tei:publisher)
    let $place := normalize-space($publicationStmt/tei:pubPlace)
    let $year := normalize-space($publicationStmt/tei:date[@type = 'publication-date'])
    return (
        if ($publisher eq '' and $place eq '') then () else (
            <dt>Publisher:</dt>,
            <dd class="hsg-frus__publisher">{
                string-join(($publisher, $place)[. ne ''], ', ')
            }</dd>
        ),
        if ($year eq '') then () else (
            <dt>Publication year:</dt>,
            <dd class="hsg-frus__pubdate">{$year}</dd>
        )
    )
};

(:~
 : The "Open" call to action: the volume's first published division in its
 : body (the first chapter or compilation), falling back to the first one
 : anywhere for a volume without a body division. None for a volume with no
 : published content, which also has no table of contents.
 :)
declare function hsg:volume-open-link($context as map(*)) as element(a)? {
    let $doc := $context?doc?content
    let $publication := config:get-relpath($doc, $config:data-default) => tokenize("/") => head()
    let $divisions := hsg:toc-divisions($publication)
    let $text := $doc/tei:TEI/tei:text
    let $openable := ($text/tei:body//xi:include, $text//xi:include)
        [map:contains($divisions, string(@xpointer))]
        [not(ends-with(normalize-space(($divisions(string(@xpointer))//tei:bibl[@type = 'frus-division-type'])[1]), '-pending'))]
    let $target := head($openable)/@xpointer/string()
    return
        if (empty($target) or not(hsg:volume-published($publication))) then ()
        else
            <a class="usa-button hsg-frus__open" href="{$context?context-path}/historicaldocuments/{$publication}/{$target}">Open</a>
};

declare %private function hsg:volume-published($publication as xs:string) as xs:boolean {
    doc($config:data-default || "/" || $publication || "/" || $publication || ".xml")
        //tei:revisionDesc/@status = ("published", "partially-published")
};

(:~
 : A document division's printed number, or the empty sequence: its
 : frus-division-n (hsg-jinks-data), else frus-document-number. Chapters carry
 : a frus-division-n too, so callers check the division type first.
 :)
declare function hsg:document-number($division as node()?) as xs:string? {
    let $bibls := $division//tei:bibl[@type = ('frus-division-n', 'frus-document-number')]
    let $numbers := $bibls ! normalize-space(.)
    return head($numbers[. ne ''])
};

(:~
 : The first and last document numbers under a division's own xi:include
 : tree, for a TOC entry's "(Documents N-M)" suffix. Reference parity with
 : hsg-shell, which read this off a @n attribute the unbound data model
 : doesn't have -- hsg:document-number is the equivalent here.
 :
 : Opens only the first and last leaf document at each level, not every one
 : -- the same performance discipline as hsg:toc-divisions.
 :)
declare %private function hsg:document-range($division as element(tei:TEI)?) as xs:string* {
    let $includes := $division//tei:text//xi:include
    return
        if (empty($includes)) then ()
        else (
            hsg:leading-document-number($includes[1], true()),
            hsg:leading-document-number($includes[last()], false())
        )
};

declare %private function hsg:leading-document-number($include as element(xi:include), $want-first as xs:boolean) as xs:string? {
    let $root := root(id($include/@xpointer, doc(util:collection-name($include) || '/' || $include/@href)))
    let $type := ($root//tei:bibl[@type = 'frus-division-type'])[1]/string()
    return
        (: Documents, published ('document') or not ('document-pending'). An
           unpublished document carries no document number, so fall back to
           the number encoded in its division id ("d148" -> "148"). This is what
           lets a pending chapter (France) still show "(Documents 148-214)",
           reference parity with hsg-shell. :)
        if (starts-with($type, 'document')) then
            let $num := hsg:document-number($root)
            return
                if (exists($num)) then $num
                else tokenize(replace(normalize-space(($root//tei:bibl[@type = 'frus-division-id'])[1]), '^d', ''), '-')[1]
        else
            let $inner := $root//tei:text//xi:include
            return
                if (empty($inner)) then ()
                else if ($want-first) then hsg:leading-document-number($inner[1], true())
                else hsg:leading-document-number($inner[last()], false())
};

declare %private function hsg:document-range-label($range as xs:string*) as xs:string? {
    hsg:document-range-text($range) ! (' (' || . || ')')
};

declare %private function hsg:document-range-text($range as xs:string*) as xs:string? {
    if (count($range) != 2 or $range[1] = '' or $range[2] = '') then ()
    else if ($range[1] = $range[2]) then 'Document ' || $range[1]
    else 'Documents ' || $range[1] || '–' || $range[2]
};

(:~
 : The volume landing page's "Ways to Explore" sidebar panel, rendered into
 : the layout's `after` (right-hand) block by templates/pages/volume/
 : landing.html: search within the volume and ebook downloads as outline
 : buttons (Figma node 4298-66234, OP#1478). The search lands on the
 : documents results filtered to this volume.
 :
 : Each ebook link is independently gated on its own relatedItem's
 : existence (fh:exists-epub/-mobi/-pdf in hsg-shell), so a volume missing
 : one format just omits that link rather than erroring.
 :)
declare function hsg:volume-ways-to-explore($context as map(*)) {
    let $doc := $context?doc?content
    return
    if (not(exists($doc))) then ()
    else
        let $volume-id := config:get-relpath($doc, $config:data-default) => tokenize("/") => head()
        (: Volume-scoped items only. A volume's notesStmt also carries a
           relatedItem per *associated file* -- frus1958-60v05mSupp, a
           microfiche supplement, has 562 type="pdf" entries, one per
           document -- and those are told apart from the volume's own
           download solely by @corresp pointing at the volume id. Reference
           parity with hsg-shell's fh:exists-pdf / fh:exists-epub / etc.,
           which all gate on @corresp eq "#" || $vol-id for this reason.
           Without the gate the ebook links below select all 562 and die
           with a cardinality error. :)
        let $related := $doc//tei:notesStmt/tei:relatedItem[@corresp = '#' || $volume-id]
        let $downloads := (
            hsg:ebook-link($related, 'epub', 'EPUB'),
            hsg:ebook-link($related, 'mobi', 'Mobi'),
            hsg:ebook-link($related, 'pdf', 'PDF')
        )
        return
            <div class="hsg-frus__ways-to-explore">
                <h2 class="hsg-frus__sidebar-title">
                    <pb-i18n key="historicaldocuments.waysToExplore">Ways to Explore</pb-i18n>
                </h2>
                <div class="hsg-frus__explore-item">
                    <label class="hsg-frus__label" for="frus-search-q">
                        <pb-i18n key="historicaldocuments.searchInsideVolume">Search inside this volume</pb-i18n>
                    </label>
                    <form action="{$context?context-path}/search" method="GET" class="usa-search usa-search--small" role="search">
                        <input id="frus-search-q" class="usa-input" name="q" type="search"/>
                        <button class="usa-button" type="submit">
                            <img src="{$context?context-path}/resources/images/usa-icons-bg/search--white.svg" class="usa-search__submit-icon" alt="Search"/>
                        </button>
                        <input name="within" type="hidden" value="documents"/>
                        <input name="volume-id" type="hidden" value="{$volume-id}"/>
                    </form>
                </div>
                {
                    if (empty($downloads)) then ()
                    else
                        <div class="hsg-frus__explore-item">
                            <h3 class="hsg-frus__label" id="frus-downloads">
                                <pb-i18n key="historicaldocuments.downloadHeading">Download</pb-i18n>
                            </h3>
                            <ul class="hsg-frus__downloads" aria-labelledby="frus-downloads">{$downloads}</ul>
                        </div>
                }
            </div>
};

declare %private function hsg:ebook-link($related as element()*, $type as xs:string, $label as xs:string) as element(li)? {
    (: [1]: callers pass the volume-scoped relatedItems, so one per type is
       expected; take the first regardless rather than let stray duplicate
       encoding turn a download link into a 500. :)
    let $item := ($related[@type = $type])[1]
    return
    if (not(exists($item))) then ()
    else
        let $href := ($item//tei:ref/@target/string())[1]
        let $bytes := ($item//tei:measure/@quantity)[1] ! xs:integer(.)
        let $size := hsg:bytes-to-readable($bytes)
        return
            <li>
                <a class="usa-button usa-button--outline hsg-frus__download" href="{$href}" title="{$label} ({$size})">
                    <span class="hsg-frus__download-icon" aria-hidden="true"></span>
                    <span class="hsg-frus__download-label">{$label}</span>
                    <span class="usa-sr-only"> ({$size})</span>
                </a>
            </li>
};

(:~
 : Format a byte count the way hsg-shell's app:bytes-to-readable does:
 : over 1,000,000 bytes as N.NNmb, over 1,000 as Nkb. Used for the ebook
 : download sizes in the "Ways to Explore" panel.
 :)
declare %private function hsg:bytes-to-readable($bytes as xs:integer?) as xs:string {
    if (empty($bytes)) then 'unknown'
    else if ($bytes gt 1000000) then (round($bytes div 10000) div 100) || 'mb'
    else if ($bytes gt 1000) then round($bytes div 1000) || 'kb'
    else $bytes || ' bytes'
};

(:~
 : Right-hand sidebar of interior division pages: the Persons and
 : Abbreviations &amp; Terms the division references, as one USWDS in-page
 : navigation ("On this page"). Each register is a list of its own, led by a
 : primary item linking to the register page.
 :
 : The markup is what the USWDS script generates, written out server-side
 : and without the parts that tie it to the script: no "usa-in-page-nav"
 : root (the script would append a list built from the page's headings) and
 : no link class (the script cancels clicks on those links and scrolls to
 : their fragment instead). The component styles still apply.
 :
 : Reference parity with hsg-shell's fh:facets/fh:view-persons/fh:view-gloss,
 : with one structural difference: shell resolved #p_X / #t_X ids with id()
 : inside the same monolithic volume document, while frus-v2-data keeps the
 : registers in separate front-matter files (front/persons.xml,
 : front/terms.xml) where the entries are marked persName/term
 : @sameAs="#p_X" rather than @xml:id -- so the lookup is a cross-file
 : @sameAs match.
 :)
declare function hsg:division-asides($context as map(*)) {
    let $doc := $context?doc?content
    return
    if (not(exists($doc))) then ()
    else
        let $type := normalize-space(($doc//tei:bibl[@type='frus-division-type'])[1])
        let $subtype := normalize-space(($doc//tei:bibl[@type='frus-division-subtype'])[1])
        (: fh:facets parity: no persons/terms panels on container listings
           (compilation, chapter) or the index. Other divisions collect their
           references below; the register list pages themselves mark entries
           with @sameAs, not @corresp/@target, so they naturally list
           nothing. :)
        let $show-registers := not($type = 'compilation' or starts-with($type, 'chapter') or $subtype = 'index')
        let $publication := config:get-relpath($doc, $config:data-default) => tokenize("/") => head()
        let $registers :=
            if (not($show-registers)) then () else (
                hsg:register-list($context, $publication,
                    'historicaldocuments.persons', 'Persons', 'persons',
                    $doc//tei:persName/@corresp,
                    doc($config:data-default || "/" || $publication || "/front/persons.xml")//tei:persName[@sameAs]),
                hsg:register-list($context, $publication,
                    'historicaldocuments.terms', 'Abbreviations &amp; Terms', 'terms',
                    $doc//tei:gloss/@target,
                    doc($config:data-default || "/" || $publication || "/front/terms.xml")//tei:term[@sameAs])
            )
        return
            if (empty($registers)) then ()
            else
                <nav class="usa-in-page-nav__nav hsg-frus__registers" aria-labelledby="hsg-registers-heading">
                    <h2 class="usa-in-page-nav__heading" id="hsg-registers-heading">
                        <pb-i18n key="historicaldocuments.onThisPage">On this page</pb-i18n>
                    </h2>
                    {$registers}
                </nav>
};

(:~
 : One register list (Persons or Abbreviations &amp; Terms): every distinct
 : reference the division makes, resolved against the volume's register and
 : rendered as a link to the register page, with the entry's description as
 : a USWDS tooltip -- fh:get-persons/fh:get-gloss parity, including the
 : name-sorted order and the hide-if-empty behaviour (a division with no
 : references gets no list).
 :
 : Both sides are grouped rather than scanned: $idrefs arrives with
 : duplicates (a division names the same person up to 249 times) and the
 : register runs to 441 entries, so one group-by pass over each side turns
 : the pairing into a map lookup.
 :)
declare %private function hsg:register-list($context as map(*), $publication as xs:string,
        $key as xs:string, $label as xs:string, $page as xs:string,
        $idrefs as node()*, $register as element()*) {
    let $byId := map:merge(
        for $entry in $register
        group by $id := string($entry/@sameAs)
        return map:entry($id, head($entry))
    )
    let $href := $context?context-path || "/historicaldocuments/" || $publication || "/" || $page
    let $entries :=
        for $ref in $idrefs
        group by $idref := string($ref)
        let $name := $byId($idref)
        where exists($name)
        let $display := normalize-space($name)
        let $description := hsg:register-description($name)
        order by $display
        return
            <li class="usa-in-page-nav__item">{
                if ($description) then
                    <a href="{$href}{$idref}" class="usa-tooltip" data-position="top"
                        title="{$description}">{$display}</a>
                else
                    <a href="{$href}{$idref}">{$display}</a>
            }</li>
    return
        if (empty($entries)) then ()
        else
            <ul class="usa-in-page-nav__list hsg-frus__register-list">
                <li class="usa-in-page-nav__item usa-in-page-nav__item--primary">
                    <a href="{$href}"><pb-i18n key="{$key}">{$label}</pb-i18n></a>
                </li>
                {$entries}
            </ul>
};

(:~
 : A register entry's description: the text following the name -- following
 : siblings of the wrapping hi when the name sits inside one (the usual
 : encoding: item/hi/persName), of the name itself otherwise -- with the
 : leading comma stripped. fh:get-persons/fh:get-gloss parity.
 :)
declare %private function hsg:register-description($name as element()) as xs:string {
    let $following :=
        if ($name/parent::tei:hi) then
            $name/parent::tei:hi/following-sibling::node()
        else
            $name/following-sibling::node()
    return normalize-space(replace(string-join($following, ''), '^\s*,\s*', ''))
};

(:~
 : The data a division listing page's markup (templates/pages/volume/
 : division-listing.html) is built from: the division, its volume id, title
 : and type, the ?start=N offset and child count for the pagination (#1079),
 : and the children on the current page with their division types, in
 : document order. None without a division.
 :)
declare function hsg:division-listing($context as map(*)) as map(*)? {
    let $doc := $context?doc?content
    return
    if (not(exists($doc))) then ()
    else
        let $includes := $doc//tei:text//xi:include
        let $start := max((1, xs:integer((page:parameter($context, "start", 1)[. castable as xs:integer], 1)[1])))
        return map {
            "doc": $doc,
            "publication": ($doc//tei:bibl[@type='frus-volume-id'])[1]/string(),
            (: Line break between date-range title and subtitle, reference
               parity (OP#1085). :)
            "title": hsg:split-title($doc//tei:teiHeader//tei:titleStmt/tei:title),
            "type": normalize-space(($doc//tei:bibl[@type='frus-division-type'])[1]),
            "start": $start,
            "total": count($includes),
            (: Only the current page's targets are opened. :)
            "entries":
                for $inc in subsequence($includes, $start, $hsg:listing-page-size)
                let $target := doc(util:collection-name($inc) || '/' || $inc/@href)/tei:TEI
                return map {
                    "target": $target,
                    "type": normalize-space(($target//tei:bibl[@type='frus-division-type'])[1])
                }
        }
};

declare variable $hsg:listing-page-size := 30;

(:~
 : A division's own notes, below its title: inline notes in its text (the
 : "will be published once all documents have been cleared" notice of a
 : pending chapter) and the footnote its heading points to, where the data
 : carries the note's text.
 :)
declare function hsg:division-notes($doc as node(), $publication as xs:string, $context as map(*)) as element(div)? {
    let $text := $doc//tei:text
    let $anchors := $text//tei:head//tei:anchor/@xml:id ! ('#' || .)
    let $notes := (
        $text//tei:note[not(ancestor::tei:note)],
        $doc//tei:standOff//tei:note[@corresp = $anchors]
    )
    return
        if (empty($notes)) then ()
        else
            <div class="hsg-frus__division-notes">
            {
                for $note in $notes
                return <p>{hsg:note-content($note/node(), $publication, $context)}</p>
            }
            </div>
};

(:~ A note's text with its references kept as links into the volume. :)
declare %private function hsg:note-content($nodes as node()*, $publication as xs:string, $context as map(*)) as node()* {
    for $node in $nodes
    return
        typeswitch ($node)
            case element(tei:ref) return
                let $target := string($node/@target)
                return
                    <a href="{if (starts-with($target, '#')) then $context?context-path || '/historicaldocuments/' || $publication || '/' || substring($target, 2) else $target}">{
                        hsg:note-content($node/node(), $publication, $context)
                    }</a>
            case element(tei:p) return hsg:note-content($node/node(), $publication, $context)
            case element() return hsg:note-content($node/node(), $publication, $context)
            case text() return text { replace($node, '\s+', ' ') }
            default return ()
};

(:~
 : USWDS pagination for a listing of $total entries shown $hsg:listing-page-size
 : at a time, the current page being the one holding entry $start. None for
 : a listing that fits one page.
 :)
declare function hsg:listing-pagination($context as map(*), $start as xs:integer, $total as xs:integer) as element(nav)? {
    let $size := $hsg:listing-page-size
    let $last := xs:integer(ceiling($total div $size))
    let $current := xs:integer(ceiling($start div $size))
    return
        if ($last le 1) then ()
        else
            <nav aria-label="Pagination" class="usa-pagination hsg-frus__pagination">
                <ul class="usa-pagination__list">
                {
                    if ($current le 1) then () else hsg:pagination-arrow($context, ($current - 2) * $size + 1, 'previous'),
                    for $item in hsg:page-window($current, $last)
                    return
                        if ($item instance of xs:string) then
                            <li class="usa-pagination__item usa-pagination__overflow" role="presentation"><span>{$item}</span></li>
                        else
                            <li class="usa-pagination__item usa-pagination__page-no">
                                <a href="?start={($item - 1) * $size + 1}" class="usa-pagination__button{if ($item eq $current) then ' usa-current' else ''}" aria-label="Page {$item}">
                                {if ($item ne $current) then () else attribute aria-current {'page'}}
                                {$item}
                                </a>
                            </li>,
                    if ($current ge $last) then () else hsg:pagination-arrow($context, $current * $size + 1, 'next')
                }
                </ul>
            </nav>
};

declare %private function hsg:pagination-arrow($context as map(*), $start as xs:integer, $direction as xs:string) as element(li) {
    let $previous := $direction eq 'previous'
    let $icon :=
        <svg class="usa-icon" aria-hidden="true" focusable="false" role="img">
            <use href="{$context?context-path}/resources/images/sprite.svg#{if ($previous) then 'navigate_before' else 'navigate_next'}"/>
        </svg>
    let $label := <span class="usa-pagination__link-text">{if ($previous) then 'Previous' else 'Next'}</span>
    return
        <li class="usa-pagination__item usa-pagination__arrow">
            <a href="?start={$start}" class="usa-pagination__link usa-pagination__{$direction}-page" aria-label="{if ($previous) then 'Previous' else 'Next'} page">
                {if ($previous) then ($icon, $label) else ($label, $icon)}
            </a>
        </li>
};

(:~
 : The page numbers to show, with "…" standing for a skipped run: USWDS's
 : pagination pattern, which always keeps the first and last page and holds
 : the whole control to at most seven slots however many pages there are.
 : Shared with the search results (search.xqm).
 :)
declare function hsg:page-window($current as xs:integer, $last as xs:integer) as item()* {
    if ($last le 7) then
        1 to $last
    else if ($current le 4) then
        (1 to 5, "&#8230;", $last)
    else if ($current ge $last - 3) then
        (1, "&#8230;", ($last - 4) to $last)
    else
        (1, "&#8230;", ($current - 1) to ($current + 1), "&#8230;", $last)
};

(:~ One document card in a listing: number-prefixed title link, then source,
 : location, date and summary rows, and a link to the document's first page
 : scan. An unpublished ('document-pending') document is shown muted and
 : unlinked -- it has no page of its own yet. :)
declare function hsg:doclist-document($target as element(tei:TEI), $publication as xs:string,
        $type as xs:string, $context as map(*)) {
    let $number := hsg:document-number($target)
    let $id := normalize-space(($target//tei:bibl[@type='frus-division-id'])[1])
    let $head := normalize-space(($target//tei:text/tei:body//tei:head)[1])
    (: The head already begins with the number ("72. Telegram..."); fall back
       to a synthesised label only for a pending document with no real head. :)
    let $title := if ($head != '') then $head else ('Document ' || $number)
    let $dateline := ($target//tei:text/tei:body//tei:opener/tei:dateline)[1]
    let $place := normalize-space(($dateline//tei:placeName)[1])
    let $date := normalize-space(($dateline//tei:date)[1])
    let $summary := normalize-space(($target//tei:standOff//tei:note[@type='summary'])[1])
    let $source := normalize-space(($target//tei:standOff//tei:note[@type='source'])[1])
    let $pending := ends-with($type, '-pending')
    let $rows := (
        if ($source eq '') then () else hsg:doclist-row('Source', $source),
        if ($place eq '') then () else hsg:doclist-row('Location', $place),
        (: A dateline without a marked-up date still says when: show it whole. :)
        if ($date != '') then hsg:doclist-row('Date', $date)
        else if ($place ne '' or normalize-space($dateline) eq '') then ()
        else hsg:doclist-row('Date', normalize-space($dateline)),
        if ($summary eq '') then () else hsg:doclist-row('Summary', $summary)
    )
    let $page := if ($pending) then () else hsg:first-page-scan($target, $publication)
    return
        <li class="hsg-frus__doc-entry{if ($pending) then ' pending' else ''}">
            <h2 class="hsg-frus__doc-title">
                {
                    if ($pending or $id = '') then
                        <span>{$title}</span>
                    else
                        <a href="{$context?context-path}/historicaldocuments/{$publication}/{$id}">{$title}</a>
                }
            </h2>
            {if (empty($rows)) then () else <dl class="hsg-frus__doc-meta">{$rows}</dl>}
            {
                if (empty($page)) then () else
                    <a class="usa-button hsg-frus__facsimile" href="{$context?context-path}/historicaldocuments/{$publication}/pg_{$page}">
                        <span class="hsg-frus__facsimile-icon" aria-hidden="true"></span>
                        Facsimile Page
                    </a>
            }
        </li>
};

declare %private function hsg:doclist-row($label as xs:string, $value as xs:string) as element()+ {
    <dt>{$label}</dt>,
    <dd>{$value}</dd>
};

(:~
 : The page of a document's first page break in the pg_{n} facsimile view,
 : when the volume has a scan of it. The page break names its volume page
 : itself, by @sameAs ("frus:frus1981-88v05/pg1") or its own pg id; a
 : document numbering its pages on its own (the microfiche supplements'
 : "eta_d1-1") has no volume page, so no link -- its page number would
 : resolve to an unrelated page. Same lookup as the view
 : (hsgapi:view-facsimile), so the link never leads to a 404.
 :)
declare %private function hsg:first-page-scan($target as element(tei:TEI), $publication as xs:string) as xs:string? {
    let $break := ($target//tei:text//tei:pb[@facs])[1]
    let $id := if ($break/@sameAs) then tokenize($break/@sameAs, '/')[last()] else string($break/@xml:id)
    let $pb :=
        if (not(matches($id, '^pg.'))) then ()
        else (collection($config:data-default || "/" || $publication)/id($id))[self::tei:pb][1]
    return
        if (empty($pb) or empty(global:iiif-facs-id((), $pb))) then () else substring($id, 3)
};

(:~ A child division (a compilation's chapters, a chapter's subchapters): a
 : titled link with its document range, muted when unpublished. :)
declare function hsg:doclist-division($target as element(tei:TEI), $publication as xs:string,
        $type as xs:string, $context as map(*)) {
    let $id := normalize-space(($target//tei:bibl[@type='frus-division-id'])[1])
    (: Line break between date-range title and subtitle, reference parity
       (OP#1085). :)
    let $title := hsg:split-title($target//tei:teiHeader//tei:titleStmt/tei:title)
    let $range := hsg:document-range-text(hsg:document-range($target))
    let $pending := ends-with($type, '-pending')
    return
        <li class="hsg-frus__doc-entry hsg-frus__division-entry{if ($pending) then ' pending' else ''}">
            <h2 class="hsg-frus__doc-title">
                <a href="{$context?context-path}/historicaldocuments/{$publication}/{$id}">{$title}</a>
            </h2>
            {if (empty($range)) then () else <p class="hsg-frus__doc-range">{$range}</p>}
        </li>
};

(:~
 : Previous / next navigation for a division page, built from the document's own
 : relatedItem prev/next targets (relative file paths in notesStmt). Reference
 : parity with hsg-shell's reading order, which descends into and ascends out of
 : the volume tree (a chapter's "next" is its first document; a document's
 : "next" is the following document, or the next chapter at a boundary).
 :)
declare %private function hsg:prev-next-targets($context as map(*)) as map(*) {
    let $doc := $context?doc?content
    return
    if (not(exists($doc))) then map {}
    else
        let $base := util:collection-name(root($doc))
        let $type := normalize-space(($doc//tei:bibl[@type='frus-division-type'])[1])
        let $notesStmt := $doc//tei:notesStmt
        (: A chapter's "previous" is its parent compilation -- one level up, e.g.
           back to "Western Europe" -- not the previous chapter's last document
           (which for a pending chapter would be an unnumbered "Document"). Its
           "next" is its first document. Reference parity with hsg-shell, where
           both Canada and FRG point back to the compilation. Documents keep the
           encoded prev/next reading order. :)
        let $prevTarget :=
            if (starts-with($type, 'chapter')) then
                ($notesStmt/tei:relatedItem[@type='parent']/@target)[1]
            else
                ($notesStmt/tei:relatedItem[@type='prev']/@target)[1]
        return map {
            "prev": hsg:nav-target($base, $prevTarget),
            "next": hsg:nav-target($base, ($notesStmt/tei:relatedItem[@type='next']/@target)[1])
        }
};

(:~
 : The head metadata for a doc-backed page (OP#629): a meta description
 : derived entirely from the teiHeader (no ODD cycle), and link rel prev/
 : next mirroring the on-page pager (Google ignores the link relations
 : nowadays but other engines still read them). Non-FRUS doc pages and
 : pages without a description-worthy header emit nothing rather than
 : boilerplate; the reference site's static "history.state.gov 3.0 shell"
 : description is deliberately not copied.
 :)
declare function hsg:head-meta($context as map(*)) as element()* {
    if (not(exists($context?doc))) then ()
    else
        let $doc := $context?doc?content
        let $division-type := normalize-space(($doc//tei:bibl[@type='frus-division-type'])[1])
        let $volume-title := hsg:volume-title($doc)
        let $division-title := normalize-space(string-join($doc//tei:fileDesc/tei:titleStmt/tei:title, ' '))
        let $description :=
            if ($division-type = 'document') then
                let $num := hsg:document-number($doc)
                return string-join((
                    $division-title[. ne ''],
                    "Document " || $num || " of " || $volume-title,
                    "Office of the Historian"), " &#8212; ")
            else if ($division-type ne '' and $volume-title[. ne '']) then
                string-join(($division-title[. ne ''], $volume-title,
                    "Office of the Historian"), " &#8212; ")
            else if (empty($volume-title[. ne ''])) then ()
            else $volume-title || " &#8212; Foreign Relations of the United States, Office of the Historian, U.S. Department of State"
        let $targets := hsg:prev-next-targets($context)
        return (
            $description[. ne ''] ! <meta name="description" content="{.}"/>,
            $targets?prev ! <link rel="prev" href="{$context?context-path}/historicaldocuments/{?publication}/{?id}"/>,
            $targets?next ! <link rel="next" href="{$context?context-path}/historicaldocuments/{?publication}/{?id}"/>
        )
};

declare function hsg:prev-next($context as map(*)) {
    let $doc := $context?doc?content
    return
    if (not(exists($doc))) then ()
    else
        let $targets := hsg:prev-next-targets($context)
        let $prev := $targets?prev
        let $next := $targets?next
        return
            if (empty($prev) and empty($next)) then ()
            else
                <nav class="hsg-frus__pager" aria-label="Document navigation">
                    {
                        if (exists($prev)) then
                            <a class="hsg-frus__pager-link hsg-frus__pager-prev" rel="prev"
                                href="{$context?context-path}/historicaldocuments/{$prev?publication}/{$prev?id}">
                                <span class="hsg-frus__pager-arrow" aria-hidden="true">&#8592;</span>
                                <span class="hsg-frus__pager-label">{$prev?label}</span>
                            </a>
                        else <span class="hsg-frus__pager-link hsg-frus__pager-empty"/>
                    }
                    {
                        if (exists($next)) then
                            <a class="hsg-frus__pager-link hsg-frus__pager-next" rel="next"
                                href="{$context?context-path}/historicaldocuments/{$next?publication}/{$next?id}">
                                <span class="hsg-frus__pager-label">{$next?label}</span>
                                <span class="hsg-frus__pager-arrow" aria-hidden="true">&#8594;</span>
                            </a>
                        else <span class="hsg-frus__pager-link hsg-frus__pager-empty"/>
                    }
                </nav>
};

(:~
 : The deep-zoom facsimile viewer of the pg_* facsimile page (OP#1335): a
 : pb-facsimile subscribed to the "transcription" channel its emit-on-load
 : pb-facs-link trigger emits on; the image server base is the shared
 : $global:iiif-image-api. Control set mirrors the reference viewer's
 : OpenSeadragon options (hsg-shell app.js: navigator shown, zoom controls,
 : no sequence buttons).
 :)
declare %private function hsg:facsimile-viewer() as element() {
    <pb-facsimile subscribe="transcription"
        base-uri="{$global:iiif-image-api}"
        default-zoom-level="0"
        show-navigation-control="show-navigation-control"
        show-navigator="show-navigator"
        show-home-control="show-home-control"
        show-full-page-control="show-full-page-control"/>
};

(:~
 : Main content of the pg_* facsimile page (OP#1335): the legacy
 : /historicaldocuments/{volume}/pg_{n} deep links hsg-shell served (each
 : "[Page N]" link in a document resolves there, and the URLs are cited
 : externally). Driven by the $context?facsimile map assembled in
 : hsgapi:view-facsimile: a visually hidden pb-facs-link with emit-on-load
 : pushes the single page scan into the viewer when the page loads, the
 : noscript fallback shows the static medium PNG like the reference page
 : did, and the pager steps through the volume's facsimile sequence
 : (reference parity: pg_315 &#8592; pg_316 &#8594; pg_317).
 :)
(:~
 : Navigation title for the pg_* facsimile page: the same quiet volume-title
 : h2 hsg:navigation-title puts on interior division pages, resolved from
 : the publication id in $context?facsimile because this page has no context
 : document (see hsgapi:view-facsimile).
 :)
declare function hsg:facsimile-title($context as map(*)) as element(h2)? {
    let $title := hsg:publication-title($context?facsimile?publication)
    return
        if (empty($title)) then () else (
            <h2 class="hsg-navigation-title" id="navigation-title">{$title}</h2>
        )
};

(:~
 : Trail of the pg_* facsimile page (reference parity: Historical
 : Documents > volume title > Page N), resolved from $context?facsimile
 : because this page has no context document.
 :)
declare function hsg:facsimile-trail($context as map(*)) as map(*)* {
    let $facs := $context?facsimile
    return
        if (empty($facs)) then ()
        else
            hsg:section-trail("historicaldocuments", (
                hsg:crumb(hsg:publication-title($facs?publication), "/historicaldocuments/" || $facs?publication),
                hsg:crumb("Page " || $facs?n, ())
            ))
};

(:~
 : "Show Documents on this Page" panel in the pg_* facsimile page's aside
 : (hsg-shell side:docs-on-page parity, OP#1335): links to every document
 : whose printed text appears on the page, computed in
 : hsgapi:docs-on-page and threaded through $context?facsimile?docs.
 : Deliberate deviation from the reference: hsg-shell rendered the panel
 : shell with an empty list on pages without documents (front matter);
 : like the register panels, this one is dropped entirely instead.
 :)
declare function hsg:facsimile-docs($context as map(*)) {
    if (empty($context?facsimile?docs) or array:size($context?facsimile?docs) = 0) then (
        (: No documents to display :)
    ) else (
        <div class="hsg-panel hsg-frus__docs-on-page">
            <h2 class="hsg-sidebar-title">
                <pb-i18n key="historicaldocuments.docs-on-page">Show Documents on this Page</pb-i18n>
            </h2>
            <ul class="hsg-list-group">
            {
                let $publication := $context?facsimile?publication
                let $path := $context?context-path
                for $doc in $context?facsimile?docs?*
                return
                    <li>
                        <a href="{$path}/historicaldocuments/{$publication}/{$doc?id}">{$doc?label}</a>
                    </li>
            }
            </ul>
        </div>
    )
};

declare function hsg:facsimile-page($context as map(*)) {
    let $facs := $context?facsimile
    return
        if (empty($facs)) then ()
        else
            <section class="hsg-frus__facsimile-page">
                <pb-facs-link class="hsg-frus__facsimile-trigger" facs="{$facs?image}" order="1"
                    emit="transcription" subscribe="transcription"
                    emit-on-load="emit-on-load">Page {$facs?n}</pb-facs-link>
                {hsg:facsimile-viewer()}
                {
                    if (empty($facs?png)) then () else (
                        <noscript>
                            <img class="hsg-frus__facsimile-static" src="{$facs?png}"
                                alt="Scan of page {$facs?n}"/>
                        </noscript>
                    )
                }
                {
                    if (empty($facs?prev) and empty($facs?next)) then () else (
                        <nav class="hsg-frus__pager" aria-label="Page navigation">
                            {
                                if (empty($facs?prev)) then (
                                    <span class="hsg-frus__pager-link hsg-frus__pager-empty"/>

                                ) else (
                                    <a class="hsg-frus__pager-link hsg-frus__pager-prev" rel="prev"
                                        href="{$context?context-path}/historicaldocuments/{$facs?publication}/{$facs?prev}">
                                        <span class="hsg-frus__pager-arrow" aria-hidden="true">&#8592;</span>
                                        <span class="hsg-frus__pager-label">Page {$facs?prev-n}</span>
                                    </a>
                                )
                            }
                            {
                                if (empty($facs?next)) then (
                                    <span class="hsg-frus__pager-link hsg-frus__pager-empty"/>
                                ) else (
                                    <a class="hsg-frus__pager-link hsg-frus__pager-next" rel="next"
                                        href="{$context?context-path}/historicaldocuments/{$facs?publication}/{$facs?next}">
                                        <span class="hsg-frus__pager-label">Page {$facs?next-n}</span>
                                        <span class="hsg-frus__pager-arrow" aria-hidden="true">&#8594;</span>
                                    </a>
                                )
                            }
                        </nav>
                    )
                }
            </section>
};

(:~ Resolve one relatedItem target (a file path relative to the current
 : division's own file) to the linked division's id, publication and a short
 : label. :)
declare %private function hsg:nav-target($base as xs:string, $rel as xs:string?) as map(*)? {
    if (empty($rel) or normalize-space($rel) = '') then ()
    else
        let $path := hsg:resolve-relative($base, $rel)
        let $target := doc($path)/tei:TEI
        return
            if (not(exists($target))) then ()
            else
                let $id := normalize-space(($target//tei:bibl[@type='frus-division-id'])[1])
                let $type := normalize-space(($target//tei:bibl[@type='frus-division-type'])[1])
                let $publication := normalize-space(($target//tei:bibl[@type='frus-volume-id'])[1])
                let $label :=
                    if (starts-with($type, 'document')) then
                        'Document ' || hsg:document-number($target)
                    else
                        normalize-space(string-join($target//tei:teiHeader//tei:titleStmt/tei:title, ' '))
                return
                    if ($id = '' or $publication = '') then ()
                    else map { "id": $id, "publication": $publication, "label": $label }
};

(:~ Resolve a "../a/b.xml"-style relative path against a base collection path,
 : returning the absolute database path. Used to follow relatedItem targets;
 : public because hsgapi:docs-on-page resolves attachment-source targets the
 : same way (OP#1335). :)
declare function hsg:resolve-relative($base as xs:string, $rel as xs:string) as xs:string {
    let $baseParts := tokenize($base, '/')[. != '']
    let $relParts := tokenize($rel, '/')[. != '']
    let $combined :=
        fold-left($relParts, $baseParts, function($acc, $part) {
            if ($part = '..') then $acc[position() != last()]
            else ($acc, $part)
        })
    return '/' || string-join($combined, '/')
};

(:~
 : The "Guide to Sources on Vietnam, 1969-1975" TEI monograph (OP#1301),
 : from the other-publications data package, rendered as a single page.
 : hsg-shell transformed it with the frus ODD; the guide's element inventory
 : (div/head/hi/p/lb/ref) is plain TEI the default ODD covers. Its ref
 : targets are absolute production URLs and stay untouched, exactly as the
 : reference's app:fix-links (which only rewrote $app-prefixed hrefs) left
 : them.
 :)
declare function hsg:vietnam-guide($context as map(*)) {
    let $doc := doc("/db/apps/other-publications/vietnam-guide/guide-to-sources-on-vietnam-1969-1975.xml")
    return page:transform($doc//tei:body/*)
};

(:~
 : A static content page from the app-owned data/content collection (OP#1313,
 : PR #46 review follow-up): the page's TEI document rendered through the
 : default ODD, replacing content transcribed into the HTML templates. Same
 : pattern as hsg:vietnam-guide above, but for app-owned documents; internal
 : links are encoded as app-root-relative ref targets, resolved against the
 : context path by the content-collection ref model in hsg-jinks.odd.
 :)
declare function hsg:content-page($context as map(*), $page as xs:string) {
    let $doc := doc($config:app-root || "/data/content/" || $page || ".xml")
    return page:transform($doc//tei:body/*)
};

(:~
 : A content page's display title, from its TEI header; the single static
 : template's breadcrumb uses it as the pb-i18n fallback (OP#1313, PR #50
 : review).
 :)
declare function hsg:content-title($context as map(*), $page as xs:string) as xs:string? {
    let $doc := doc($config:app-root || "/data/content/" || $page || ".xml")
    return normalize-space(head($doc//tei:titleStmt/tei:title))
};
