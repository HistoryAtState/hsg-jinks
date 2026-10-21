// Department History page headings, ported from hsg-shell's per-route
// headline specs (tests/cypress/e2e/departmenthistory/*, OP#1466). Routes
// another spec already asserts the heading of are left out: buildings,
// buildings/section2 and section3, short-history and its foundations and
// origins chapters, and wwi.
//
// hsg-shell heads the Secretaries list "Biographies of the Secretaries of
// State"; hsg-jinks keeps that only in the page <title> (page-titles.cy.js).
// The shorter heading was accepted with OP#1318.

const shouldBeHeaded = (expected) =>
    cy.get("main h1").filter(":visible").first().should(($h1) => {
        expect($h1.text().replace(/\s+/g, " ").trim()).to.eq(expected);
    });

describe("department history page headings", () => {
    [
        ["departmenthistory", "Department History"],
        ["departmenthistory/buildings/foreword", "Original Foreword"],
        ["departmenthistory/buildings/intro", "Introduction"],
        ["departmenthistory/buildings/section1", "The Period of the Continental Congress"],
        ["departmenthistory/diplomatic-couriers", "U.S. Diplomatic Couriers"],
        ["departmenthistory/people/principals-chiefs", "Principal Officers and Chiefs of Mission"],
        ["departmenthistory/people/secretaries", "Secretaries of State"],
        ["departmenthistory/travels/president", "Travels Abroad of the President"],
        ["departmenthistory/travels/secretary", "Travels Abroad of the Secretary of State"],
        ["departmenthistory/visits", "Visits by Foreign Leaders"],
    ].forEach(([path, expected]) => {
        it(`/${path} is headed "${expected}"`, () => {
            cy.visit(path);
            shouldBeHeaded(expected);
        });
    });
});
