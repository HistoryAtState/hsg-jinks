// Every page carries the reference system's exact <title> (OP#1333):
// hsg-shell's per-page static-title trails, "<page> - <section trail> -
// Office of the Historian", verified value-for-value against the reference
// mirror and production. Page templates declare their trail via
// [% template! title %]; hsg-content.html supplies the FRUS default
// ("Historical Documents", the reference's value for every volume, chapter
// and document page).

const SITE = "Office of the Historian";

describe("page <title> (OP#1333, reference parity)", () => {
    [
        // the reference landing's title comes from its "Latest News" carousel
        // heading; kept value-identical
        ["", `Latest News - ${SITE}`],
        ["about", `About Us - ${SITE}`],
        ["about/faq", `FAQs - About Us - ${SITE}`],
        ["about/contact-us", `Contact Us - About Us - ${SITE}`],
        ["historicaldocuments", `Historical Documents - ${SITE}`],
        ["historicaldocuments/about-frus", `About the Foreign Relations Series - Historical Documents - ${SITE}`],
        ["historicaldocuments/frus1981-88v05", `Historical Documents - ${SITE}`],
        ["historicaldocuments/frus1981-88v05/d57", `Historical Documents - ${SITE}`],
        ["historicaldocuments/frus-history", `History of the Foreign Relations Series - ${SITE}`],
        ["milestones", `Milestones - ${SITE}`],
        ["tags", `Tags - ${SITE}`],
        ["conferences", `Conferences - ${SITE}`],
        ["developer", `Developer Resources - ${SITE}`],
        ["search", `Search - ${SITE}`],
        ["search/tips", `Tips - Search - ${SITE}`],
        ["countries", `Countries - ${SITE}`],
        ["countries/argentina", `Argentina - Countries - ${SITE}`],
        ["departmenthistory", `Department History - ${SITE}`],
        ["departmenthistory/people/secretaries", `Biographies of the Secretaries of State - Department History - ${SITE}`],
        ["departmenthistory/people/by-name/a", `A - Principals and Chiefs Alphabetical Listing - People - Department History - ${SITE}`],
        ["departmenthistory/short-history/foundations", `Foundations of Foreign Affairs, 1775-1823 - Short History - Department History - ${SITE}`],
        ["departmenthistory/visits/1985", `1985 - Visits by Foreign Leaders - Department History - ${SITE}`],
        ["education", `Education Resources - ${SITE}`],
        ["conferences/2007-detente", `Détente Conference - Conferences - ${SITE}`],
    ].forEach(([path, expected]) => {
        it(`/${path} is titled "${expected}"`, () => {
            cy.visit(path === "" ? "index.html" : path);
            cy.title().should("eq", expected);
        });
    });

    it("the 404 page keeps the site suffix", () => {
        cy.visit({ url: "no-such-page-zzz", failOnStatusCode: false });
        cy.title().should("eq", `Page not found - ${SITE}`);
    });

    // deliberate divergence: the reference's content-warning page repeats
    // "Contact Us - About Us" (an upstream copy-paste slip); ours names the
    // page. Recorded here so the difference is a decision, not an accident.
    it("/about/content-warning names the page (reference has a copy-paste slip)", () => {
        cy.visit("about/content-warning");
        cy.title().should("eq", `Content Warning - About Us - ${SITE}`);
    });
});
