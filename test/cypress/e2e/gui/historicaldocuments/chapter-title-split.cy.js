// Split chapter titles (OP#1085): frus-unbound-alpha encodes a chapter's
// date-range title and descriptive subtitle as two titleStmt/title elements.
// Reference parity (history.state.gov renders its tei-lb <br> between them):
// block contexts (heading, TOCs, document list) break the line; the
// breadcrumb, which cannot, separates with a space.
//
// frus1981-88v05 ch1 is part of the frozen baseline data, so exact
// assertions on its title are fine.

const chapter = "historicaldocuments/frus1981-88v05/ch1";
const datePart = "March 1985–July 1985";
const subtitle = "“Now we have to begin everything anew”: Gorbachev’s Debut";

describe("split chapter titles", () => {
    it("breaks the line between date range and subtitle in the chapter heading", () => {
        cy.visit(chapter);
        cy.get("main h1.hsg-frus__division-title", { timeout: 15000 })
            .should("contain.text", datePart)
            .and("contain.text", subtitle)
            .find("br").should("have.length", 1);
    });

    it("separates date range and subtitle with a space in the breadcrumb", () => {
        cy.visit(chapter);
        cy.get("li.breadcrumb-current", { timeout: 15000 })
            .should("have.text", `${datePart} ${subtitle}`);
    });

    it("breaks the line in the sidebar table of contents", () => {
        cy.visit(chapter);
        cy.get("aside a[aria-current='page']", { timeout: 15000 })
            .should("contain.text", datePart)
            .find("br").should("have.length", 1);
    });

    it("breaks the line in the compilation's chapter list", () => {
        cy.visit("historicaldocuments/frus1981-88v05/comp");
        cy.get(`main .hsg-frus__doclist a[href$='/${chapter}']`, { timeout: 15000 })
            .should("contain.text", datePart)
            .find("br").should("have.length", 1);
    });

    it("breaks the line in the volume landing table of contents", () => {
        cy.visit("historicaldocuments/frus1981-88v05");
        cy.get(`main a[href$='/${chapter}']`, { timeout: 15000 })
            .first()
            .should("contain.text", datePart)
            .find("br").should("have.length", 1);
    });
});
