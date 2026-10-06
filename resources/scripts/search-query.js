// Keep the current search query in the header search boxes (OP#1431).
//
// The menus (templates/menu.html, templates/menu-mobile.html) fill the box
// from the request's `q` when they are rendered inline. With proxy caching
// on, nginx serves them as one cached fragment shared by every page, so the
// fragment cannot carry the query; fill the boxes on the client instead.
// Wired via config `script.custom`.
(function () {
    function fill() {
        var q = new URLSearchParams(window.location.search).get('q');
        if (!q) {
            return;
        }
        document.querySelectorAll('form[role="search"] input[name="q"]').forEach(function (input) {
            if (!input.value) {
                input.value = q;
            }
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', fill);
    } else {
        fill();
    }
})();
