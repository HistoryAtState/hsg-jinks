// Every page carries "<page> - Office of the Historian" as its <title>
// (OP#1333; reference parity with hsg-shell). The landing page is the bare
// site name. Page templates declare their heading via [% template! title %];
// hsg-content.html derives a default for doc-backed FRUS pages.

const SITE = "Office of the Historian";

describe("page <title> (OP#1333)", () => {
    [
        ["", SITE],
        ["about/faq", `Frequently Asked Questions - ${SITE}`],
        ["about/contact-us", `Contact Us - ${SITE}`],
        ["historicaldocuments", `Historical Documents - ${SITE}`],
        ["milestones", `Milestones in the History of U.S. Foreign Relations - ${SITE}`],
        ["tags", `Tags - ${SITE}`],
        ["conferences", `Conferences - ${SITE}`],
        ["developer", `Developer Resources - ${SITE}`],
        ["search", `Search - ${SITE}`],
        ["countries", `Countries - ${SITE}`],
        ["departmenthistory/people/secretaries", `Secretaries of State - ${SITE}`],
    ].forEach(([path, expected]) => {
        it(`/${path} is titled "${expected}"`, () => {
            cy.visit(path === "" ? "index.html" : path);
            cy.title().should("eq", expected);
        });
    });

    it("a FRUS document page is titled by document number and volume", () => {
        cy.visit("historicaldocuments/frus1981-88v05/d57");
        cy.title()
            .should("match", /^Document 57 - Foreign Relations of the United States/)
            .and("match", new RegExp(` - ${SITE}$`));
    });

    it("the 404 page keeps the site suffix", () => {
        cy.visit({ url: "no-such-page-zzz", failOnStatusCode: false });
        cy.title().should("eq", `Page not found - ${SITE}`);
    });
});
