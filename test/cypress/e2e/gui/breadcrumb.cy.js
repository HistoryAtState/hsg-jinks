// Breadcrumb rendering tests.
//
// The last breadcrumb item is the current document's title, rendered from the
// teiHeader breadcrumb model in resources/odd/hsg-jinks.odd (CSS class
// tei-teiHeader3). Add cases here as breadcrumb / page markup evolves.
//
// baseUrl is http://localhost:8080/exist/apps/hsg-jinks (cypress.config.cjs),
// which matches the container's default host port mapping. If you remapped the
// host port (see "Remapping ports" in the README), override it:
// `cypress run --config baseUrl=http://localhost:<host-port>/exist/apps/hsg-jinks`.

const DOC = "historicaldocuments/frus1981-88v05/d1";
const DOC_TITLE =
    "Letter From President Reagan to Soviet General Secretary Gorbachev";

describe("document breadcrumb", () => {
    beforeEach(() => {
        cy.visit(DOC);
    });

    it("renders the document title as the last crumb", () => {
        cy.get('nav[aria-label="breadcrumb"] .tei-teiHeader3')
            .should("be.visible")
            .invoke("text")
            // TEI source carries internal newlines/indentation; collapse them.
            .then((text) => text.replace(/\s+/g, " ").trim())
            .should("eq", DOC_TITLE);
    });

    // This guard might be too aggressive as a normal title might contain "test:"
    // we can delete it at any point
    it('does not leak the "test:" debug prefix', () => {
        cy.get('nav[aria-label="breadcrumb"]')
            .invoke("text")
            .should("not.contain", "test:");
    });
});
