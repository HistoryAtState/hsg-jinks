// Document view: title renders as an <h1>.
//
// Documents carry no <head> in the body (only a <?frusGen document-heading...?>
// placeholder PI), so the title is synthesized from the document's own
// teiHeader via the "document-view" ODD mode (resources/odd/hsg-jinks.odd),
// selected in templates/pages/volume-interior.html for
// frus-division-type='document'.

const DOC = "historicaldocuments/frus1981-88v05/d1";
const DOC_TITLE =
    "Letter From President Reagan to Soviet General Secretary Gorbachev";

describe("document view", () => {
    it("renders the document's title as the page's h1", () => {
        cy.visit(DOC);
        cy.get("main h1")
            .should("be.visible")
            .invoke("text")
            .then((text) => text.replace(/\s+/g, " ").trim())
            .should("eq", DOC_TITLE);
    });

    it("renders exactly one h1", () => {
        cy.visit(DOC);
        cy.get("main h1").should("have.length", 1);
    });
});
