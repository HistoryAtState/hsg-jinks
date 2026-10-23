// Tag page headings, ported from hsg-shell's per-route headline specs
// (tests/cypress/e2e/tags/*, OP#1466). tags.cy.js asserts the headings of
// /tags, /tags/all and /tags/presidents.
//
// hsg-shell headed the category and tag pages with an h2 below a section
// h1; here the page's own h1 carries the name.

const shouldBeHeaded = (expected) =>
    cy.get("main h1").filter(":visible").first().should(($h1) => {
        expect($h1.text().replace(/\s+/g, " ").trim()).to.eq(expected);
    });

describe("tag page headings", () => {
    [
        ["tags/people", "People"],
        ["tags/places", "Places"],
        ["tags/topics", "Topics"],
        ["tags/secretaries-of-state", "Secretaries of State"],
        ["tags/buchanan-james-p", "Buchanan, James (P)"],
        ["tags/jefferson-thomas-s", "Jefferson, Thomas (S)"],
    ].forEach(([path, expected]) => {
        it(`/${path} is headed "${expected}"`, () => {
            cy.visit(path);
            shouldBeHeaded(expected);
        });
    });
});
