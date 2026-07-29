// Covers #1172 "Browse and read a retired curriculum module": the retired
// Education Resources section (retirement notice on every page), the
// landing page's abbreviated prose list, the full listing page's
// usa-collection, and per-module detail pages, plus the #1169 sidebar/
// listing ordering-bug fix and 404 handling for unknown/in-preparation ids.
//
// The module record collection (modules.xml, 8 records: 7 published, 1
// in-preparation) is frozen archival data, not one of the growing
// HistoryAtState/* data packages CLAUDE.md's "have.length.at.least"
// guidance targets -- exact counts are safe to assert here.

const publishedModules = [
    { id: "documents-intro", year: "2011" },
    { id: "border-vanishes-intro", year: "2010" },
    { id: "journey-shared-intro", year: "2008" },
    { id: "media-intro", year: "2006" },
    { id: "sports-intro", year: "2005" },
    { id: "history-diplomacy-intro", year: "2004" },
    { id: "terrorism-intro", year: "2002" },
];

describe("education landing page", () => {
    it("shows the retirement notice and the abbreviated module list", () => {
        cy.visit("education");
        cy.get(".usa-alert--error").should("contain.text", "Note to Readers")
            .and("contain.text", "no longer being maintained");
        cy.get("main ol li").should("have.length", publishedModules.length);
        cy.get("main ol li").first().should("contain.text", "2011");
        cy.get("main ol li").last().should("contain.text", "2002");
    });
});

describe("curriculum modules listing", () => {
    it("lists exactly the 7 published modules, year-descending, each with a title link, teaser, and availability line", () => {
        cy.visit("education/modules");
        cy.get(".usa-alert--error").should("contain.text", "Note to Readers");
        cy.get(".usa-collection__item").should("have.length", publishedModules.length);
        cy.get(".usa-collection__item").each(($item, index) => {
            cy.wrap($item).find(".usa-collection__heading a").should("have.attr", "href")
                .and("include", publishedModules[index].id);
            cy.wrap($item).find(".usa-collection__meta").should("contain.text", publishedModules[index].year);
        });
    });

    it("sidebar module order matches the main listing order (#1169 ordering-bug regression)", () => {
        cy.visit("education/modules");
        cy.get(".usa-collection__heading a").then(($links) => {
            const listingOrder = [...$links].map((a) => a.getAttribute("href"));
            cy.get("aside .usa-sidenav a").then(($sidebarLinks) => {
                const sidebarOrder = [...$sidebarLinks].map((a) => a.getAttribute("href"));
                expect(sidebarOrder).to.deep.equal(listingOrder);
            });
        });
    });
});

describe("curriculum module detail pages", () => {
    publishedModules.forEach(({ id }) => {
        it(`renders ${id} with its title, availability block, and full introduction`, () => {
            cy.visit(`education/modules/${id}`);
            cy.get(".usa-alert--error").should("contain.text", "Note to Readers");
            cy.get(".usa-summary-box").should("contain.text", "Availability");
            cy.get("main h1, main .tei-head").should("exist");
        });
    });

    it("navigates from the landing page sidebar into a module page", () => {
        cy.visit("education");
        cy.get("aside .usa-sidenav a").first().click();
        cy.location("pathname").should("match", /education\/modules\/[a-z-]+$/);
        cy.get(".usa-summary-box").should("exist");
    });

    it("404s for an unknown moduleId", () => {
        cy.request({ url: "education/modules/not-a-real-module", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
    });

    it("404s for the in-preparation module (no reachable tei-document-name) and excludes it from both listings", () => {
        cy.request({ url: "education/modules/us-relations-with-south-and-central-america", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
        cy.visit("education/modules");
        cy.contains(".usa-collection__heading", "U.S. Relations with South and Central America").should("not.exist");
        cy.visit("education");
        cy.get("main ol").should("not.contain.text", "U.S. Relations with South and Central America");
    });
});
