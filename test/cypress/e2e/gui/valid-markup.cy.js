// Guards against document elements leaking into the page body.
//
// Documents and non-chapter divisions used to fall through to the ODD's
// default behaviour="document" transform, which emits a complete
// <html><head>… skeleton *inside* <main> (invalid HTML). They now render
// via the "division" mode (templates/pages/volume-interior.html +
// resources/odd/hsg-jinks.odd), which only outputs the text body.
//
// baseUrl notes: see breadcrumb.cy.js.

const PAGES = [
    "historicaldocuments/frus1981-88v05",
    "historicaldocuments/frus1981-88v05/comp",
    "historicaldocuments/frus1981-88v05/ch1",
    "historicaldocuments/frus1981-88v05/d1",
    "historicaldocuments/frus1981-88v05/preface",
];

describe("rendered pages contain no nested document elements", () => {
    PAGES.forEach((page) => {
        it(`${page} has no html/head/body inside main`, () => {
            cy.visit(page);
            cy.get("main").within(() => {
                cy.get("html, head, body").should("not.exist");
            });
        });
    });

    it("document body content still renders on d1", () => {
        cy.visit("historicaldocuments/frus1981-88v05/d1");
        cy.get("main section p").should("have.length.greaterThan", 0);
    });
});
