// The "Pre-1861 U.S. foreign relations materials" static index page (OP#1302),
// reference parity with hsg-shell:
// https://history.state.gov/historicaldocuments/pre-1861
//
// Purely static content, so exact assertions are fine here. The serial-set
// link is asserted as present even though its target 404s until OP#1303
// lands, per the section's transitional link policy.

describe("the pre-1861 page", () => {
    beforeEach(() => cy.visit("historicaldocuments/pre-1861"));

    it("returns HTTP 200", () => {
        cy.request("historicaldocuments/pre-1861").its("status").should("eq", 200);
    });

    it("shows the article heading and the Serial Set introduction", () => {
        cy.get("main h1", { timeout: 15000 })
            .should("have.text", "Pre-1861 U.S. foreign relations materials");
        cy.get("main").should("contain.text", "U.S. Congressional Serial Set, which began publication");
    });

    it("links into the Serial Set subsection", () => {
        cy.get("main ul a[href$='/historicaldocuments/pre-1861/serial-set']", { timeout: 15000 })
            .should("exist");
    });

    it("links the 1861 mention to the FRUS History monograph", () => {
        cy.get("main p a[href$='/historicaldocuments/frus-history']", { timeout: 15000 }).should("exist");
    });

    it("links the two external early-documentation sources", () => {
        cy.get("main a[href='http://memory.loc.gov/ammem/amlaw/lwsp.html']").should("exist");
        cy.get("main a[href='https://founders.archives.gov/']").should("exist");
    });

    it("has the Historical Documents nav card band", () => {
        // The section navigation is a card band below the content since
        // OP#1400, not a left sidebar.
        cy.get(".hsg-historicaldocuments-nav", { timeout: 15000 })
            .find(".hsg-historicaldocuments-nav-card").should("have.length", 8);
    });
});
