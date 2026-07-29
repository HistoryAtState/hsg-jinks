// Covers #1165 "Browse and read a Milestones era and its articles despite the
// retirement notice": the full browse flow across all four page types, the
// retirement notice's placement (full on the landing page, brief with a link
// back everywhere else), image resolution, and breadcrumb/prev-next
// correctness.
//
// baseUrl is http://localhost:8080/exist/apps/hsg-jinks (cypress.config.cjs).
// Override for a remapped host port, e.g.
// `cypress run --config baseUrl=http://localhost:8090/exist/apps/hsg-jinks`.

describe("Milestones section landing page", () => {
    it("shows the full retirement notice and a data-driven era selector", () => {
        cy.visit("milestones");
        cy.get("main h1").should("contain.text", "Milestones in the History of U.S. Foreign Relations");
        cy.get(".usa-alert--error").should("contain.text", "Why retire");
        // Frozen/retired publication (see CLAUDE.md "Cypress assertions on
        // data-package counts"): exactly 19 eras is expected to stay stable,
        // unlike the actively-growing HistoryAtState/* packages.
        cy.get("#milestones-era-select option").should("have.length", 20); // 19 eras + the placeholder option
        cy.get("nav[aria-label='Side navigation'] .usa-sidenav__item").should("have.length", 19);
    });

    it("links to the all-milestones listing", () => {
        cy.visit("milestones");
        cy.contains("a", "all milestones").click();
        cy.location("pathname").should("match", /milestones\/all$/);
    });
});

describe("Browsing an era from the landing page", () => {
    it("index > era (via sidebar) > article, with prev/next moving within the era", () => {
        cy.visit("milestones");
        cy.get("nav[aria-label='Side navigation']").contains("a", "1914–1920").click();
        cy.location("pathname").should("match", /milestones\/1914-1920$/);
        cy.get(".usa-alert--error").should("contain.text", "the full notice");
        cy.get("main .usa-sidenav__item, main ul li").should("exist");

        cy.contains("a", "U.S. Invasion and Occupation of Haiti").click();
        cy.location("pathname").should("match", /milestones\/1914-1920\/haiti$/);
        cy.get("main h1").should("contain.text", "U.S. Invasion and Occupation of Haiti");
        cy.get("main img").should("have.attr", "src").and("include", "static.history.state.gov/milestones/");

        // Prev/next moves within the era without returning to the TOC.
        cy.get(".usa-pagination__next-page").click();
        cy.location("pathname").should("match", /milestones\/1914-1920\/wwi$/);
        cy.get(".usa-pagination__previous-page").click();
        cy.location("pathname").should("match", /milestones\/1914-1920\/haiti$/);
        cy.get(".usa-pagination__previous-page").click();
        cy.location("pathname").should("match", /milestones\/1914-1920\/foreword$/);
    });

    it("highlights the current article in the era TOC sidebar", () => {
        cy.visit("milestones/1914-1920/haiti");
        cy.get("nav[aria-label='Side navigation'] .usa-current").should("contain.text", "U.S. Invasion and Occupation of Haiti");
    });

    it("breadcrumb moves back up through era to the section landing", () => {
        cy.visit("milestones/1914-1920/haiti");
        cy.get("nav[aria-label='breadcrumb']").contains("a", "1914–1920").click();
        cy.location("pathname").should("match", /milestones\/1914-1920$/);
        cy.get("nav[aria-label='breadcrumb']").contains("a", "Milestones").click();
        cy.location("pathname").should("match", /milestones$/);
    });
});

describe("All-milestones flat listing", () => {
    it("groups articles by era and links directly into any article across eras", () => {
        cy.visit("milestones/all");
        cy.get("main h1").should("contain.text", "All Milestones");
        cy.get(".usa-alert--error").should("contain.text", "please see");
        cy.get(".milestones-era-group").should("have.length", 19);
        cy.contains("a", "Continental Congress").click();
        cy.location("pathname").should("match", /milestones\/1776-1783\/continental-congress$/);
    });
});
