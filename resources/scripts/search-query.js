// Keep the current search query in the header search boxes (OP#1431).
//
// The menus (templates/menu.html, templates/menu-mobile.html) fill the box
// from the request's `q` when they are rendered inline. With proxy caching
// on, nginx serves them as one cached fragment shared by every page, so the
// fragment cannot carry the query; fill the boxes on the client instead.
// Wired via config `script.custom`: a classic script at the end of <body>,
// so the block keeps its bindings out of the shared global scope.
"use strict";

{
    const q = new URLSearchParams(window.location.search).get("q");
    if (q) {
        for (const input of document.querySelectorAll('form[role="search"] input[name="q"]')) {
            input.value ||= q;
        }
    }
}
