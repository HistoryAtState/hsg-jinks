// A volume landing is headed once, by the volume title, followed by the
// cover whose alt text names the volume. Ported from hsg-shell's
// historical-documents/volume/volume-cover.cy.js (OP#1466), on a volume of
// the frus-data-jinks baseline instead of frus1951-54IranEd2.
// volume-landing.cy.js covers the cover URL on frus1981-88v05.

const TITLE = "Foreign Relations of the United States, 1981–1988, Volume XLI, Global Issues II";

describe("volume landing with a cover", () => {
    beforeEach(() => cy.visit("historicaldocuments/frus1981-88v41"));

    it("shows the cover image from the static bucket", () => {
        cy.get("main img.hsg-frus__cover").should(
            "have.attr",
            "src",
            "https://static.history.state.gov/frus/frus1981-88v41/covers/frus1981-88v41.jpg",
        );
    });

    it("gives the cover the volume title as alt text", () => {
        cy.get("main img.hsg-frus__cover").should("have.attr", "alt", `Book Cover of ${TITLE}`);
    });

    it("puts the volume title in an h1 before the image", () => {
        cy.get("main img.hsg-frus__cover").prev("h1").should("have.text", TITLE);
    });

    it("shows no second heading generated from the TEI", () => {
        cy.get("main h1").filter(":visible").should("have.length", 1);
    });
});
