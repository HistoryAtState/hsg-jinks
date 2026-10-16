// The data-driven statics of the section (content-page.html, OP#1313) show
// their division head as the page title and the Administrations panel in
// the right sidebar (OP#1467). The rule hiding the duplicate head of
// monograph sections must leave the title alone.

const CONTENT_PAGES = [
    ["about-frus", "About the Foreign Relations of the United States Series"],
    ["citing-frus", "Citing the Foreign Relations series"],
    ["other-electronic-resources", "Electronic Resources for U.S. Foreign Relations"],
    ["pre-1861", "Pre-1861 U.S. foreign relations materials"],
];

describe("historical documents content pages", () => {
    CONTENT_PAGES.forEach(([page, title]) => {
        it(`shows the title on ${page}`, () => {
            cy.visit(`historicaldocuments/${page}`);
            cy.get("main h1", { timeout: 15000 }).should("have.length", 1).and("be.visible").and("contain.text", title);
        });

        it(`shows the Administrations panel on ${page}`, () => {
            // hsg:administrations-panel; the links themselves are listed in
            // about-frus.cy.js.
            cy.visit(`historicaldocuments/${page}`);
            cy.get("aside.after", { timeout: 15000 }).within(() => {
                cy.contains("h2", "Administrations").should("be.visible");
                cy.get("li a").first().should("have.text", "Kennedy Administration");
                cy.get("li a").last().should("have.text", "All Administrations");
            });
        });
    });

    it("still hides the duplicate head on a monograph section", () => {
        // about:monograph-section-content renders the head as the page h1;
        // the division's own copy stays hidden.
        cy.visit("about/hac/december-1996");
        cy.get("main h1:visible", { timeout: 15000 }).should("have.length", 1).and("have.text", "December 1996");
    });
});
