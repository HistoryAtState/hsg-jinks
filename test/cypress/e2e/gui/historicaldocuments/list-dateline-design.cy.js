// Upstream frus.odd list/dateline design (OP#1317). The former item/label/
// opener ODD guards are retired; these tests pin the adopted markup contract
// so a regression in the ODD chain (odd:merge replaces wholesale!) is caught
// structurally, not just visually.

const VOLUME = "historicaldocuments/frus1981-88v05";

describe("FRUS description lists (upstream design)", () => {
    it("renders a subject list as ul.description with its label as a heading line", () => {
        cy.visit(`${VOLUME}/d16`);
        cy.get("ul.description.subtype-subject", { timeout: 15000 })
            .first()
            .within(() => {
                cy.get("li.listLabel").should("contain.text", "SUBJECT");
                cy.get("li").should("have.length.at.least", 2);
            });
    });

    it("renders a participants list the same way", () => {
        cy.visit(`${VOLUME}/d38`);
        cy.get("ul.description.subtype-participants", { timeout: 15000 })
            .first()
            .find("li.listLabel")
            .should("exist");
    });
});

describe("FRUS dateline (upstream design)", () => {
    it("is an inline span inside the opener paragraph, floated by its rendition", () => {
        cy.visit(`${VOLUME}/d57`);
        cy.get("p.opener", { timeout: 15000 }).first().within(() => {
            cy.get("span.dateline").should("contain.text", "July 8, 1985");
        });
        // the invalid shape the retired opener guard used to prevent
        cy.get("p.opener > div").should("not.exist");
    });
});

describe("FRUS index divisions (upstream design)", () => {
    // The same check on the back-matter index lives in
    // volume-front-back-matter.cy.js, the one test that renders that slow
    // page (OP#1470).
    it("renders register entries as their own blocks, never divs inside a ul", () => {
        cy.visit(`${VOLUME}/persons`);
        cy.get("main div.list", { timeout: 15000 }).should("have.length.at.least", 50);
        cy.get("main ul > div").should("not.exist");
    });
});
