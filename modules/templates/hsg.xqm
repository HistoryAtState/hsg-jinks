xquery version "3.1";

module namespace hsg="https://history.state.gov/ns/templates/hsg";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "../config.xqm";



(:~
 : Generate a breadcrumb trail for the current collection.
 :)
declare function hsg:collection-breadcrumbs($context as map(*)) {
    if (exists($context?doc)) then
        let $components := config:get-relpath($context?doc?content, $config:data-default) => tokenize("/")
        let $publication := $components[1]
        let $chapter := $components[3]
            return (
                <li>
                    <a href="{$context?context-path}/historicaldocuments/{$publication}">
                        <pb-i18n key="breadcrumb.{string-join(subsequence($components, 1, 1), '.')}">
                            {$publication}
                        </pb-i18n>
                    </a>
                </li>,
                <li>
                    <a href="{$context?context-path}/historicaldocuments/{string-join(($publication, $chapter), '/')}">
                        <pb-i18n key="breadcrumb.{string-join(subsequence($components, 1, 3), '.')}">
                            {$chapter}
                        </pb-i18n>
                    </a>
                </li>
            )

    else ()
};
