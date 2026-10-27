// Country and archives articles have one h1, the article title from the
// template; the TEI section heads sit one level below it (OP#1489).

const headings = () =>
    cy.get("main .usa-prose").find("h1, h2, h3").then(($hs) =>
        Cypress._.map($hs, (h) => [h.tagName.toLowerCase(), h.textContent.replace(/\s+/g, " ").trim()]));

describe("country article headings", () => {
    it("an archives article has one h1 and its sections as h2", () => {
        cy.visit("countries/archives/afghanistan");
        cy.get("main h1").should("have.length", 1)
            .and("have.text", "World Wide Diplomatic Archives Index: Afghanistan");
        headings().should("deep.equal", [
            ["h1", "World Wide Diplomatic Archives Index: Afghanistan"],
            ["h2", "Legislation"],
            ["h2", "Location"],
            ["h2", "Procedures"],
            ["h2", "Website"],
        ]);
    });

    it("a country article has one h1, its sections as h2 and their subsections as h3", () => {
        cy.visit("countries/japan");
        cy.get("main h1").should("have.length", 1).and("contain.text", "Japan");
        cy.contains("main h2", "Summary").should("exist");
        cy.contains("main h2", "Recognition").should("exist");
        cy.contains("main h3", "Mutual Recognition, 1854.").should("exist");
    });
});
