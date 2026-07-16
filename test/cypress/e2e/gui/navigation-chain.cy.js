// Covers the user story "As a User I want to be able to navigate from the
// volume landing page to a document detail view" -- click-through from the
// volume landing page down to a document, entirely via rendered links.

const VOLUME = "historicaldocuments/frus1981-88v05";

describe("navigate from volume landing to a document", () => {
    it("clicks through landing -> compilation -> chapter -> document", () => {
        cy.visit(VOLUME);
        cy.contains("a", "Soviet Union, March 1985").click();
        cy.location("pathname").should("match", new RegExp(`${VOLUME}/comp$`));

        cy.contains("a", "Gorbachev").click();
        cy.location("pathname").should("match", new RegExp(`${VOLUME}/ch1$`));

        cy.get("main a[href$='d1']").first().click();
        cy.location("pathname").should("match", new RegExp(`${VOLUME}/d1$`));
        cy.get("main").should("contain.text", "Reagan");
    });
});
