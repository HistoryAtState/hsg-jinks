// Status of the Foreign Relations Series page (OP#1292), reference parity
// with hsg-shell pages/historicaldocuments/status-of-the-series.xml.
//
// Every report section except the "Volumes in Progress" h2 is rendered only
// when its volume set is non-empty, and the "Published in ..." /
// "Anticipated in ..." sections additionally depend on the current year, so
// none of those are asserted here. What is asserted from data: the
// "Volumes with Chapters Outstanding" table and the "Being Cleared" list,
// both driven by frus1977-80v27's partially-published revisionDesc in the
// dev subset -- lower-bound counts only, per CLAUDE.md "Cypress assertions
// on data-package counts".

const PAGE = "historicaldocuments/status-of-the-series";

describe("the status of the series page", () => {
    beforeEach(() => cy.visit(PAGE));

    it("responds with 200", () => {
        cy.request(PAGE).its("status").should("eq", 200);
    });

    it("shows the fixed heading and intro paragraph", () => {
        cy.get("main h1", { timeout: 15000 }).should(
            "have.text",
            "Status of the Foreign Relations of the United States Series"
        );
        cy.get("main h1 em").should("have.text", "Foreign Relations of the United States");
        cy.contains("main p", "volumes proceed through four main stages of").should("exist");
    });

    it("always shows the Volumes in Progress heading", () => {
        cy.contains("main h2", "Volumes in Progress", { timeout: 15000 }).should("exist");
    });

    it("shows the chapters-outstanding table for the partially published volume", () => {
        cy.contains("main h2", "Volumes with Chapters Outstanding", { timeout: 15000 }).should(
            "exist"
        );
        // Fixed chrome of the table, once it renders: exactly these 3 columns.
        cy.get("main table.usa-table thead th").should($ths => {
            expect($ths.map((i, th) => th.textContent.trim()).get()).to.deep.equal([
                "Volume title",
                "Chapters in Clearance",
                "Chapters Published",
            ]);
        });
        cy.get("main table.usa-table tbody tr").should("have.length.at.least", 1);
        // Each row links the volume title and lists chapters in year groups.
        cy.get("main table.usa-table tbody tr")
            .first()
            .within(() => {
                cy.get("td").eq(0).find("a").should("have.attr", "href")
                    .and("match", /historicaldocuments\/frus[^/]+$/);
                cy.get("td").eq(1).find("ul li a").should("have.length.at.least", 1);
            });
    });

    it("lists volumes being cleared with their outstanding chapters", () => {
        cy.contains("main h3", "Being Cleared", { timeout: 15000 })
            .parent()
            .within(() => {
                cy.get("ol > li").should("have.length.at.least", 1);
                cy.get("ol > li ul li").should("have.length.at.least", 1);
            });
    });

    it("has the section navigation in the left sidebar", () => {
        cy.get("aside.before ul.usa-sidenav", { timeout: 15000 })
            .find("a[href$='historicaldocuments/status-of-the-series']")
            .should("exist");
    });
});
