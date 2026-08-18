// Covers the user story "As a User I want to be able to navigate from the
// volume landing page to a document detail view" -- click-through from the
// section landing down to a document, entirely via rendered links.
//
// The section landing at /historicaldocuments groups volumes by presidential
// administration (OP#1214): one card per presidency linking to an
// administration page, which lists that administration's volumes -- so the
// chain gained one level: section -> administration -> volume -> ... -> document.
//
// frus-data-jinks is append-only upstream like the external data packages
// (see CLAUDE.md "Cypress assertions on data-package counts"): new volumes
// get added over time, so assert lower bounds on data-derived counts, not
// exact ones.

const SECTION = "historicaldocuments";
const ADMIN = "historicaldocuments/reagan";
const VOLUME = "historicaldocuments/frus1981-88v05";

describe("the section landing", () => {
    it("lists administrations as cards", () => {
        cy.visit(SECTION);
        cy.get("main h1").should("contain.text", "Historical Documents");
        cy.get("main .hsg-admin-cards > li.usa-card").should("have.length.at.least", 25);
        cy.get(`main .hsg-admin-cards a[href$='${ADMIN}']`).should("exist");
    });

    it("is what the breadcrumb's Historical Documents crumb points at", () => {
        cy.visit(`${VOLUME}/d1`);
        cy.get("nav[aria-label='breadcrumb']")
            .contains("a", "Historical Documents")
            .click();
        cy.location("pathname").should("match", new RegExp(`${SECTION}$`));
        cy.get("main .hsg-admin-cards > li.usa-card").should("have.length.at.least", 25);
    });
});

describe("navigate from the section landing to a document", () => {
    it("clicks through section -> administration -> landing -> compilation -> chapter -> document", () => {
        cy.visit(SECTION);
        cy.get(`main .hsg-admin-cards a[href$='${ADMIN}']`).click();
        cy.location("pathname").should("match", new RegExp(`${ADMIN}$`));

        // By href, not by title text: several volumes share the "Soviet
        // Union" prefix within the administration's listing.
        cy.get(`main a[href$='${VOLUME}']`).click();
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
