// Anticipated (uncleared) volumes are not browsable (OP#1337; hsg-shell
// contract): the landing renders but lists no chapter entries, and interior
// division routes 404. The gate is VOLUME-level (revisionDesc status at
// least partially-published, like hsg-shell's select-section): a partially
// published volume lists and serves its pending divisions, marked
// li.pending (sidebar-toc.cy.js / volume-landing.cy.js cover that side).
//
// Only the published side is tested. Testing the gate needs an unpublished
// volume that ships chapter files, and no data set here has one: the tests
// used frus1981-88v16, which is now partially-published, and the curated
// frus-tei subset's unpublished volumes (frus1981-88v37, frus1861-99Index)
// have no chapter files.

describe("chapter routes of FRUS volumes", () => {
    it("published volumes keep their chapters reachable", () => {
        cy.request("historicaldocuments/frus1981-88v05/ch1").its("status").should("eq", 200);
    });
});
