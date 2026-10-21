// Conference page headings, ported from hsg-shell's per-route headline specs
// (tests/cypress/e2e/conferences/20*, OP#1466). Routes another spec already
// asserts the heading of are left out: the 2010-southeast-asia landing,
// secretary-clinton, photos and videos-transcripts.
//
// A conference landing is a table of contents headed by the conference
// title (document-view-content.cy.js). hsg-shell inlined the first division
// instead, so its 2007-detente spec expected "Schedule"; the jinks heading
// was accepted with OP#1318. The conference documents are frozen, so the
// headings are exact.

const shouldBeHeaded = (expected) =>
    cy.get("main h1").filter(":visible").first().should(($h1) => {
        expect($h1.text().replace(/\s+/g, " ").trim()).to.eq(expected);
    });

describe("conference page headings", () => {
    [
        ["conferences/2006-china-cold-war", "Transforming the Cold War: The United States and China, 1969-1980"],
        ["conferences/2006-china-cold-war/susser", "Introductions"],
        ["conferences/2007-detente", "U.S.-Soviet Relations in the Era of Détente, 1969-1976"],
        ["conferences/2007-detente/roundtable1", "Introduction to Roundtable Discussion of Former Government Officials"],
        ["conferences/2010-southeast-asia/background-materials", "Background Materials"],
        ["conferences/2010-southeast-asia/maps", "Maps"],
        ["conferences/2011-foreign-economic-policy", "Foreign Economic Policy, 1973-1976"],
        ["conferences/2011-foreign-economic-policy/audio-transcripts", "Audio and Transcripts"],
        [
            "conferences/2011-foreign-economic-policy/opening-remarks-and-editors-talk",
            "Opening Remarks and Editor’s Talk on Foreign Economic Policy, 1973-1976",
        ],
        ["conferences/2011-foreign-economic-policy/panel", "Panel Discussion"],
        ["conferences/2012-national-security-policy-salt", "National Security Policy and SALT I, 1969-1972"],
    ].forEach(([path, expected]) => {
        it(`/${path} is headed "${expected}"`, () => {
            cy.visit(path);
            shouldBeHeaded(expected);
        });
    });
});
