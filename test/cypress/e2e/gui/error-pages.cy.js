// Site-wide error pages (OP#1309) and the malformed-query guard (OP#1273):
// friendly themed pages with correct HTTP status, replacing the generic
// "Ooops" diagnostics page (which hardcoded HTTP 200) for the 404/400
// classes. Status mapping is centralized in modules/hsg-errors.xqm; every
// section's x-error-handler and the jinks catch-all route delegate to it.

describe("404 not found", () => {
    it("unrouted path serves the friendly 404 page with status 404", () => {
        cy.request({ url: "asdfg", failOnStatusCode: false }).then((r) => {
            expect(r.status).to.eq(404);
            expect(r.body).to.contain("Page not found");
        });
    });

    it("unknown volume id 404s through the section handler", () => {
        cy.request({ url: "historicaldocuments/no-such-volume", failOnStatusCode: false })
            .its("status").should("eq", 404);
    });

    it("offers home and search links", () => {
        cy.visit({ url: "asdfg", failOnStatusCode: false });
        cy.get("main a[href$='/']", { timeout: 15000 }).should("exist");
        cy.get("main a[href$='/search']").should("exist");
    });
});

describe("400 invalid search query", () => {
    it("malformed Lucene syntax serves the invalid-search page with status 400", () => {
        cy.request({ url: 'search?q=%22unbalanced', failOnStatusCode: false }).then((r) => {
            expect(r.status).to.eq(400);
            expect(r.body).to.contain("Invalid search query");
        });
    });

    it("links to the search form and the search tips", () => {
        cy.visit({ url: 'search?q=%22unbalanced', failOnStatusCode: false });
        cy.get("main a[href$='/search']", { timeout: 15000 }).should("exist");
        cy.get("main a[href$='/search/tips']").should("exist");
    });

    it("does not reject a legitimate query", () => {
        cy.request("search?q=Gorbachev").its("status").should("eq", 200);
    });

    it("still rejects query-guard payloads with 400", () => {
        cy.request({ url: "search?q=1%20OR%201%3D1", failOnStatusCode: false })
            .its("status").should("eq", 400);
    });
});
