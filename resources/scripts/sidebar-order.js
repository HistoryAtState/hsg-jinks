/*
 * sticky-layout: below the desktop breakpoint the sidebars sit below the
 * content (layout.css), as USWDS places side navigation on mobile. Grid
 * areas alone would only move them visually -- reading and focus order would
 * still put them first, failing WCAG 1.3.2 Meaningful Sequence and 2.4.3
 * Focus Order. So the .before/.after elements are moved in the DOM as well:
 * after main on narrow screens, back to their original place on desktop.
 * Grid areas are assigned by name, so the desktop layout does not depend on
 * DOM order.
 *
 * The breakpoint matches layout.css (and the hidden-mobile class).
 */
(function () {
    const layout = document.querySelector("pb-page.sticky-layout");
    const main = layout && layout.querySelector(":scope > main");
    if (!main) {
        return;
    }
    const sidebars = Array.from(layout.querySelectorAll(":scope > .before, :scope > .after"));
    // Remember each sidebar's original place with an empty marker node
    const markers = sidebars.map((sidebar) => {
        const marker = document.createComment(`${sidebar.classList[0]} sidebar`);
        sidebar.before(marker);
        return marker;
    });

    const narrow = window.matchMedia("(max-width: 1023px)");

    function place() {
        if (narrow.matches) {
            main.after(...sidebars);
        } else {
            sidebars.forEach((sidebar, i) => markers[i].after(sidebar));
        }
    }

    place();
    narrow.addEventListener("change", place);
})();
