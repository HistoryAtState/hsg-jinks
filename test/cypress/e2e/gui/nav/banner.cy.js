// Official U.S. government banner (OP#1050): the standard USWDS banner,
// wired as an opt-in via theme.banner in config.json (markup from the
// theme-sourced templates/banner.html, included inside the .usa-header
// root; single-root constraint documented in templates/menu.html).
// The flag ships as false, so the banner must NOT render by default.

describe("government banner (disabled by default)", () => {
    it("does not render on the landing page", () => {
        cy.visit("index.html");
        cy.get(".usa-header", { timeout: 15000 }).should("exist");
        cy.get(".usa-banner").should("not.exist");
    });

    it("does not render on content pages either", () => {
        cy.visit("historicaldocuments/citing-frus");
        cy.get(".usa-header", { timeout: 15000 }).should("exist");
        cy.get(".usa-banner").should("not.exist");
    });
});
