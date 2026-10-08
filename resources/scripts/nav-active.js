// Highlight the current primary-navigation item in the USWDS header.
//
// The menu is rendered server-side from config (templates/menu.html) and does
// not know which page is active, so we resolve the active item on the client:
// find the nav link whose path is the longest prefix of the current URL, mark
// it with `usa-current`, and mark its parent category button too. Keeping this
// in app-owned JS (wired via config `script.custom`) avoids editing the
// profile-owned menu template. See OP#1283.
//
// A classic script at the end of <body> (base10's script.custom), after the
// header it reads; the block keeps its bindings out of the shared global scope.
"use strict";

{
    const normalize = (pathname) => (pathname || "").replace(/\/+$/, "") || "/";

    const isLocal = (href) => Boolean(href) && !/^(https?:)?\/\//.test(href) && !href.startsWith("#");

    /** The normalized path a link points to, or null if it can't be parsed. */
    const pathOf = (href) => {
        try {
            return normalize(new URL(href, window.location.origin).pathname);
        } catch {
            return null;
        }
    };

    const nav = document.querySelector(".usa-nav__primary");
    if (nav) {
        const current = normalize(window.location.pathname);
        // the app root (the logo's link); it only matches itself, so Home does
        // not win on every page
        const root = normalize(document.querySelector(".usa-logo__text")?.getAttribute("href") || "/");

        let best = null;
        let bestLength = -1;
        for (const link of nav.querySelectorAll("a[href]")) {
            const href = link.getAttribute("href");
            const target = isLocal(href) ? pathOf(href) : null;
            if (target === null) {
                continue;
            }
            // an exact page, or a section landing that is a path prefix
            const matches = target === root
                ? current === target
                : current === target || current.startsWith(`${target}/`);
            if (matches && target.length > bestLength) {
                best = link;
                bestLength = target.length;
            }
        }

        if (best) {
            best.classList.add("usa-current");
            best.closest(".usa-nav__primary-item")
                ?.querySelector(".usa-accordion__button")
                ?.classList.add("usa-current");
        }
    }
}
