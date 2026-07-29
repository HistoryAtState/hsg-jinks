xquery version "3.1";

module namespace tags="https://history.state.gov/ns/templates/tags";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(:~
 : Ported from hsg-shell's tags-html.xqm (not its %templates:wrap machinery,
 : which Jinks doesn't use -- same porting discipline #1096 applied to
 : pocom-html.xqm). Unlike hsg-shell, there is no external "tagged-resources"
 : study registry to join against (confirmed absent from the reference
 : implementation during #1101's research) -- tag assignments are read
 : directly from teiHeader tei:keywords[@scheme=SCHEME]/tei:term on FRUS
 : volumes and Secretary of State biographies, exactly as hsg-shell main
 : itself already does.
 :
 : The taxonomy itself is the #1177 conversion's stored TEI document (native
 : tei:taxonomy/tei:category/tei:catDesc), not the bespoke source format --
 : must stay a real stored document (see tools/convert-taxonomy.xql's own
 : doc comment for why an in-memory/detached version is unsafe).
 :)
declare variable $tags:SCHEME := "https://history.state.gov/tags";
declare variable $tags:TAXONOMY_DOC := "/db/apps/hsg-jinks/data/tags/taxonomy.xml";
declare variable $tags:FRUS_COL := "/db/apps/frus-data-jinks/data/Publications";
declare variable $tags:SECRETARY_BIOS_COL := "/db/apps/other-publications/secretary-bios";

(:~ Every tei:keywords element carrying this section's scheme, across both tagged collections. :)
declare %private function tags:all-keywords() as element(tei:keywords)* {
    (
        collection($tags:FRUS_COL)//tei:keywords[@scheme eq $tags:SCHEME],
        collection($tags:SECRETARY_BIOS_COL)//tei:keywords[@scheme eq $tags:SCHEME]
    )
};

(:~ Resolve a taxonomy id to its tei:category element, or the empty sequence if unknown. :)
declare function tags:taxonomy-entry($tagId as xs:string?) as element(tei:category)? {
    if (empty($tagId)) then ()
    else doc($tags:TAXONOMY_DOC)//tei:category[@xml:id eq $tagId]
};

declare function tags:taxonomy-label($tagId as xs:string?) as xs:string? {
    tags:taxonomy-entry($tagId)/tei:catDesc/tei:term/string()
};

(:~ Total number of taxonomy subjects (categories + tags), for the landing page's live count. :)
declare function tags:tag-count() as xs:integer {
    count(doc($tags:TAXONOMY_DOC)//tei:category)
};

(:~ Distinct FRUS volumes carrying at least one tag (landing-page count). :)
declare function tags:tagged-frus-volume-count() as xs:integer {
    count(distinct-values(collection($tags:FRUS_COL)//tei:keywords[@scheme eq $tags:SCHEME]/root(.)/tei:TEI/@xml:id))
};

(:~ Distinct Secretary biographies carrying at least one tag (landing-page count). :)
declare function tags:tagged-secretary-count() as xs:integer {
    count(distinct-values(collection($tags:SECRETARY_BIOS_COL)//tei:keywords[@scheme eq $tags:SCHEME]/root(.)/tei:TEI/@xml:id))
};

(:~ Total tag *assignments* (every tei:term, not distinct) across both collections -- landing-page count. :)
declare function tags:total-tag-assignments() as xs:integer {
    count(tags:all-keywords()/tei:term)
};

(:~
 : Landing-page narrative (#1174), ported verbatim from the reference site's
 : /tags text (curly quotes and all) with the reference's hardcoded counts
 : replaced by tags:tag-count()/tagged-secretary-count()/
 : tagged-frus-volume-count()/total-tag-assignments() -- PR #19 review:
 : the first draft substituted a "usa-summary-box" + bullet list that matched
 : nothing on the reference site and dropped two of its three paragraphs
 : along with several inline links; this replaces that with the actual
 : reference wording and every one of its links (People/Places/Topics/full
 : taxonomy, the Secretaries biographies list, and the FRUS series itself).
 :)
declare function tags:landing-intro($context as map(*)) as element(p)+ {
    let $cp := $context?context-path
    return (
        <p>The Office of the Historian&#x2019;s &#x201C;Subject Taxonomy of the History of U.S.
            Foreign Relations&#x201D; covers {tags:tag-count()}
            subjects, organized into three major sections: <a href="{$cp}/tags/people">People</a>, <a href="{$cp}/tags/places">Places</a>, and <a href="{$cp}/tags/topics">Topics</a>. Drill into
            one of these sections, or view <a href="{$cp}/tags/all">the full
                taxonomy</a>.</p>,
        <p>The taxonomy has been applied to a small but growing segment of the
            resources on the Office of the Historian&#x2019;s website: {tags:tagged-secretary-count()}
            <a href="{$cp}/departmenthistory/people/secretaries"> biographies of the
                Secretaries of State</a> and {tags:tagged-frus-volume-count()} volumes from the <a href="{$cp}/historicaldocuments">
                <em>Foreign Relations of the United States</em>
            </a> series.</p>,
        <p>With {format-number(tags:total-tag-assignments(), "#,###")} tags applied to
            date, this growing resource exposes connections across the accumulated
            knowledge of the Office of the Historian.</p>
    )
};

(:~ FRUS volumes directly tagged with exactly this id (not descendant-inclusive). :)
declare function tags:tagged-frus-volumes($tagId as xs:string) as element(tei:TEI)* {
    collection($tags:FRUS_COL)//tei:keywords[@scheme eq $tags:SCHEME][tei:term = $tagId]/root(.)/tei:TEI
};

(:~ Secretary biographies directly tagged with exactly this id (not descendant-inclusive). :)
declare function tags:tagged-secretaries($tagId as xs:string) as element(tei:TEI)* {
    collection($tags:SECRETARY_BIOS_COL)//tei:keywords[@scheme eq $tags:SCHEME][tei:term = $tagId]/root(.)/tei:TEI
};

(:~ An entry's own id plus every descendant category/tag id -- the set a parent's hit-count aggregates over. :)
declare function tags:descendant-ids($entry as element(tei:category)) as xs:string* {
    ($entry/@xml:id/string(), $entry//tei:category/@xml:id/string())
};

(:~
 : Descendant-inclusive hit count: how many tag assignments (across both
 : collections) name this entry's own id or any id beneath it. Mirrors
 : hsg-shell's tags:descend hit-count computation.
 :)
(:~
 : Materializes the term sequence into a variable before filtering rather
 : than chaining tags:all-keywords()/tei:term[predicate] in one path
 : expression -- eXist was observed to silently drop matches when the
 : predicate is chained directly onto a child step over a sequence unioned
 : from two different collection() calls (confirmed live: identical
 : predicate, only the intermediate-variable form returns correct counts).
 :)
declare function tags:hit-count($entry as element(tei:category)) as xs:integer {
    let $terms := tags:all-keywords()/tei:term
    let $ids := tags:descendant-ids($entry)
    return count($terms[. = $ids])
};

(:~ Immediate child categories/tags with their own descendant-inclusive hit counts, for drill-down rendering. :)
declare function tags:children-with-counts($entry as element(tei:category)) as map(*)* {
    for $child in $entry/tei:category
    order by $child/tei:catDesc/tei:term
    return map { "entry": $child, "count": tags:hit-count($child) }
};

(:~
 : Render a catDesc/tei:p's mixed content: text passes through, tei:ptr
 : cross-references resolve to /tags/{id} links (target is "#id", TEI-style),
 : tei:ref (converted from the one hand-authored <a href> in the source)
 : passes through as an external link.
 :)
declare function tags:prose-html($nodes as node()*, $context as map(*)) as node()* {
    for $n in $nodes
    return
        typeswitch ($n)
            case text() return $n
            case element(tei:ptr) return
                let $target := substring-after($n/@target, "#")
                return <a href="{$context?context-path}/tags/{$target}">{tags:taxonomy-label($target)}</a>
            case element(tei:ref) return
                <a href="{$n/@target}">{tags:prose-html($n/node(), $context)}</a>
            default return
                tags:prose-html($n/node(), $context)
};

declare function tags:definition-html($entry as element(tei:category), $context as map(*)) as element(p)? {
    let $p := $entry/tei:catDesc/tei:p
    return
        if (exists($p)) then
            <p>{tags:prose-html($p/node(), $context)}</p>
        else ()
};

(:~ Recursive nested list of the entire taxonomy tree, for /tags/all. No counts -- a full-tree listing, not an aggregation view. :)
declare function tags:all-taxonomy-html($context as map(*)) as element(ul) {
    <ul class="usa-list">
        {
            for $entry in doc($tags:TAXONOMY_DOC)//tei:taxonomy/tei:category
            return tags:taxonomy-entry-html($entry, $context)
        }
    </ul>
};

declare %private function tags:taxonomy-entry-html($entry as element(tei:category), $context as map(*)) as element(li) {
    let $id := $entry/@xml:id/string()
    return
        <li>
            <a href="{$context?context-path}/tags/{$id}">{$entry/tei:catDesc/tei:term/string()}</a>
            {
                let $def := $entry/tei:catDesc/tei:p
                return
                    if (exists($def)) then
                        <span class="tags-definition"><em> — {tags:prose-html($def/node(), $context)}</em></span>
                    else ()
            }
            {
                if (exists($entry/tei:category)) then
                    <ul class="usa-list">
                        { for $child in $entry/tei:category return tags:taxonomy-entry-html($child, $context) }
                    </ul>
                else ()
            }
        </li>
};

(:~
 : Sole coupling point back into the historicaldocuments section (named in
 : #1101's own epic description, not its own ticket): a FRUS volume-landing
 : page's own tei:keywords terms, linked to their /tags/{id} pages. Mirrors
 : hsg-shell's tags:load-tags/tags:list-tags/frus:hide-tags-if-empty trio,
 : collapsed into one function since this templating engine has no
 : %templates:wrap equivalent -- renders nothing (not an empty panel) when
 : the volume carries no tags.
 :)
declare function tags:volume-tags-panel($context as map(*)) as element(nav)? {
    let $doc := $context?doc?content
    let $terms := distinct-values($doc//tei:keywords[@scheme eq $tags:SCHEME]/tei:term)
    return
        if (empty($terms)) then ()
        else
            <nav aria-label="Tags" class="tags-panel">
                <h5><pb-i18n key="tags.panel-heading">Tags</pb-i18n></h5>
                <ul class="usa-sidenav">
                    {
                        for $term in $terms
                        let $label := tags:taxonomy-label($term)
                        order by $label
                        return
                            <li class="usa-sidenav__item">
                                <a href="{$context?context-path}/tags/{$term}" title="Resources tagged {$label}">{$label}</a>
                            </li>
                    }
                </ul>
            </nav>
};

(:~
 : Same breadcrumb shape as dh:breadcrumb (departmenthistory.xqm) -- the
 : section has no backing document for its hub pages, so the trail is fixed
 : per page rather than walked off an ODD structure.
 :)
declare function tags:breadcrumb($context as map(*), $trail as map(*)*) as element(li)+ {
    (
        <li>
            <a href="{$context?context-path}/">
                <pb-i18n key="breadcrumb.home">Home</pb-i18n>
            </a>
        </li>,
        if (empty($trail)) then
            <li aria-current="page">
                <pb-i18n key="breadcrumb.tags">Tags</pb-i18n>
            </li>
        else
            <li>
                <a href="{$context?context-path}/tags">
                    <pb-i18n key="breadcrumb.tags">Tags</pb-i18n>
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

(:~
 : Browse page for one taxonomy entry (#1176). Three states, mirroring
 : hsg-shell's tags:show-tag: direct hits (tagged secretaries and/or FRUS
 : volumes for this exact id, plus a child drill-down if the entry has
 : children); "dig deeper" (no direct hits, but a descendant id does --
 : recursive descendant-inclusive drill-down); empty (nothing tagged
 : anywhere beneath this id).
 :)
declare function tags:show-tag($context as map(*)) as element(div) {
    let $tagId := $context?request?parameters?tagId
    let $entry := tags:taxonomy-entry($tagId)
    let $secretaries := tags:tagged-secretaries($tagId)
    let $volumes := tags:tagged-frus-volumes($tagId)
    let $children := tags:children-with-counts($entry)
    return
        <div>
            <h1>{$entry/tei:catDesc/tei:term/string()}</h1>
            {tags:definition-html($entry, $context)}
            {
                if (exists($secretaries) or exists($volumes)) then
                    (
                        if (exists($secretaries)) then
                            <div class="tags-resources">
                                <h2>Biographies of the Secretaries of State ({count($secretaries)})</h2>
                                <ul class="usa-collection">
                                    {
                                        for $bio in $secretaries
                                        order by $bio/tei:teiHeader//tei:titleStmt/tei:title[@type eq 'short']
                                        return
                                            <li class="usa-collection__item">
                                                <a href="{$context?context-path}/departmenthistory/people/{$bio/@xml:id}">
                                                    {$bio/tei:teiHeader//tei:titleStmt/tei:title[@type eq 'short']/string()}
                                                </a>
                                            </li>
                                    }
                                </ul>
                            </div>
                        else (),
                        if (exists($volumes)) then
                            <div class="tags-resources">
                                <h2><em>Foreign Relations</em> volumes ({count($volumes)})</h2>
                                <ul class="usa-collection">
                                    {
                                        for $vol in $volumes
                                        order by $vol/@xml:id
                                        return
                                            <li class="usa-collection__item">
                                                <a href="{$context?context-path}/historicaldocuments/{$vol/@xml:id}">
                                                    {normalize-space(($vol/tei:teiHeader//tei:titleStmt/tei:title)[1])}
                                                </a>
                                            </li>
                                    }
                                </ul>
                            </div>
                        else (),
                        if (exists($children)) then
                            tags:drill-down-html($children, "Resources covering specific subjects within " || $entry/tei:catDesc/tei:term/string(), $context)
                        else ()
                    )
                else if (exists($children[?count gt 0])) then
                    (
                        <p>No resources have been specifically identified as "{$entry/tei:catDesc/tei:term/string()}",
                        but resources beneath this level in the taxonomy have been tagged. Please dig deeper:</p>,
                        tags:drill-down-html($children, (), $context)
                    )
                else
                    <p>No resources have been tagged "{$entry/tei:catDesc/tei:term/string()}".</p>
            }
        </div>
};

declare %private function tags:drill-down-html($children as map(*)*, $heading as xs:string?, $context as map(*)) as element(div) {
    <div class="tags-drilldown">
        { if (exists($heading)) then <h2>{$heading}</h2> else () }
        <ul class="usa-sidenav">
            {
                for $child in $children
                return
                    <li class="usa-sidenav__item">
                        <a href="{$context?context-path}/tags/{$child?entry/@xml:id}">
                            {$child?entry/tei:catDesc/tei:term/string()}
                            <span class="usa-tag">{$child?count}</span>
                        </a>
                    </li>
            }
        </ul>
    </div>
};
