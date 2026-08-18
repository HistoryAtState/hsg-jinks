// The by-administration section landing and the administration pages
// (OP#1214), reference parity with hsg-shell.
//
// The administration list is data-derived (the administrations taxonomy in
// frus-data-jinks) but effectively frozen -- a new entry means a new
// presidential administration entered the FRUS series -- so lower-bound
// counts are used for it anyway per CLAUDE.md "Cypress assertions on
// data-package counts". The sidebar is fixed UI chrome: exact count.

const SECTION = "historicaldocuments";

describe("the administrations grid", () => {
    beforeEach(() => cy.visit(SECTION));

    it("shows one card per presidency with portrait and coverage dates", () => {
        cy.get("main .hsg-admin-cards > li.usa-card").should("have.length.at.least", 25);
        cy.get("main .hsg-admin-cards .usa-card__media img").should("have.length.at.least", 25);
        cy.contains("main .usa-card", "Abraham Lincoln Administration")
            .should("contain.text", "1861–1865")
            .find("a")
            .should("have.attr", "href")
            .and("match", /historicaldocuments\/lincoln$/);
    });

    it("links both Nixon and Ford to the shared nixon-ford page", () => {
        cy.get("main .hsg-admin-cards a[href$='historicaldocuments/nixon-ford']")
            .should("have.length", 2);
    });

    it("keeps Grover Cleveland's two non-consecutive terms separate", () => {
        cy.get("main .hsg-admin-cards a[href$='historicaldocuments/cleveland-22']").should("exist");
        cy.get("main .hsg-admin-cards a[href$='historicaldocuments/cleveland-24']").should("exist");
    });

    it("has the section navigation in the left sidebar", () => {
        cy.get("aside.before ul.usa-sidenav > li").should("have.length", 8);
        cy.get("aside.before ul.usa-sidenav a[href$='historicaldocuments/about-frus']").should("exist");
    });
});

describe("an administration page", () => {
    it("shows the heading with term-of-office dates and volumes grouped by sub-series", () => {
        cy.visit(`${SECTION}/reagan`);
        cy.get("main h1").should("contain.text", "Ronald Reagan Administration (1981–1989)");
        // Sub-series headings are h3 like the reference (frus:series-title);
        // an h2 only appears above them when several production tracks are
        // in use (see the nixon-ford/kennedy pages on the reference site).
        cy.get("main h3.hsg-admin__sub-series")
            .should("contain.text", "Foreign Relations of the United States, 1981–1988");
        cy.get("main .hsg-admin__volumes > li").should("have.length.at.least", 2);
        cy.get("main .hsg-admin__volumes .hsg-status-notice")
            .first()
            .should("contain.text", "Published");
        cy.get("main .hsg-admin__volumes a[href$='historicaldocuments/frus1981-88v05']").should("exist");
        // Reagan is administration-organized: no pre-1964 listing note.
        cy.get("main #pre-administration-based-subseries-note").should("not.exist");
    });

    it("shows the listing note with a term-scoped search link on a pre-1964 administration", () => {
        // OP#1251 reference parity with fh:administration-listing-note /
        // fh:admin-search-href: Lincoln has FRUS coverage in the dev data
        // subset (frus1861).
        cy.visit(`${SECTION}/lincoln`);
        cy.get("main #pre-administration-based-subseries-note", { timeout: 15000 })
            .should("contain.text", "The volumes listed")
            .find("a")
            .should("have.attr", "href")
            .and("match", /\/search\?within=documents&start-date=1861-03-04&end-date=1865-04-15&sort=date-asc$/);
    });

    it("uses the combined heading for the shared nixon-ford page", () => {
        cy.visit(`${SECTION}/nixon-ford`);
        cy.get("main h1").should(
            "contain.text",
            "Richard M. Nixon and Gerald R. Ford Administrations (1969–1977)"
        );
    });

    it("returns 404 for an unknown administration id", () => {
        cy.request({ url: `${SECTION}/no-such-admin`, failOnStatusCode: false })
            .its("status")
            .should("eq", 404);
    });
});
