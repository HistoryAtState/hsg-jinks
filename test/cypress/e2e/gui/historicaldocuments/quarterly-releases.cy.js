// The Quarterly Releases index and its ten frozen announcement pages
// (OP#1295), reference parity with hsg-shell.
//
// All content on these pages is static and frozen (the quarterly release
// program ended in 2018), so exact assertions are used throughout -- the
// lower-bound rule for data-derived counts does not apply here.

const SECTION = "historicaldocuments/quarterly-releases";

const RELEASE_IDS = [
    "2016-q3", "2016-q4",
    "2017-q1", "2017-q2", "2017-q3", "2017-q4",
    "2018-q1", "2018-q2", "2018-q3", "2018-q4",
];

describe("the quarterly releases index", () => {
    it("returns 200", () => {
        cy.request(SECTION).its("status").should("eq", 200);
    });

    it("shows the heading and links to all ten announcements", () => {
        cy.visit(SECTION);
        cy.get("main h1", { timeout: 15000 }).should("have.text", "Quarterly Releases");
        // exactly the 10 announcement links, one per release
        cy.get("main a[href*='/quarterly-releases/']").should("have.length", 10);
        RELEASE_IDS.forEach((id) => {
            cy.get(`main a[href$='historicaldocuments/quarterly-releases/${id}']`)
                .should("have.length", 1);
        });
        // the 2017-q2 entry also announces the Iran retrospective volume
        cy.get("main a[href$='historicaldocuments/frus1951-54Iran']").should("exist");
        cy.get(".hsg-historicaldocuments-nav .hsg-historicaldocuments-nav-card").should("have.length", 8);
    });
});

describe("an announcement page (2018-q4)", () => {
    it("returns 200", () => {
        cy.request(`${SECTION}/2018-q4`).its("status").should("eq", 200);
    });

    it("shows the announcement heading, date, and volume links", () => {
        cy.visit(`${SECTION}/2018-q4`);
        cy.get("main h1", { timeout: 15000 }).should(
            "have.text",
            "Quarterly Release of Newly Digitized Foreign Relations Volumes"
        );
        cy.get("main h1 + p").should("have.text", "December 6, 2018");
        // frozen list of the 14 volumes in this release
        cy.get("main ol a[href*='/historicaldocuments/frus']").should("have.length", 14);
        cy.get("main ol a[href$='/historicaldocuments/frus1861']").should("exist");
        cy.get("main ol a[href$='/historicaldocuments/frus1863p2']").should("exist");
        cy.get("main ol a[href$='/historicaldocuments/frus1866p3']").should("exist");
        // breadcrumb links back to the quarterly releases index
        cy.get("nav[aria-label='breadcrumb'] a[href$='historicaldocuments/quarterly-releases']")
            .should("exist");
    });
});

describe("an unknown release id", () => {
    it("returns 404", () => {
        cy.request({ url: `${SECTION}/2019-q1`, failOnStatusCode: false })
            .its("status")
            .should("eq", 404);
    });
});
