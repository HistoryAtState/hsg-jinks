// Milestones era page: heading and article listing, and the era foreword's
// heading. Ported from hsg-shell's milestones/1750-1775/*.cy.js and the
// Milestones case of ui-components/table-of-contents.cy.js (OP#1466).
// browse.cy.js and deep-links.cy.js cover the landing, the all-milestones
// listing and the 1914-1920 era.

const ERA = "milestones/1750-1775";

const shouldBeHeaded = (expected) =>
    cy.get("main h1").filter(":visible").first().should(($h1) => {
        expect($h1.text().replace(/\s+/g, " ").trim()).to.eq(expected);
    });

describe("a milestones era page", () => {
    beforeEach(() => cy.visit(ERA));

    it("is headed with the publication title", () => {
        shouldBeHeaded("Milestones in the History of U.S. Foreign Relations");
    });

    it("lists the era's articles", () => {
        cy.get("main ul.usa-sidenav a").should("have.length.at.least", 5);
        cy.get(`main ul.usa-sidenav a[href$='${ERA}/french-indian-war']`).should("exist");
    });
});

describe("a milestones era foreword", () => {
    it("is headed with the era title", () => {
        cy.visit(`${ERA}/foreword`);
        shouldBeHeaded("1750–1775: Diplomatic Struggles in the Colonial Period");
    });
});
