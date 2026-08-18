// The "Citing the Foreign Relations series" static article page (OP#1299),
// reference parity with hsg-shell:
// https://history.state.gov/historicaldocuments/citing-frus
//
// Purely static content, so exact assertions are fine here.

describe("the citing-frus page", () => {
    beforeEach(() => cy.visit("historicaldocuments/citing-frus"));

    it("returns HTTP 200", () => {
        cy.request("historicaldocuments/citing-frus").its("status").should("eq", 200);
    });

    it("shows the article heading and the sample citation", () => {
        cy.get("main h1", { timeout: 15000 })
            .should("have.text", "Citing the Foreign Relations series");
        cy.get("main").should("contain.text", "Daniel J. Lawler and Erin R. Mahan");
    });

    it("links the canonic-URL example to the document page", () => {
        cy.get("main blockquote a[href$='/historicaldocuments/frus1969-76v19p1/d75']", { timeout: 15000 })
            .should("contain.text", "history.state.gov/historicaldocuments/frus1969-76v19p1/d75");
    });

    it("links the series-title discussion to the FRUS History terms section", () => {
        cy.get("main p a[href$='/historicaldocuments/frus-history/terms']", { timeout: 15000 }).should("exist");
    });

    it("has the section navigation in the left sidebar", () => {
        cy.get("aside.before ul.usa-sidenav", { timeout: 15000 }).should("exist");
    });
});
