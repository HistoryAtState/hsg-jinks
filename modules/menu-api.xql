xquery version "3.1";

(:~
 : Menu fragment endpoint (OP#1284).
 :
 : Serves the site's primary navigation as a bare, context-independent HTML
 : fragment (no <html>/<pb-page> wrapper, and no usa-header wrapper either:
 : the stable wrapper stays in every cached page body, rendered by
 : templates/menu.html), driven by the same config.json `menu.items` the
 : inline header uses. It exists so production nginx can
 : compose the menu into aggressively-cached page bodies via an SSI
 : <!--#include virtual=".../menu" -->, cache this fragment under its own key,
 : and refresh the nav site-wide by purging only /menu -- without evicting any
 : page bodies. Because the fragment is shared across every page it must stay
 : context-independent: it deliberately omits the document-view Download
 : submenu, the editor Admin submenu, and login/language (all contextual or
 : off for this site).
 :)
module namespace menuapi = "https://history.state.gov/api/menu";

import module namespace vapi = "http://teipublisher.com/api/view" at "lib/api/view.xql";

declare namespace response = "http://exist-db.org/xquery/response";

(:~
 : Cache lifetime (seconds) for the menu fragments. Long on purpose: menu
 : changes are published by an explicit purge of /menu and /menu-mobile (see
 : doc/nginx-ssi-menu.conf), not by TTL expiry, and nginx uses the upstream
 : Cache-Control max-age as the fragment's cache validity. 30 days, matching
 : the sample nginx config's fragment TTL.
 :)
declare variable $menuapi:max-age := 2592000;

(:~
 : GET /menu -- render templates/menu-fragment.html with the shared config
 : context ($menu, $context-path, ...). Sets a public Cache-Control so nginx
 : caches the fragment under its own key; cutil:check-last-modified adds a
 : Last-Modified (and honours If-Modified-Since with a 304) whenever
 : proxy-caching is enabled, keyed on the fragment template's mtime -- which is
 : bumped on every redeploy, i.e. whenever the menu changes.
 :)
declare function menuapi:menu($request as map(*)) {
    response:set-header("Cache-Control", "public, max-age=" || $menuapi:max-age),
    menuapi:render($request, "menu-fragment")
};

(:~
 : Render one of the fragment templates with the shared config context. The
 : route declares `application/xml`, so roaster serializes these nodes with
 : the `xml` output method -- a bare fragment with **no** DOCTYPE (the `html5`
 : method used for text/html would prepend `<!DOCTYPE html>`, which is invalid
 : spliced mid-page by SSI). Returning nodes (not a serialized string) avoids
 : roaster re-escaping the markup.
 :)
declare %private function menuapi:render($request as map(*), $file as xs:string) {
    vapi:html(map:put($request, "parameters", map:merge((
        $request?parameters,
        map { "file": $file }
    ))))
};

(:~
 : GET /menu-mobile -- the same primary navigation as the collapsible mobile
 : menubar fragment (Pico `<details>` dropdowns). Same caching contract as
 : /menu so the mobile nav is edge-composed and refreshed independently too.
 :)
declare function menuapi:menu-mobile($request as map(*)) {
    response:set-header("Cache-Control", "public, max-age=" || $menuapi:max-age),
    menuapi:render($request, "menu-mobile-fragment")
};

declare function menuapi:handle-error($error) {
    vapi:handle-error($error)
};
