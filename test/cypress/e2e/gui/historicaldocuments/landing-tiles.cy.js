// The Historical Documents landing opens its administrations grid with the
// first three presidencies, portraits from the static bucket, in hsg-shell's
// order. Ported from hsg-shell's historical-documents/landing.cy.js
// (OP#1466); administrations.cy.js covers the grid's size and card content,
// nav/menu.cy.js the menu link to this page.

describe("the historical documents landing tiles", () => {
    it("start with Lincoln, Andrew Johnson and Grant", () => {
        cy.visit("historicaldocuments");
        cy.get("main .hsg-admin-cards .usa-card__media img").then(($imgs) => {
            const srcs = [...$imgs].slice(0, 3).map((img) => img.getAttribute("src"));
            expect(srcs).to.deep.eq([
                "https://static.history.state.gov/images/alincoln.jpg",
                "https://static.history.state.gov/images/ajohnson.jpg",
                "https://static.history.state.gov/images/usgrant.jpg",
            ]);
        });
    });
});
