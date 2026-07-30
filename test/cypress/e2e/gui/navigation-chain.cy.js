// Covers the user story "As a User I want to be able to navigate from the
// volume landing page to a document detail view" -- click-through from the
// volume landing page down to a document, entirely via rendered links.
//
// The section landing at /historicaldocuments extends that chain one level up.
// It is scaffolding: a bare list of volumes, enough to navigate through and
// to give the breadcrumb's "Historical Documents" crumb -- which every
// content page links to -- somewhere to land.
//
// frus-data-jinks is append-only upstream like the external data packages
// (see CLAUDE.md "Cypress assertions on data-package counts"): new volumes
// get added over time (frus1981-88v41 alongside frus1981-88v05), so assert a
// lower bound on the volume count, not an exact one.

const SECTION = "historicaldocuments";
const VOLUME = "historicaldocuments/frus1981-88v05";

describe("the section landing", () => {
    it("lists every volume as a link", () => {
        cy.visit(SECTION);
        cy.get("main h1").should("contain.text", "Historical Documents");
        cy.get("main ul.volume-list > li").should("have.length.at.least", 1);
        cy.get("main ul.volume-list a[href$='historicaldocuments/frus1981-88v05']").should("exist");
    });

    it("is what the breadcrumb's Historical Documents crumb points at", () => {
        cy.visit(`${VOLUME}/d1`);
        cy.get("nav[aria-label='breadcrumb']")
            .contains("a", "Historical Documents")
            .click();
        cy.location("pathname").should("match", new RegExp(`${SECTION}$`));
        cy.get("main ul.volume-list > li").should("have.length.at.least", 1);
    });
});

describe("navigate from volume landing to a document", () => {
    it("clicks through section -> landing -> compilation -> chapter -> document", () => {
        cy.visit(SECTION);
        cy.contains("a", "Foreign Relations of the United States").click();
        cy.location("pathname").should("match", new RegExp(`${VOLUME}$`));

        cy.contains("a", "Soviet Union, March 1985").click();
        cy.location("pathname").should("match", new RegExp(`${VOLUME}/comp$`));

        cy.contains("a", "Gorbachev").click();
        cy.location("pathname").should("match", new RegExp(`${VOLUME}/ch1$`));

        cy.get("main a[href$='d1']").first().click();
        cy.location("pathname").should("match", new RegExp(`${VOLUME}/d1$`));
        cy.get("main").should("contain.text", "Reagan");
    });
});
