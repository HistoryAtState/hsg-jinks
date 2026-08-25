// Anticipated (uncleared) volumes are not browsable (OP#1337; hsg-shell
// contract): the landing renders but lists no chapter entries, and interior
// division routes 404. The gate is VOLUME-level (revisionDesc status at
// least partially-published, like hsg-shell's select-section): a partially
// published volume lists and serves its pending divisions, marked
// li.pending (sidebar-toc.cy.js / volume-landing.cy.js cover that side).
// frus1981-88v16 is 'being-cleared' (curated dev subset, OP#1320); if the
// volume is not deployed the tests skip rather than fail.

const VOLUME = "historicaldocuments/frus1981-88v16";

describe("anticipated FRUS volume (frus1981-88v16)", () => {
    let deployed = false;

    before(() => {
        cy.request({ url: VOLUME, failOnStatusCode: false }).then((r) => {
            deployed = r.status === 200;
        });
    });

    it("landing renders with no chapter links in its table of contents", function () {
        if (!deployed) this.skip();
        cy.visit(VOLUME);
        cy.get("h1").should("contain.text", "South America");
        cy.get(`a[href*="frus1981-88v16/ch"]`).should("not.exist");
    });

    it("chapter routes 404 while the volume is in clearance", function () {
        if (!deployed) this.skip();
        cy.request({ url: `${VOLUME}/ch1`, failOnStatusCode: false })
            .its("status")
            .should("eq", 404);
    });

    it("published volumes keep their chapters reachable", () => {
        cy.request("historicaldocuments/frus1981-88v05/ch1").its("status").should("eq", 200);
    });
});
