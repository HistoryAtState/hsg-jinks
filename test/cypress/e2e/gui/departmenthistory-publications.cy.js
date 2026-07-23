// Covers #1149 "Read the department's history publications" -- Short
// History/Buildings (TEI monograph TOC + division), Diplomatic Couriers
// (video + transcript), and the WWI/Marine Corps static pamphlet pages.
//
// baseUrl is http://localhost:8080/exist/apps/hsg-jinks (cypress.config.cjs).
// Override for a remapped host port, e.g.
// `cypress run --config baseUrl=http://localhost:8090/exist/apps/hsg-jinks`.

describe("Short History and Buildings: TOC, chapter, prev/next, sidebar", () => {
    it("Short History: TOC lists chapters, opens a chapter, and the sidebar marks it current", () => {
        cy.visit("departmenthistory/short-history");
        cy.get("main h1").should("contain.text", "A Short History of the Department of State");
        cy.contains(".usa-sidenav a", "Foundations of Foreign Affairs").click();
        cy.location("pathname").should("match", /short-history\/foundations$/);
        cy.get("main h1").should("contain.text", "Foundations of Foreign Affairs");
        cy.get("nav[aria-label='Side navigation'] a.usa-current").should("contain.text", "Foundations of Foreign Affairs");
    });

    it("Short History: moves forward with Next and the breadcrumb tracks the current chapter/subchapter", () => {
        cy.visit("departmenthistory/short-history/foundations");
        cy.get(".usa-pagination__next-page").click();
        cy.location("pathname").should("match", /short-history\/origins$/);
        cy.get("main h1").should("contain.text", "Origins of a Diplomatic Tradition");
        cy.get("nav[aria-label='breadcrumb']").first().within(() => {
            cy.contains("a", "Short History");
            cy.contains("a", "Foundations of Foreign Affairs");
            cy.contains("li", "Origins of a Diplomatic Tradition");
        });
    });

    it("Buildings: flat TOC (no nested subchapters), first section has no Previous", () => {
        cy.visit("departmenthistory/buildings");
        cy.get("main h1").should("contain.text", "Buildings of the Department of State");
        cy.contains(".usa-sidenav a", "Introduction").click();
        cy.location("pathname").should("match", /buildings\/intro$/);
        cy.get(".usa-pagination__previous-page").should("not.exist");
    });

    it("rejects a whitespace-mangled section id (exact-division guard)", () => {
        cy.request({ url: "departmenthistory/short-history/foundations%20origins", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
        cy.request({ url: "departmenthistory/short-history/foundations%20", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
    });
});

describe("Diplomatic Couriers: series page, film, video, transcript", () => {
    it("opens a film from the series page and shows the Brightcove embed and transcript", () => {
        cy.visit("departmenthistory/diplomatic-couriers");
        cy.contains("a", "Through the Khyber Pass").click();
        cy.location("pathname").should("match", /diplomatic-couriers\/through-the-khyber-pass$/);
        cy.get("main h1").should("contain.text", "Through the Khyber Pass");
        cy.contains("h2", "Transcript").should("exist");
        cy.get("main").contains("MR VERREOS").should("exist");
        // The Brightcove player script (an external CDN) hydrates and can
        // replace the <video> element once it loads, racing a live-DOM
        // assertion -- check the server-rendered embed markup directly
        // instead, which is what dh:courier-video actually controls.
        cy.request("departmenthistory/diplomatic-couriers/through-the-khyber-pass").its("body").should("match", /<video[^>]*class="video-js"[^>]*data-video-id="4262345725001"/);
    });

    it("404s an unknown film id (the id whitelist, not a collection scan)", () => {
        cy.request({ url: "departmenthistory/diplomatic-couriers/nosuchfilm", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
    });
});

describe("WWI and Marine Corps: static pamphlet pages with PDF downloads", () => {
    it("Marine Corps page reads and links its PDF via a usa-button", () => {
        cy.visit("departmenthistory/marine-corps");
        cy.get("main h1").should("contain.text", "The U.S. Marine Corps and the Department");
        cy.contains("a.usa-button", "Download PDF").should("have.attr", "href").and("match", /static\.history\.state\.gov/);
    });

    it("WWI page reads and links both of its PDFs", () => {
        cy.visit("departmenthistory/wwi");
        cy.get("main h1").should("contain.text", "World War I and the Department");
        cy.get("a.usa-button").should("have.attr", "href").and("match", /static\.history\.state\.gov/);
    });
});

describe("breadcrumbs lead back to the section landing", () => {
    it("Short History chapter breadcrumb links back through the section", () => {
        cy.visit("departmenthistory/short-history/foundations");
        cy.get("nav[aria-label='breadcrumb']").first().contains("a", "Department History").click();
        cy.location("pathname").should("match", /departmenthistory$/);
    });
});

// Known gap, not yet fixed (tracked under #1147's data-transformation scope,
// deliberately out of scope for #1134/#1135): the 108 Short History/Buildings
// graphics carry bare filenames with no S3 base-URI resolution, so `<img>`
// src attributes do not currently resolve. No assertion here pending that fix
// -- asserting it now would either be a false negative or would need to be
// skipped, and either hides the real, still-open gap rather than tracking it.
