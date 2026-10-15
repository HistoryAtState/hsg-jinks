// The "Other Electronic Resources" static resource-list page (OP#1300),
// reference parity with hsg-shell:
// https://history.state.gov/historicaldocuments/other-electronic-resources
//
// Purely static content, so exact assertions are fine here.

describe("the other-electronic-resources page", () => {
    beforeEach(() => cy.visit("historicaldocuments/other-electronic-resources"));

    it("returns HTTP 200", () => {
        cy.request("historicaldocuments/other-electronic-resources").its("status").should("eq", 200);
    });

    it("shows the article heading and introduction", () => {
        cy.get("main h1", { timeout: 15000 })
            .should("have.text", "Electronic Resources for U.S. Foreign Relations");
        cy.get("main").should("contain.text", "primary source materials relating to U.S. foreign relations");
    });

    it("lists all eight resource categories", () => {
        cy.get("main h2").should("have.length", 8);
        cy.get("main h2").first().should("have.text", "Declassified Document Collections");
        cy.get("main h2").last().should("have.text", "Pre-1861 Resources");
    });

    it("links the four declassified document collections", () => {
        cy.get("main h2").first().next("ul").find("li a").should("have.length", 4);
    });

    it("links the Pre-1861 Resources entry to the pre-1861 page", () => {
        cy.get("main ul a[href$='/historicaldocuments/pre-1861']", { timeout: 15000 }).should("exist");
    });

    it("has the Historical Documents nav card band", () => {
        // The section navigation is a card band below the content since
        // OP#1400, not a left sidebar.
        cy.get(".hsg-historicaldocuments-nav", { timeout: 15000 })
            .find(".hsg-historicaldocuments-nav-card").should("have.length", 8);
    });
});
