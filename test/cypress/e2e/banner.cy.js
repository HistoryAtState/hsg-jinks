// The government banner must follow the app's page width
// (--jinks-page-max-width) like the header and footer, not USWDS's
// compile-time $theme-banner-max-width (issue #43). The demo app enables the
// banner and sets a page width that differs from the USWDS default.
//
// Compare what is visible, not box edges: USWDS pads the banner
// asymmetrically (the header row has no right padding, and the guidance icons
// hang into the left margin so the guidance text lines up with the banner
// text), so its boxes don't share the nav row's padding.
const left = (sel) => cy.get(sel).then(($el) => $el[0].getBoundingClientRect().left);

describe("government banner", () => {
    beforeEach(() => {
        // Wider than the page box, so a fixed-width banner would show.
        cy.viewport(1728, 900);
        cy.visit("index.html");
    });

    it("lines its flag up with the logo", () => {
        left(".usa-logo").then((logoLeft) => {
            left(".usa-banner__header-flag").should("be.closeTo", logoLeft, 1);
        });
    });

    it("keeps the expanded guidance in line with the banner text, inside the page box", () => {
        cy.get(".usa-banner__button").click();
        cy.get(".usa-banner__content").should("be.visible");
        left(".usa-banner__header-text").then((textLeft) => {
            left(".usa-banner__guidance .usa-media-block__body").should("be.closeTo", textLeft, 1);
        });
        cy.get(".usa-header--extended .usa-nav__inner").then(($nav) => {
            const nav = $nav[0].getBoundingClientRect();
            const style = getComputedStyle($nav[0]);
            const pageRight = nav.right - parseFloat(style.paddingRight);
            cy.get(".usa-banner__guidance")
                .last()
                .should(($g) => {
                    expect($g[0].getBoundingClientRect().right).to.be.at.most(pageRight + 1);
                });
        });
    });
});
