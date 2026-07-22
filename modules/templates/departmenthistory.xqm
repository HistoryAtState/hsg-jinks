xquery version "3.1";

module namespace dh="https://history.state.gov/ns/templates/departmenthistory";

(:~
 : Static section breadcrumb: Home > Department History > $trail. $trail is a
 : sequence of maps { "label": ..., "href": ... }; the last entry renders as
 : the current page (no link). $href is app-relative, e.g.
 : "/departmenthistory/people".
 :
 : Maps, not arrays: a trailing array literal ends in a literal "]]", which
 : collides with this templating engine's "[[ ... ]]" expression delimiter --
 : it closes the interpolation at the first "]]" it scans, truncating the
 : expression. Maps close on "}", so they cannot produce that collision.
 :
 : The section's hub and static-article pages have no backing document, so
 : there is nothing for an ODD-driven breadcrumb (hsg:collection-breadcrumbs's
 : approach on historicaldocuments) to walk -- the trail is fixed per page
 : instead. Mirrors that function's <li> shape so both breadcrumbs nest
 : identically inside the layout's shared wrapper.
 :)
declare function dh:breadcrumb($context as map(*), $trail as map(*)*) as element(li)+ {
    (
        <li>
            <a href="{$context?context-path}/">
                <pb-i18n key="breadcrumb.home">Home</pb-i18n>
            </a>
        </li>,
        if (empty($trail)) then
            <li aria-current="page">
                <pb-i18n key="breadcrumb.departmenthistory">Department History</pb-i18n>
            </li>
        else
            <li>
                <a href="{$context?context-path}/departmenthistory">
                    <pb-i18n key="breadcrumb.departmenthistory">Department History</pb-i18n>
                </a>
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
