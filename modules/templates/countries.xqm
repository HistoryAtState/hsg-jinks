xquery version "3.1";

module namespace countries="https://history.state.gov/ns/templates/countries";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : rdcr and wwdai are foreign apps (own .xar packages, not this app's own
 : data root) -- same absolute-collection-path technique used to read them
 : from countryapi:view/countryapi:archives-view.
 :)
declare variable $countries:RDCR_ARTICLES := "/db/apps/rdcr/articles";
declare variable $countries:WWDAI_ARTICLES := "/db/apps/wwdai/articles";

(:~
 : Alphabetical index of a countries/archives article collection (#1095).
 :
 : Shared by /countries/all and /countries/archives/all rather than
 : duplicated: hsg-shell's ch:list and archives:list independently
 : reimplemented "group by first letter of title" two different ways for the
 : two collections. Here it's one scan, parameterized by collection.
 :
 : Sort-title strips a leading "The " so e.g. "The Bahamas" alphabetizes
 : under B (reproducing ch:load-countries), and keeps a leading "*" marker on
 : former countries (reference-site convention: an asterisk after the title
 : denotes a former, dissolved/superseded country) -- ported as data-derived
 : caller-facing text, not re-derived structurally, since the TEI carries no
 : dedicated field for "former country" (it's expressed in the title text
 : itself in the small number of rdcr articles that need it).
 :
 : @param $collection absolute collection path, e.g. "/db/apps/rdcr/articles"
 :)
declare function countries:index-groups($collection as xs:string) as map(*)* {
    let $articles :=
        for $doc in collection($collection)/tei:TEI
        let $short := normalize-space($doc//tei:titleStmt/tei:title[@type = 'short'])
        let $sort-title :=
            if (starts-with($short, 'The ')) then
                substring-after($short, 'The ') || ', The'
            else
                $short
        return map {
            "id": tokenize(document-uri(root($doc)), '/')[last()] => substring-before('.xml'),
            "title": $short,
            "sort-title": $sort-title,
            "letter": upper-case(substring($sort-title, 1, 1))
        }
    for $group in $articles
    group by $letter := $group?letter
    order by $letter
    return map {
        "letter": $letter,
        "articles": (
            for $a in $group
            order by $a?sort-title
            return $a
        )
    }
};

declare function countries:country-groups() as map(*)* {
    countries:index-groups($countries:RDCR_ARTICLES)
};

declare function countries:archive-groups() as map(*)* {
    countries:index-groups($countries:WWDAI_ARTICLES)
};

(:~
 : The title[@type='complete'] heading, used verbatim as <h1> on article
 : pages (ch:article-heading / archives:archive-title in hsg-shell).
 :)
declare function countries:article-heading($doc as document-node()) as xs:string {
    normalize-space($doc//tei:titleStmt/tei:title[@type = 'complete'])
};

(:~
 : The "<short title> - <suffix>" page title (ch:page-title /
 : archives:archive-pagetitle in hsg-shell).
 :)
declare function countries:page-title($doc as document-node(), $suffix as xs:string) as xs:string {
    normalize-space($doc//tei:titleStmt/tei:title[@type = 'short']) || " - " || $suffix
};

(:~
 : Breadcrumb trail for a country/archive article: Home > Countries
 : [> Archives] > title. Deliberately its own function rather than reusing
 : hsg:collection-breadcrumbs (FRUS-specific: assumes documents live under
 : $config:data-default and carry frus-division-type bibls) or the
 : jinks-owned page:collection-breadcrumbs (its config:get-relpath-based walk
 : degrades to nothing for a document outside $config:data-default -- which
 : rdcr/wwdai always are). Distinguishes the two collections from
 : $context?doc?path rather than a separate flag, since vapi:view already
 : puts the absolute docid there.
 :)
declare function countries:breadcrumbs($context as map(*)) {
    if (exists($context?doc)) then (
        <li>
            <a href="{$context?context-path}/">
                <pb-i18n key="breadcrumb.home">Home</pb-i18n>
            </a>
        </li>,
        <li>
            <a href="{$context?context-path}/countries">
                <pb-i18n key="breadcrumb.countries">Countries</pb-i18n>
            </a>
        </li>,
        if (starts-with($context?doc?path, $countries:WWDAI_ARTICLES)) then
            <li>
                <a href="{$context?context-path}/countries/archives">
                    <pb-i18n key="breadcrumb.archives">Archives</pb-i18n>
                </a>
            </li>
        else (),
        <li aria-current="page">{countries:article-heading($context?doc?content)}</li>
    )
    else ()
};
