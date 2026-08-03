// Covers OP#1103 "Render HSG developer" -- the two static developer-facing
// documentation pages (no TEI document, no data collection): the landing
// page and the Ebook Catalog (OPDS) API reference, plus the URL-preservation
// and 404 acceptance criteria from OP#1190.
//
// baseUrl comes from CYPRESS_BASE_URL (this worktree's .env) -- see
// cypress.config.cjs and README "Parallel worktrees".

describe("Developer Resources landing page", () => {
    it("renders the overview and links to the Ebook Catalog API page", () => {
        cy.visit("developer");
        cy.get("main h1").should("contain.text", "Developer Resources");
        cy.contains("main a", "Office of the Historian Ebook Catalog API")
            .should("have.attr", "href")
            .and("match", /\/developer\/catalog$/);
    });

    it("lists the external Related Links (eXist-db, TEI, GitHub)", () => {
        cy.visit("developer");
        cy.contains(".usa-icon-list a", "eXist-db").should("have.attr", "href", "https://exist-db.org/");
        cy.contains(".usa-icon-list a", "Text Encoding Initiative (TEI)").should("have.attr", "href", "http://www.tei-c.org");
        cy.contains(".usa-icon-list a", "Project on GitHub").should("have.attr", "href", "https://github.com/HistoryAtState");
    });

    it("following the in-page link lands on the catalog page", () => {
        cy.visit("developer");
        cy.contains("main a", "Office of the Historian Ebook Catalog API").click();
        cy.location("pathname").should("match", /\/developer\/catalog$/);
        cy.get("main h1").should("contain.text", "Ebook Catalog API");
    });
});

describe("Ebook Catalog API documentation page", () => {
    it("documents the entry point and the three key sub-resource URIs", () => {
        cy.visit("developer/catalog");
        cy.get("main h1").should("contain.text", "Office of the Historian Ebook Catalog API");
        cy.contains("pre", "GET https://history.state.gov/api/v1/catalog").should("exist");
        cy.contains("pre", "GET https://history.state.gov/api/v1/catalog/all").should("exist");
        cy.contains("pre", "GET https://history.state.gov/api/v1/catalog/recent").should("exist");
        cy.contains("pre", "GET https://history.state.gov/api/v1/catalog/browse").should("exist");
    });

    it("breadcrumb links back to the Developer Resources landing page", () => {
        cy.visit("developer/catalog");
        cy.get("nav[aria-label='breadcrumb']").first().within(() => {
            cy.contains("a", "Developer Resources").click();
        });
        cy.location("pathname").should("match", /\/developer$/);
    });
});

describe("URL preservation and 404 handling (OP#1190 acceptance criteria)", () => {
    it("/developer and /developer/catalog resolve at their exact hsg-shell URLs", () => {
        cy.request("developer").its("status").should("eq", 200);
        cy.request("developer/catalog").its("status").should("eq", 200);
    });

    it("any other path segment under /developer returns 404", () => {
        cy.request({ url: "developer/no-such-page", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
    });
});
