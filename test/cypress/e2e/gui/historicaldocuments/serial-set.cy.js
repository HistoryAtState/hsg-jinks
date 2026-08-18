// The pre-1861 U.S. Congressional Serial Set subsection (OP#1303-#1305),
// reference parity with hsg-shell:
// https://history.state.gov/historicaldocuments/pre-1861/serial-set
//
// The records come from the other-publications data package (append-only
// upstream), so record/term counts assert lower bounds; at write-time the
// data held 2805 records, 5 regions, 81 subjects, and 10 Africa/Egypt
// records. Fixed page chrome asserts exact values.

describe("the serial-set landing page", () => {
    beforeEach(() => cy.visit("historicaldocuments/pre-1861/serial-set"));

    it("returns HTTP 200", () => {
        cy.request("historicaldocuments/pre-1861/serial-set").its("status").should("eq", 200);
    });

    it("shows the heading and the TEI introduction", () => {
        cy.get("main h1", { timeout: 15000 })
            .should("contain.text", "U.S. foreign relations materials in the pre-1861 U.S. Congressional Serial");
        cy.get("main").should("contain.text", "began publication in 1817");
    });

    it("links to the full bibliography", () => {
        cy.get("main a[href$='/historicaldocuments/pre-1861/serial-set/all']", { timeout: 15000 })
            .should("contain.text", "View all");
    });

    it("lists the regions with their subjects as browse links", () => {
        cy.get("main ul.usa-list > li", { timeout: 15000 }).should("have.length.at.least", 5);
        cy.get("main ul.usa-list > li a[href*='serial-set/browse?region=']").should("exist");
        cy.get("main ul.usa-list > li li a[href*='&subject=']").should("have.length.at.least", 75);
    });

    it("has the section navigation in the left sidebar", () => {
        cy.get("aside.before ul.usa-sidenav", { timeout: 15000 }).should("exist");
    });
});

describe("the serial-set full bibliography page", () => {
    beforeEach(() => cy.visit("historicaldocuments/pre-1861/serial-set/all"));

    it("returns HTTP 200", () => {
        cy.request("historicaldocuments/pre-1861/serial-set/all").its("status").should("eq", 200);
    });

    it("shows the heading and the record count", () => {
        cy.get("main h1", { timeout: 15000 })
            .should("contain.text", "All Documents on U.S. foreign relations before");
        cy.get("main p").invoke("text").should("match", /\d+ sources, in chronological\s+order/);
    });

    it("renders the six-column record table with all records", () => {
        cy.get("main table.usa-table thead th", { timeout: 15000 }).should("have.length", 6);
        cy.get("main table.usa-table thead").should("contain.text", "Region")
            .and("contain.text", "Subject").and("contain.text", "Pages");
        cy.get("main table.usa-table tbody tr").should("have.length.at.least", 2500);
    });
});

describe("the serial-set browse page", () => {
    it("filters by region, dropping the region column", () => {
        cy.visit("historicaldocuments/pre-1861/serial-set/browse?region=Africa");
        cy.get("main h1", { timeout: 15000 })
            .should("contain.text", "Documents on")
            .and("contain.text", "Africa before");
        cy.get("main table.usa-table thead th").should("have.length", 5);
        cy.get("main table.usa-table thead").should("not.contain.text", "Region");
        cy.get("main table.usa-table tbody tr").should("have.length.at.least", 10);
    });

    it("filters by region and subject, dropping both columns", () => {
        cy.visit("historicaldocuments/pre-1861/serial-set/browse?region=Africa&subject=Egypt");
        cy.get("main h1", { timeout: 15000 }).should("contain.text", "Egypt (Africa)");
        cy.get("main table.usa-table thead th").should("have.length", 4);
        cy.get("main table.usa-table tbody tr").should("have.length.at.least", 5);
    });

    it("shows the region and subject as trailing breadcrumbs", () => {
        cy.visit("historicaldocuments/pre-1861/serial-set/browse?region=Africa&subject=Egypt");
        cy.get("nav[aria-label='breadcrumb'] a[href*='browse?region=Africa']", { timeout: 15000 })
            .should("contain.text", "Africa");
        cy.get("nav[aria-label='breadcrumb'] li[aria-current='page']").should("contain.text", "Egypt");
    });
});
