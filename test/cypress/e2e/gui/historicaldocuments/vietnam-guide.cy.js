// The "Guide to Sources on Vietnam, 1969-1975" TEI monograph page (OP#1301),
// reference parity with hsg-shell:
// https://history.state.gov/historicaldocuments/guide-to-sources-on-vietnam-1969-1975
//
// The content is one frozen TEI document from the other-publications data
// package, rendered as a single page; text assertions target its fixed
// headings rather than counts.

describe("the vietnam-guide page", () => {
    beforeEach(() => cy.visit("historicaldocuments/guide-to-sources-on-vietnam-1969-1975"));

    it("returns HTTP 200", () => {
        cy.request("historicaldocuments/guide-to-sources-on-vietnam-1969-1975")
            .its("status").should("eq", 200);
    });

    it("renders the monograph content", () => {
        // Phrases chosen to sit on one source line: contain.text is
        // whitespace-sensitive, and the TEI's own line wrapping splits the
        // guide's title across lines.
        cy.get("main", { timeout: 15000 })
            .should("contain.text", "The Vietnam war is one of the best documented events")
            .and("contain.text", "Office of the Historian");
    });

    it("keeps the guide's absolute production link untouched", () => {
        // The guide's single tei:ref, target https://history.state.gov with
        // no path, stays as-is (the reference's app:fix-links only rewrote
        // $app-prefixed hrefs).
        cy.get("main a[href='https://history.state.gov']", { timeout: 15000 }).should("exist");
    });

    it("has the section navigation in the left sidebar, linking here", () => {
        cy.get("aside.before ul.usa-sidenav", { timeout: 15000 }).should("exist");
        cy.get("aside.before ul.usa-sidenav a[href$='guide-to-sources-on-vietnam-1969-1975']")
            .should("exist");
    });
});
