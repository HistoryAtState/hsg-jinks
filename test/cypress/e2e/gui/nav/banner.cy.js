// Official U.S. government banner (OP#1050): the standard USWDS banner,
// enabled via theme.banner in config.json, markup from the theme-sourced
// templates/banner.html included inside the .usa-header root (the
// single-root constraint documented in templates/menu.html).

describe("government banner", () => {
    it("renders above the navbar on the landing page", () => {
        cy.visit("index.html");
        cy.get(".usa-banner .usa-banner__header-text", { timeout: 15000 })
            .should("contain.text", "An official website of the United States government");
        cy.get(".usa-banner").then(($b) => {
            cy.get(".usa-navbar").then(($n) => {
                expect($b[0].getBoundingClientRect().top).to.be.lessThan($n[0].getBoundingClientRect().top);
            });
        });
    });

    it("renders on content pages too", () => {
        cy.visit("historicaldocuments/citing-frus");
        cy.get(".usa-banner", { timeout: 15000 }).should("exist");
    });

    it("expands the guidance accordion", () => {
        cy.visit("index.html");
        cy.get(".usa-banner__button", { timeout: 15000 }).click();
        cy.get("#gov-banner-default").should("be.visible")
            .and("contain.text", "Official websites use .gov");
    });
});
