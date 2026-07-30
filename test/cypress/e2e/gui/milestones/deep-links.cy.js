// Covers #1166 "Arrive at a Milestones page via a deep link or stale
// bookmark": direct navigation to an era or article page without browsing
// via the index, correct orientation on arrival, and 404 (not 200/5xx) for
// unresolvable ids -- including the id()-whitespace-tokenization edge cases
// milapi:view-section's exact-match guard exists to close.

describe("Direct arrival at an era or article page", () => {
    it("lands fully oriented on a valid era, with no prior browsing", () => {
        cy.visit("milestones/1914-1920");
        cy.get("nav[aria-label='breadcrumb']").should("contain.text", "1914–1920");
        cy.get(".usa-alert--error").should("exist");
        cy.contains("a", "U.S. Invasion and Occupation of Haiti").should("exist");
    });

    it("lands fully oriented on a valid article, with no prior browsing", () => {
        cy.visit("milestones/1914-1920/haiti");
        cy.get("nav[aria-label='breadcrumb']").should("contain.text", "U.S. Invasion and Occupation of Haiti");
        cy.get("nav[aria-label='Side navigation'] .usa-current").should("exist");
        cy.get(".usa-alert--error").should("exist");
    });

    it("the foreword front-matter div is reachable as an ordinary deep link", () => {
        cy.visit("milestones/1914-1920/foreword");
        cy.get("main h1").should("contain.text", "World War One and Wilsonian Diplomacy");
        cy.get("nav[aria-label='Side navigation'] .usa-current").should("exist");
    });
});

describe("404 handling (not 200, not 5xx)", () => {
    it("preserves every real URL form", () => {
        const urls = [
            "milestones",
            "milestones/all",
            "milestones/1914-1920",
            "milestones/1914-1920/foreword",
            "milestones/1914-1920/haiti",
        ];
        urls.forEach((url) => {
            cy.request(url).its("status").should("eq", 200);
        });
    });

    it("404s an unknown era id", () => {
        cy.request({ url: "milestones/1700-1749", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
    });

    it("404s a valid era with an unknown article id", () => {
        cy.request({ url: "milestones/1914-1920/nonexistent-article", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
    });

    it("404s an id carrying encoded whitespace rather than silently resolving to a different article", () => {
        // The id()-whitespace-tokenization trap #518/#1166 both flag: a
        // trailing encoded space, or several ids in one path segment, must
        // not silently resolve to a real article.
        cy.request({ url: "milestones/1914-1920/haiti%20", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
        cy.request({ url: "milestones/1914-1920/haiti%20wwi", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
    });
});
