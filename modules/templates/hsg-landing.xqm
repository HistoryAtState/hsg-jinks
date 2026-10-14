xquery version "3.1";

(:~
 : HSG-specific landing page building blocks.
 :
 : Latest News is not authored in the landing TEI document: it is driven by the
 : carousel data package (/db/apps/carousel), the same data source the old
 : hsg-shell home page used. The section is a carousel of the topics named in
 : display-order.xml, in that order; resources/scripts/landing-carousel.js
 : wires the arrows and dots and hides them while every slide fits on screen.
 : When the carousel package is not installed the function returns the empty
 : sequence and the section simply does not appear.
 :)
module namespace hsg-landing="http://history.state.gov/ns/templates/landing";

declare variable $hsg-landing:carousel-data := "/db/apps/carousel/data";

declare function hsg-landing:news($context as map(*)) {
    let $order := doc($hsg-landing:carousel-data || "/display-order/display-order.xml")
    let $ids := $order//topic-id ! string(.)
    let $topics :=
        for $topic in collection($hsg-landing:carousel-data || "/entries")/topic[id = $ids]
        order by index-of($ids, $topic/id/string())
        return $topic
    let $count := count($topics)
    return
        if ($count = 0) then
            ()
        else
            <section class="usa-section section-news hsg-carousel"
                aria-roledescription="carousel" aria-labelledby="latest-news-heading">
                <div class="grid-container">
                    <div class="section-header">
                        <h2 id="latest-news-heading">Latest News</h2>
                        <div class="hsg-carousel__arrows">
                            <button type="button" class="hsg-carousel__arrow hsg-carousel__prev"
                                aria-controls="latest-news-slides" aria-label="Previous news item">
                                <svg class="usa-icon" aria-hidden="true" focusable="false" role="img">
                                    <use href="{hsg-landing:sprite($context)}#navigate_before"/>
                                </svg>
                            </button>
                            <button type="button" class="hsg-carousel__arrow hsg-carousel__next"
                                aria-controls="latest-news-slides" aria-label="Next news item">
                                <svg class="usa-icon" aria-hidden="true" focusable="false" role="img">
                                    <use href="{hsg-landing:sprite($context)}#navigate_next"/>
                                </svg>
                            </button>
                        </div>
                    </div>
                    <ul class="usa-card-group hsg-carousel__slides" id="latest-news-slides">
                        {
                            for $topic at $pos in $topics
                            return hsg-landing:news-card($context, $topic, $pos, $count)
                        }
                    </ul>
                    <div class="hsg-carousel__dots">
                        {
                            for $pos in 1 to $count
                            return
                                <button type="button" class="hsg-carousel__dot"
                                    aria-controls="latest-news-slides"
                                    aria-label="Go to slide {$pos}"/>
                        }
                    </div>
                </div>
            </section>
};

declare %private function hsg-landing:news-card($context as map(*), $topic as element(topic),
    $pos as xs:integer, $count as xs:integer) {
    let $href := hsg-landing:href($context, $topic/link/string())
    return
        <li class="usa-card hsg-carousel__slide" aria-roledescription="slide"
            aria-label="{$pos} of {$count}">
            <div class="usa-card__container">
                <div class="usa-card__media usa-card__media--inset">
                    <div class="usa-card__img">
                        <img src="{$topic/image/string()}" alt="{normalize-space($topic/image-description)}"/>
                    </div>
                </div>
                <div class="usa-card__header">
                    { hsg-landing:tag($topic) }
                    <h3 class="usa-card__heading">
                        <a href="{$href}">{$topic/title/node()}</a>
                    </h3>
                </div>
                <div class="usa-card__body">
                    <p>{$topic/body/node()}</p>
                </div>
                <div class="usa-card__footer">
                    { hsg-landing:date($topic) }
                    <a class="usa-button hsg-carousel__more" href="{$href}">Read More</a>
                </div>
            </div>
        </li>
};

(:~ The topic's type (publication, office-news, ...) as the card's tag. :)
declare %private function hsg-landing:tag($topic as element(topic)) {
    let $type := normalize-space($topic/type)
    return
        if ($type) then
            <span class="usa-tag">{translate($type, "-", " ")}</span>
        else
            ()
};

declare %private function hsg-landing:sprite($context as map(*)) {
    head(($context?defaults?site-root, $context?context-path)) || "/resources/images/sprite.svg"
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
