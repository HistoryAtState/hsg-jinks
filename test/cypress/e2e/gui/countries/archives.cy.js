// Countries landing country picker and World Wide Diplomatic Archives Index
// headings, ported from hsg-shell's countries/landing.cy.js and
// countries/archives/*.cy.js (OP#1466). countries.cy.js covers the
// Countries landing heading and the archives article for Japan.

const shouldBeHeaded = (expected) =>
    cy.get("main h1").filter(":visible").first().should(($h1) => {
        expect($h1.text().replace(/\s+/g, " ").trim()).to.eq(expected);
    });

describe("countries landing", () => {
    // A USWDS combo box: its script hands the select's id to the text input
    // it adds in front of the select.
    it("offers a select input for choosing a country", () => {
        cy.visit("countries");
        cy.get("main .usa-combo-box input#country-select").should("be.visible");
        // Data-derived count (the countries package can grow) -- lower bound only.
        cy.get("main .usa-combo-box select option[value*='/countries/']").should("have.length.at.least", 200);
    });

    it("goes to the country chosen", () => {
        cy.visit("countries");
        cy.get("main input#country-select").type("Afghan");
        cy.contains("main .usa-combo-box__list-option", "Afghanistan").click();
        cy.location("pathname").should("match", /\/countries\/afghanistan$/);
    });
});

describe("archives index headings", () => {
    [
        ["countries/archives", "World Wide Diplomatic Archives Index"],
        ["countries/archives/all", "All Countries"],
        ["countries/archives/afghanistan", "World Wide Diplomatic Archives Index: Afghanistan"],
        ["countries/archives/bahamas", "World Wide Diplomatic Archives Index: Bahamas"],
        ["countries/archives/zimbabwe", "World Wide Diplomatic Archives Index: Zimbabwe"],
    ].forEach(([path, expected]) => {
        it(`/${path} is headed "${expected}"`, () => {
            cy.visit(path);
            shouldBeHeaded(expected);
        });
    });
});
