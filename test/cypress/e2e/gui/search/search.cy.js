// Covers OP#1184 "Search the whole site by keyword and refine the results"
// and OP#1185 "Filter FRUS documents by date via a (legacy) deep link" --
// the two acceptance-criteria user stories under epic OP#1102 (Render HSG
// search). Verified against this worktree's own devcontainer, whose data
// packages were freshly installed for this epic (see
// doc/epic-1102-search-plan.md) rather than the frozen baseline other
// worktrees currently run -- counts use the "at least" pattern per
// CLAUDE.md regardless, since these packages are append-only upstream.
//
// baseUrl is http://localhost:8080/exist/apps/hsg-jinks (cypress.config.cjs).
// Override for a remapped host port, e.g.
// `cypress run --config baseUrl=http://localhost:8097/exist/apps/hsg-jinks`.

describe("landing vs. results dispatch (OP#1184 AC)", () => {
    it("no query params shows the landing form, not results", () => {
        cy.visit("search");
        cy.get(".usa-search input[name='q']").should("exist");
        cy.get(".usa-collection").should("not.exist");
    });

    it("a non-empty q shows results, not the landing form", () => {
        cy.visit("search?q=cuba");
        cy.get(".usa-collection").should("exist");
        cy.get(".usa-collection__item").should("have.length.at.least", 5);
    });

    it("a whitespace-only q does NOT count as present -- still shows the landing form", () => {
        cy.visit("search?q=%20%20");
        cy.get(".usa-search input[name='q']").should("exist");
        cy.get(".usa-collection").should("not.exist");
    });

    it("start-date alone (no q) triggers the results view", () => {
        cy.visit("search?within=documents&start-date=1985-06-12&end-date=1985-06-12");
        cy.get(".usa-collection").should("exist");
    });
});

describe("keyword search and refinement (OP#1184)", () => {
    it("searches across the entire site by default, mixing content types", () => {
        cy.visit("search?q=cuba");
        cy.contains(".usa-prose", "across the entire Office of the Historian website");
        cy.get(".usa-collection__item a[href*='/departmenthistory/']").should("exist");
    });

    it("refines by section via the within filter", () => {
        cy.visit("search?q=cuba&within=department");
        cy.contains(".usa-prose", "within department");
        cy.get(".usa-collection__item a").each(($a) => {
            expect($a.attr("href")).to.match(/\/(departmenthistory)\//);
        });
    });

    it("re-sorts by date", () => {
        cy.visit("search?q=cuba&sort-by=date-asc");
        cy.contains(".usa-prose", "sorted by dates (oldest first)");
    });

    it("pages through results, preserving the query", () => {
        cy.visit("search?q=cuba");
        cy.get("a.usa-pagination__next-page").first().click();
        cy.location("search").should("include", "start=11");
        cy.location("search").should("include", "q=cuba");
    });

    it("legacy order-by=date maps to sort-by=date-asc", () => {
        cy.visit("search?q=cuba&order-by=date");
        cy.contains(".usa-prose", "sorted by dates (oldest first)");
    });

    it("zero hits still returns 200 with a results page, not an error", () => {
        cy.request("search?q=zzznonexistentqueryzzz").its("status").should("eq", 200);
        cy.visit("search?q=zzznonexistentqueryzzz");
        cy.contains("No results were found");
    });

    it("an unknown within value is a 200 with (functionally) no matching section, not a 400", () => {
        cy.request("search?q=cuba&within=not-a-real-section").its("status").should("eq", 200);
    });

    it("malformed Lucene query syntax is rejected with the 400 invalid-search page (OP#1273 decision; previously swallowed to a 200 zero-results page)", () => {
        cy.request({ url: "search?q=" + encodeURIComponent("cuba AND"), failOnStatusCode: false })
            .its("status").should("eq", 400);
        cy.visit({ url: "search?q=" + encodeURIComponent("cuba AND"), failOnStatusCode: false });
        cy.contains("Invalid search query");
    });
});

describe("query guard (OP#1179 / OP#1184 AC)", () => {
    it("rejects a SQL-injection-shaped q with HTTP 400", () => {
        cy.request({ url: "search?q=" + encodeURIComponent("1 UNION SELECT null,null,null"), failOnStatusCode: false })
            .its("status").should("eq", 400);
    });

    it("does not false-positive on ordinary prose containing 'union select'", () => {
        cy.request("search?q=" + encodeURIComponent("European Union Select Committee")).its("status").should("eq", 200);
    });

    it("rejects an oversized q with HTTP 400", () => {
        const longQuery = "a".repeat(1001);
        cy.request({ url: "search?q=" + longQuery, failOnStatusCode: false }).its("status").should("eq", 400);
    });
});

describe("search tips and routing (OP#1182)", () => {
    it("/search/tips returns 200 with the documented examples", () => {
        cy.visit("search/tips");
        cy.get("main h1").should("contain.text", "Search Tips");
        cy.contains("a", "peace").should("have.attr", "href").and("include", "within=department");
    });

    it("/search/anything-else 404s", () => {
        cy.request({ url: "search/anything-else", failOnStatusCode: false }).its("status").should("eq", 404);
    });

    it("the sitewide header search box posts to /search with param q", () => {
        cy.visit("");
        cy.get("pb-search").first().should("have.attr", "action").and("include", "/search");
        cy.get("pb-search").first().should("have.attr", "name", "q");
    });
});

// Date deep-links work against the frus-v2 data via the division-level
// index fields added in hsg-jinks-data (frus-search-date-min/max; OP#1316).
describe("legacy FRUS date deep link (OP#1185)", () => {
    it("a full legacy deep link (q + within=documents + date range + sort-by) lands directly on filtered results", () => {
        // Uses dobrynin/June 1985 (this worktree's one-volume sample data,
        // frus1981-88v05) rather than hsg-shell's own doc-example (Cuba,
        // October 1962) -- the full multi-volume FRUS corpus that example
        // was written against isn't installed here (see
        // doc/epic-1102-search-plan.md's frus-data-jinks discussion); the
        // legacy-parameter-combination dispatch behavior under test is
        // identical either way.
        cy.visit("search?q=dobrynin&within=documents&start-date=1985-06-12&end-date=1985-06-12&sort-by=date-asc");
        cy.get(".usa-search input[name='q']").should("have.value", "dobrynin");
        cy.contains(".usa-prose", "within documents");
        cy.get(".usa-collection__item").should("have.length.at.least", 1);
    });

    it("start-date without within is treated as within=documents (frus-dates compatibility)", () => {
        cy.visit("search?start-date=1985-06-12&end-date=1985-06-12");
        cy.contains(".usa-prose", "within documents");
    });

    it("sort-by=relevance with no q silently becomes date-asc", () => {
        cy.visit("search?within=documents&start-date=1985-06-12&end-date=1985-06-12&sort-by=relevance");
        cy.contains(".usa-prose", "sorted by dates (oldest first)");
    });

    it("an exact single-day range returns only documents dated that day", () => {
        cy.visit("search?within=documents&start-date=1985-06-12&end-date=1985-06-12&sort-by=date-asc");
        cy.get(".usa-collection__item").should("have.length.at.least", 1);
        cy.contains(".usa-prose", "between June 12, 1985 and June 12, 1985");
    });
});
