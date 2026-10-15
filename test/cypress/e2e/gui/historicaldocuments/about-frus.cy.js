// The "About the Foreign Relations Series" static article page (OP#1291),
// reference parity with hsg-shell:
// https://history.state.gov/historicaldocuments/about-frus
//
// Purely static content, so exact assertions are fine here.

describe("the about-frus page", () => {
    beforeEach(() => cy.visit("historicaldocuments/about-frus"));

    it("returns HTTP 200", () => {
        cy.request("historicaldocuments/about-frus").its("status").should("eq", 200);
    });

    it("shows the article heading and statutory basis", () => {
        cy.get("main h1", { timeout: 15000 })
            .should("have.text", "About the Foreign Relations of the United States Series");
        cy.get("main").should("contain.text", "Public Law 102-138");
    });

    it("links the FRUS series mention to the historicaldocuments landing page", () => {
        cy.get("main p a[href$='/historicaldocuments']", { timeout: 15000 }).should("exist");
    });

    it("has the Historical Documents nav card band", () => {
        // The section navigation is a card band below the content since
        // OP#1400, not a left sidebar.
        cy.get(".hsg-historicaldocuments-nav", { timeout: 15000 })
            .find(".hsg-historicaldocuments-nav-card").should("have.length", 8);
    });
});
