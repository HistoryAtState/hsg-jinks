// Every section filter and date-filter form, under both sort orders, returns
// results; impossible date ranges return none. Ported from hsg-shell's
// search/filter-results.cy.js (OP#1466).
//
// hsg-shell searched 1946; the frozen frus-data-jinks baseline has no FRUS
// documents from then, so the date filters use 1985 (frus1981-88v05),
// keeping each of hsg-shell's date forms. Its end-date-only case is left
// out: an end date alone is ignored, on the reference site too (OP#1439).

const validFilters = [
    ["entire-site", { within: "entire-site" }],
    ["department", { within: "department" }],
    ["documents", { within: "documents" }],
    ["documents+dates", { within: "documents", "start-date": "1985-03-01", "end-date": "1985-06-30" }],
    ["documents+year", { within: "documents", "start-date": "1985", "end-date": "1985-06-30" }],
    ["documents+month", { within: "documents", "start-date": "1985-03", "end-date": "1985-06-30" }],
    ["documents+range", { within: "documents", "start-date": "1985-03-01", "end-date": "1985" }],
    ["documents+range-month", { within: "documents", "start-date": "1985-03-01", "end-date": "1985-06" }],
    ["documents+start-only", { within: "documents", "start-date": "1985-03-30" }],
];

const invalidFilters = [
    ["start-gt-end", { within: "documents", "start-date": "1985-01-02", "end-date": "1984-01-01" }],
    ["dates-out-of-scope", { within: "documents", "start-date": "1000-01-02", "end-date": "1000-01-01" }],
];

describe("search filters return results", () => {
    validFilters.forEach(([label, filter]) => {
        ["relevance", "date-asc"].forEach((sort) => {
            it(`${label}, sorted by ${sort}`, () => {
                cy.visit("search", { qs: { q: "china", ...filter, "sort-by": sort } });
                cy.get(".usa-collection__item a").should("have.length.at.least", 1);
            });
        });
    });
});

describe("impossible date ranges return no results", () => {
    invalidFilters.forEach(([label, filter]) => {
        it(label, () => {
            cy.visit("search", { qs: { q: "china", ...filter, "sort-by": "relevance" } });
            cy.get(".hsg-results-summary").should("have.text", "No results were found.");
            cy.get(".usa-collection__item").should("not.exist");
        });
    });
});
