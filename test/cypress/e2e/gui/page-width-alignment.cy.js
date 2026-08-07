// Page-width consistency on sticky-layout pages (hsg-jinks#1213).
//
// header, footer, and main content are all capped at the same
// --jinks-page-max-width (profile-theme-uswds's resources/sass/styles.scss),
// and .content-top (the breadcrumb/toolbar row) is boxed the same way main
// is. Four things verified here, one per finding from the alignment review
// that followed the original page-width fix:
//   1. the header logo (.usa-navbar) lines up with the nav row (.usa-nav__inner)
//   2. the breadcrumb (.content-top) lines up with the page box's left edge,
//      at any viewport width -- NOT with main. The volume landing page has a
//      populated TOC sidebar (.before), making pb-page's grid "before-fixed"
//      (see templates/layouts/hsg-content.html), which lets .content-top span
//      across that sidebar's column so the breadcrumb sits flush with the
//      header instead of stopping at the sidebar like main does.
//   3. the breadcrumb-to-H1 gap is a single spacing value, not two stacked ones
//   4. the footer sits at the bottom of the viewport on a short page, and
//      below all content (not clipped) on a long one
//
// baseUrl: see the note in document-view.cy.js.

const VOLUME = "historicaldocuments/frus1981-88v05";

function left(sel) {
    return cy.get(sel).then(($el) => $el[0].getBoundingClientRect().left);
}

describe("page-width alignment", () => {
    it("header logo lines up with the nav row", () => {
        cy.visit(VOLUME);
        left(".usa-navbar").then((navbarLeft) => {
            left(".usa-nav__inner").should((navInnerLeft) => {
                expect(navbarLeft).to.be.closeTo(navInnerLeft, 1);
            });
        });
    });

    [
        ["narrow (<1344px)", 1200],
        ["wide (>1344px)", 1728],
    ].forEach(([label, width]) => {
        it(`breadcrumb lines up with the page box's left edge at a ${label} viewport`, () => {
            cy.viewport(width, 900);
            cy.visit(VOLUME);
            // .usa-logo, not .usa-nav__inner itself: the nav row carries its
            // own 32px (2rem) padding-inline, so its content edge -- where
            // the logo sits -- is the actual page box left edge to compare
            // against.
            left(".usa-logo").then((logoLeft) => {
                left('nav[aria-label="breadcrumb"]').should((crumbLeft) => {
                    expect(crumbLeft).to.be.closeTo(logoLeft, 1);
                });
            });
        });
    });

    it("breadcrumb-to-H1 gap matches main's own padding-top (not doubled by the H1's margin)", () => {
        cy.visit(VOLUME);
        cy.get("main").then(($main) => {
            const rect = $main[0].getBoundingClientRect();
            const paddingTop = parseFloat(getComputedStyle($main[0]).paddingTop);
            const expectedH1Top = rect.top + paddingTop;
            cy.get("main h1")
                .then(($h1) => $h1[0].getBoundingClientRect().top)
                .should("be.closeTo", expectedH1Top, 1);
        });
    });

    // The page box belongs to the whole content band, sidebars included
    // (#1217). It used to sit on main alone, which only lines up on pages
    // without a sidebar -- the volume landing page above. On comp, chapter and
    // document pages .before takes the first column, and main used to centre
    // in what was left of a full-bleed grid, pushing the band up to 146px past
    // the chrome above and below it.
    [
        ["comp", `${VOLUME}/comp`],
        ["chapter", `${VOLUME}/ch1`],
        ["document", `${VOLUME}/d1`],
    ].forEach(([kind, path]) => {
        [1440, 1728].forEach((width) => {
            it(`${kind} page: content band stays inside the header's page box at ${width}px`, () => {
                cy.viewport(width, 900);
                cy.visit(path);
                cy.get(".usa-nav__inner").then(($nav) => {
                    const nav = $nav[0].getBoundingClientRect();
                    const style = getComputedStyle($nav[0]);
                    const pageLeft = nav.left + parseFloat(style.paddingLeft);
                    const pageRight = nav.right - parseFloat(style.paddingRight);
                    // sidebar starts where the header's content starts ...
                    cy.get(".before")
                        .then(($el) => $el[0].getBoundingClientRect().left)
                        .should("be.closeTo", pageLeft, 2);
                    // ... and main ends where the header's content ends
                    cy.get("main")
                        .then(($el) => $el[0].getBoundingClientRect().right)
                        .should("be.closeTo", pageRight, 2);
                });
            });
        });
    });

    it("footer is pinned to the bottom of the viewport on a short page", () => {
        // Tall enough to stay "short" relative to the viewport even with
        // the #1101 tags sidebar panel this volume now carries (OP#1101
        // tagged frus1981-88v05 specifically, to have a real fixture for
        // the tags feature's own tests) -- 1200 was tuned to this volume's
        // pre-tags-panel content height and no longer fits.
        cy.viewport(1440, 1800);
        cy.visit(VOLUME); // volume landing: short page
        cy.window().then((win) => {
            cy.get("footer.usa-footer")
                .then(($footer) => $footer[0].getBoundingClientRect().bottom)
                .should("be.closeTo", win.innerHeight, 1);
        });
    });

    it("footer lands below all content (not clipped at 100vh) on a long page", () => {
        cy.viewport(1440, 900);
        cy.visit(`${VOLUME}/ch1`); // chapter page: long page, real body text
        cy.window().then((win) => {
            cy.get("footer.usa-footer")
                .then(($footer) => $footer[0].getBoundingClientRect().bottom)
                .should("be.greaterThan", win.innerHeight);
        });
    });
});
