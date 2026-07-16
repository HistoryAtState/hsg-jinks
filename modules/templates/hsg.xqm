xquery version "3.1";

module namespace hsg="https://history.state.gov/ns/templates/hsg";

declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "../config.xqm";



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
