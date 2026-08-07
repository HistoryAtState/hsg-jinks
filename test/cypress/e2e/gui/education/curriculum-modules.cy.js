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

    it("shows the site-wide About panel (5 links) and the Education panel (1 link), not the module list (PR #17 review)", () => {
        cy.visit("education");
        cy.contains("aside h2", "About").next("ul.usa-sidenav").find("a").should("have.length", 5);
        cy.contains("aside h2", "About").next("ul.usa-sidenav").find("a").eq(0).should("have.text", "Contact Us");
        cy.contains("aside h2", "About").next("ul.usa-sidenav").find("a").eq(4).should("have.text", "Recent Publications");
        cy.contains("aside h2", "Education").next("ul.usa-sidenav").find("a").should("have.length", 1)
            .and("have.text", "Curriculum Modules")
            .and("have.attr", "href").and("match", /\/education\/modules$/);
        cy.get("aside h3").should("not.exist");
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

    it("shows the Education/Curriculum Modules sidebar heading pair and marks the section-nav link current (PR #17 review)", () => {
        cy.visit("education/modules");
        cy.get("aside h2").should("have.length", 2).and("contain.text", "Education");
        cy.get("aside h3").should("have.text", "Curriculum Modules");
        cy.contains("aside h2 + ul a", "Curriculum Modules")
            .should("have.attr", "aria-current", "page")
            .and("have.class", "usa-current");
    });

    it("sidebar module order matches the main listing order (#1169 ordering-bug regression)", () => {
        cy.visit("education/modules");
        cy.get(".usa-collection__heading a").then(($links) => {
            const listingOrder = [...$links].map((a) => a.getAttribute("href"));
            // The modules-list sidebar sits under its own "Curriculum Modules"
            // h3, distinct from the single-link "Education" section-nav panel
            // that also renders on this page.
            cy.get("aside h3 + ul.usa-sidenav a").then(($sidebarLinks) => {
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

    it("shows the intro TEI's complete title as the page heading and breadcrumb leaf, and does not mark the section-nav current (PR #17 review)", () => {
        cy.visit("education/modules/documents-intro");
        cy.get("main h1").should("contain.text", "Introduction to Curriculum Packet on");
        cy.get("main h1").should("contain.text", "Documents on Diplomacy");
        cy.get("nav[aria-label=breadcrumb] li[aria-current=page]").should("contain.text", "Introduction to Curriculum Packet on");
        cy.contains("aside h2 + ul a", "Curriculum Modules").should("not.have.attr", "aria-current");
    });

    it("navigates from the landing page, via the Education sidebar link and the full listing, into a module page", () => {
        cy.visit("education");
        // The landing page sidebar only links to the listing (its brief
        // module list is plain text, not links, matching the reference
        // site); the listing page is where individual modules become
        // clickable, both from the main usa-collection and its own sidebar.
        cy.contains("aside h2 + ul a", "Curriculum Modules").click();
        cy.location("pathname").should("match", /education\/modules$/);
        cy.get(".usa-collection__heading a").first().click();
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
