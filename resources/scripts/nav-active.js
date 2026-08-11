// Highlight the current primary-navigation item in the USWDS header.
//
// The menu is rendered server-side from config (templates/menu.html) and does
// not know which page is active, so we resolve the active item on the client:
// find the nav link whose path is the longest prefix of the current URL, mark
// it with `usa-current`, and mark its parent category button too. Keeping this
// in app-owned JS (wired via config `script.custom`) avoids editing the
// profile-owned menu template. See OP#1283.
(function () {
    function normalize(pathname) {
        return (pathname || '').replace(/\/+$/, '') || '/';
    }

    function markActive() {
        var nav = document.querySelector('.usa-nav__primary');
        if (!nav) {
            return;
        }
        var current = normalize(window.location.pathname);
        var links = nav.querySelectorAll('a[href]');
        var best = null;
        var bestLen = -1;
        links.forEach(function (link) {
            var href = link.getAttribute('href');
            if (!href || /^(https?:)?\/\//.test(href) || href.charAt(0) === '#') {
                return;
            }
            var target;
            try {
                target = normalize(new URL(href, window.location.origin).pathname);
            } catch (err) {
                return;
            }
            // Match an exact page or a section landing that is a path prefix.
            // Ignore the root ("/...app root") so Home does not win everywhere.
            var isRoot = target === normalize(document.querySelector('.usa-logo__text') &&
                document.querySelector('.usa-logo__text').getAttribute('href') || '/');
            if (isRoot) {
                if (current === target && target.length > bestLen) {
                    best = link;
                    bestLen = target.length;
                }
                return;
            }
            if ((current === target || current.indexOf(target + '/') === 0) && target.length > bestLen) {
                best = link;
                bestLen = target.length;
            }
        });
        if (!best) {
            return;
        }
        best.classList.add('usa-current');
        var item = best.closest('.usa-nav__primary-item');
        if (item) {
            var button = item.querySelector('.usa-accordion__button');
            if (button) {
                button.classList.add('usa-current');
            }
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', markActive);
    } else {
        markActive();
    }
})();
