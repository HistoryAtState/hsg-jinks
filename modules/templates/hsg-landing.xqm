xquery version "3.1";

(:~
 : HSG-specific landing page building blocks.
 :
 : Latest News is not authored in the landing TEI document: it is driven by the
 : carousel data package (/db/apps/carousel), the same data source the old
 : hsg-shell home page used. The section renders the first three topics named
 : in display-order.xml. When the carousel package is not installed the
 : function returns the empty sequence and the section simply does not appear.
 :)
module namespace hsg-landing="http://history.state.gov/ns/templates/landing";

declare variable $hsg-landing:carousel-data := "/db/apps/carousel/data";

declare function hsg-landing:news($context as map(*)) {
    let $order := doc($hsg-landing:carousel-data || "/display-order/display-order.xml")
    let $ids := subsequence($order//topic-id, 1, 3)
    let $topics :=
        for $topic in collection($hsg-landing:carousel-data || "/entries")/topic[id = $ids]
        order by index-of($ids ! string(.), $topic/id/string())
        return $topic
    return
        if (empty($topics)) then
            ()
        else
            <section class="usa-section section-news">
                <div class="grid-container">
                    <div class="section-header">
                        <h2>Latest News</h2>
                    </div>
                    <ul class="usa-card-group">
                        { $topics ! hsg-landing:news-card($context, .) }
                    </ul>
                </div>
            </section>
};

declare %private function hsg-landing:news-card($context as map(*), $topic as element(topic)) {
    let $href := hsg-landing:href($context, $topic/link/string())
    return
        <li class="usa-card tablet:grid-col-4">
            <div class="usa-card__container">
                <div class="usa-card__media">
                    <div class="usa-card__img">
                        <img src="{$topic/image/string()}" alt="{normalize-space($topic/image-description)}"/>
                    </div>
                </div>
                <div class="usa-card__header">
                    <h3 class="usa-card__heading">
                        <a href="{$href}">{$topic/title/node()}</a>
                    </h3>
                </div>
                <div class="usa-card__body">
                    <p>{$topic/body/node()}</p>
                </div>
                <div class="usa-card__footer">
                    { hsg-landing:date($topic) }
                    <a class="usa-button usa-button--outline" href="{$href}">Read More</a>
                </div>
            </div>
        </li>
};

(:~ Prefix app-internal links (leading slash) with the site root or, in a
 : development deployment, the app's context path — same convention as the
 : generated menu. External URLs pass through unchanged. :)
declare %private function hsg-landing:href($context as map(*), $link as xs:string) {
    if (starts-with($link, "/")) then
        head(($context?defaults?site-root, $context?context-path)) || $link
    else
        $link
};

declare %private function hsg-landing:date($topic as element(topic)) {
    let $datetime := $topic/created-datetime[. castable as xs:dateTime]
    return
        if ($datetime) then
            <span class="card-date">{format-dateTime(xs:dateTime($datetime), "[MNn] [D], [Y]")}</span>
        else
            ()
};
