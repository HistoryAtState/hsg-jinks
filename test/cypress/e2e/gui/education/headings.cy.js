// Education page headings, ported from hsg-shell's per-route headline specs
// (tests/cypress/e2e/education/*, OP#1466). curriculum-modules.cy.js
// asserts the documents-intro heading; the other module introductions only
// had theirs checked for existence.
//
// The module records are frozen archival data, so the headings are exact.
// They carry the curly quotes of the TEI; hsg-shell's spec compared them
// after straightening.

const shouldBeHeaded = (expected) =>
    cy.get("main h1").filter(":visible").first().should(($h1) => {
        expect($h1.text().replace(/\s+/g, " ").trim()).to.eq(expected);
    });

describe("education page headings", () => {
    [
        ["education", "Education"],
        ["education/modules", "Curriculum Modules"],
        [
            "education/modules/border-vanishes-intro",
            "Introduction to Curriculum Packet on “When the Border Vanishes: Diplomacy and the Threat to our Health and Environment”",
        ],
        ["education/modules/history-diplomacy-intro", "Introduction to Curriculum Packet on “A History of Diplomacy”"],
        [
            "education/modules/journey-shared-intro",
            "Introduction to Curriculum Packet on “A Journey Shared: The United States and China”",
        ],
        [
            "education/modules/media-intro",
            "Introduction to Curriculum Packet on “Today in Washington: The Media and Diplomacy”",
        ],
        [
            "education/modules/sports-intro",
            "Introduction to Curriculum Packet on “Sports and Diplomacy in the Global Arena”",
        ],
        ["education/modules/terrorism-intro", "Introduction to Curriculum Packet on “Terrorism: A War Without Borders”"],
    ].forEach(([path, expected]) => {
        it(`/${path} is headed "${expected}"`, () => {
            cy.visit(path);
            shouldBeHeaded(expected);
        });
    });
});
