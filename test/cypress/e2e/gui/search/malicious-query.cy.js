// Hostile or unusual q values, ported from hsg-shell's
// search/malicious-query.cy.js (OP#1466): unsupported Lucene metacharacters
// are searched literally (200, never a 400), documented operators pass, and
// a stacked SQL statement is rejected. search.cy.js and error-pages.cy.js
// cover the UNION and tautology probes and malformed syntax (OP#1273).

describe("unsupported characters are searched literally, not rejected", () => {
    ["title:secret", "../../etc/passwd", "boost^10", "[a TO z]", "{malformed}", "100%"].forEach((q) => {
        it(`responds 200 for q="${q}"`, () => {
            cy.request({ url: "search", qs: { q }, failOnStatusCode: false }).its("status").should("eq", 200);
        });
    });
});

describe("documented operators are allowed", () => {
    it("responds 200 for a phrase with required and excluded terms", () => {
        cy.request({ url: "search", qs: { q: '"United Nations" +Washington -Berlin' }, failOnStatusCode: false })
            .its("status")
            .should("eq", 200);
    });
});

describe("a stacked SQL statement is rejected", () => {
    it("responds 400 with the invalid-search page", () => {
        cy.request({ url: "search", qs: { q: "x; DROP TABLE users" }, failOnStatusCode: false }).then((r) => {
            expect(r.status).to.eq(400);
            expect(r.body).to.contain("Invalid search query");
        });
    });
});
