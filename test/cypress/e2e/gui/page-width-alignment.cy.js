// Page-width consistency on sticky-layout pages (hsg-jinks#1213).
//
// header, footer, and main content are all capped at the same
// --jinks-page-max-width (profile-theme-uswds's resources/sass/styles.scss),
// and .content-top (the breadcrumb/toolbar row) is boxed the same way main
// is. Four things verified here, one per finding from the alignment review
// that followed the original page-width fix:
//   1. the header logo (.usa-navbar) lines up with the nav row (.usa-nav__inner)
//   2. the breadcrumb (.content-top) lines up with main, at any viewport width
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
        it(`breadcrumb lines up with main content at a ${label} viewport`, () => {
            cy.viewport(width, 900);
            cy.visit(VOLUME);
            left('nav[aria-label="breadcrumb"]').then((crumbLeft) => {
                left("main").should((mainLeft) => {
                    expect(crumbLeft).to.be.closeTo(mainLeft, 1);
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

    it("footer is pinned to the bottom of the viewport on a short page", () => {
        cy.viewport(1440, 1200);
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
