xquery version "3.1";

module namespace hsg="https://history.state.gov/ns/templates/hsg";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace xi="http://www.w3.org/2001/XInclude";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "../config.xqm";



(:~
 : The volume's table of contents, as a USWDS side navigation (#1089).
 :
 : Shape (reference parity): front matter flat, then each compilation as a node
 : with its chapters nested beneath, then the back matter. Documents are never
 : listed. The print table of contents (front/toc.xml) is omitted.
 :
 : Rendered into the layout's `before` block, so it appears on the comp, chapter
 : and document pages -- but not on the volume landing, whose TOC belongs in the
 : main content instead (#1080); see the guard below.
 :
 : The same tree is what #1080 needs in main content, so keep this the only
 : traversal.
 :)
declare function hsg:volume-toc($context as map(*)) {
    let $doc := $context?doc?content
    let $publication := ($doc//tei:bibl[@type='frus-volume-id'])[1]/string()
    return
    (: Only a division of a volume gets the sidebar. The volume file itself
       carries no typed bibl ids at all -- only its divisions do -- so an absent
       frus-volume-id is what identifies the landing page, which has no sidebar:
       its table of contents belongs in the main content (#1080). :)
    if (exists($doc) and $publication != '') then
        let $current := ($doc//tei:bibl[@type='frus-division-id'])[1]/string()
        let $current-is-document := ($doc//tei:bibl[@type='frus-division-type'])[1] = 'document'
        let $volume := doc($config:data-default || "/" || $publication || "/" || $publication || ".xml")
        let $divisions := hsg:toc-divisions($publication)
        return
            <nav aria-label="Side navigation" class="toc">
                <h5>
                    <pb-i18n key="document.contents">Contents</pb-i18n>
                </h5>
                <ul class="usa-sidenav">
                    {hsg:toc-entries($volume/tei:TEI, $divisions, $publication, $current, $current-is-document, $context)}
                </ul>
            </nav>
    else
        ()
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
        for $division in collection($config:data-default || "/" || $publication)/tei:TEI
            [tei:teiHeader//tei:bibl[@type='frus-division-type'] != 'document']
        where normalize-space(($division//tei:bibl[@type='frus-division-subtype'])[1]) != 'table-of-contents'
        return
            map:entry(($division//tei:bibl[@type='frus-division-id'])[1]/string(), $division)
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
declare %private function hsg:toc-entries($division as element(tei:TEI)?, $divisions as map(*),
        $publication as xs:string, $current as xs:string?, $current-is-document as xs:boolean,
        $context as map(*)) {
    for $include in $division//tei:text//xi:include
    let $id := $include/@xpointer/string()
    where map:contains($divisions, $id)
    let $included := $divisions($id)
    let $title := normalize-space(($included//tei:fileDesc//tei:titleStmt/tei:title)[1])
    (: current when it is the page being viewed, or -- on a document page, where
       the document itself is not listed -- when it is the division including it :)
    let $is-current :=
        $id = $current or
        ($current-is-document and exists($included//tei:text//xi:include[@xpointer = $current]))
    let $children := hsg:toc-entries($included, $divisions, $publication, $current, $current-is-document, $context)
    return
        <li class="usa-sidenav__item">
            {
                element a {
                    attribute href {
                        $context?context-path || "/historicaldocuments/" || $publication || "/" || $id
                    },
                    if ($is-current) then (
                        attribute class {"usa-current"},
                        attribute aria-current {"page"}
                    ) else (),
                    $title
                }
            }
            {
                if (exists($children)) then
                    <ul class="usa-sidenav__sublist">{$children}</ul>
                else
                    ()
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
 : hsg:collection-breadcrumbs() relies on -- so this discovers volumes rather
 : than listing them anywhere.
 :)
declare function hsg:volume-list($context as map(*)) {
    for $volume in xmldb:get-child-collections($config:data-default)
    let $path := $config:data-default || "/" || $volume || "/" || $volume || ".xml"
    where doc-available($path)
    let $title := normalize-space((doc($path)//tei:titleStmt/tei:title)[1])
    order by $title
    return
        <li>
            <a href="{$context?context-path}/historicaldocuments/{$volume}">{$title}</a>
        </li>
};

(:~
 : Generate the breadcrumb trail: Home > Historical Documents > volume title.
 : The volume title is the current (non-link) crumb only on the volume
 : landing page; on any interior page it links back there.
 :
 : When the page being viewed is itself a chapter, document, or compilation,
 : one more crumb -- the current (non-link), final one -- is appended on a
 : new line: the division's own title for a chapter or compilation, or
 : "Document <n>" (its encoded frus-document-number) for a document.
 :)
declare function hsg:collection-breadcrumbs($context as map(*)) {
    if (exists($context?doc)) then
        let $components := config:get-relpath($context?doc?content, $config:data-default) => tokenize("/")
        let $publication := $components[1]
        let $is-landing := count($components) = 2
        let $volume := doc($config:data-default || "/" || $publication || "/" || $publication || ".xml")
        let $volume-title := normalize-space(($volume//tei:titleStmt/tei:title)[1])
        let $division-type := ($context?doc?content//tei:bibl[@type='frus-division-type'])[1]/string()
        return (
            <li>
                <a href="{$context?context-path}/">
                    <pb-i18n key="breadcrumb.home">Home</pb-i18n>
                </a>
            </li>,
            <li>
                <a href="{$context?context-path}/historicaldocuments">
                    <pb-i18n key="breadcrumb.historicaldocuments">Historical Documents</pb-i18n>
                </a>
            </li>,
            if ($is-landing) then
                <li aria-current="page">{$volume-title}</li>
            else
                <li>
                    <a href="{$context?context-path}/historicaldocuments/{$publication}">{$volume-title}</a>
                </li>,
            if (not($is-landing) and $division-type = ('chapter', 'compilation')) then
                let $own-title := normalize-space(($context?doc?content//tei:titleStmt/tei:title)[1])
                return <li class="breadcrumb-current" aria-current="page">{$own-title}</li>
            else if (not($is-landing) and $division-type = 'document') then
                let $number := ($context?doc?content//tei:bibl[@type='frus-document-number'])[1]/string()
                return <li class="breadcrumb-current" aria-current="page">Document {$number}</li>
            else ()
        )

    else ()
};
