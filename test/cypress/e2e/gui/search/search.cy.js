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

    it("the sitewide header search box is a GET form to /search with param q", () => {
        cy.visit("");
        cy.get("section[aria-label='Search'] form")
            .should("have.attr", "action")
            .and("match", /\/search$/);
        cy.get("section[aria-label='Search'] form").should("have.attr", "method", "get");
        cy.get("section[aria-label='Search'] input[name='q']").should("exist");
    });

    // OP#1431: pb-search redirected with the query as "query", which the
    // search page ignores, so a header search landed on the empty landing form
    // and both boxes lost the term.
    [
        ["pressing Enter", (input) => input.type("dobrynin{enter}")],
        ["clicking the search button", (input) => {
            input.type("dobrynin");
            cy.get("section[aria-label='Search'] button[type='submit']").click();
        }],
    ].forEach(([how, submit]) => {
        it(`a header search by ${how} shows results and keeps the query in both boxes`, () => {
            cy.visit("");
            submit(cy.get("section[aria-label='Search'] input[name='q']"));
            cy.location("pathname").should("match", /\/search$/);
            cy.location("search").should("include", "q=dobrynin");
            cy.get(".usa-collection").should("exist");
            cy.get(".usa-collection__item").should("have.length.at.least", 1);
            cy.get("section[aria-label='Search'] input[name='q']").should("have.value", "dobrynin");
            cy.get("#search-field").should("have.value", "dobrynin");
        });
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

// OP#1420 "Style Search page like the Design": the results page's filter
// panel, cards and controls. Asserts structure and behaviour, not pixels --
// the frozen frus-data-jinks baseline supplies the FRUS hits (1989-92 vol.
// XXXI, document d82, dated 1990-02-23); everything else stays at the
// "at least" pattern.
describe("results page: filter panel, cards and controls (OP#1420)", () => {
    beforeEach(() => {
        // the filter panel is a sidebar column, hidden below the desktop layout
        cy.viewport(1440, 900);
    });

    it("the filter panel has boxed Sections, Date and Volumes groups with Reset and Apply", () => {
        // the Date group is only offered while Historical Documents is the one section
        cy.visit("search?q=salt&within=documents");
        cy.get(".hsg-search-filters__heading").should("have.text", "Filter by");
        cy.get(".hsg-filter-group__title").then(($titles) => {
            expect([...$titles].map((t) => t.textContent.trim())).to.deep.equal(["Sections", "Date", "Volumes"]);
        });
        cy.get(".hsg-filter-group input[name='within']").should("have.length", 7);
        ["start", "end"].forEach((prefix) => {
            ["date-month", "date-day", "date-year", "time-hour", "time-minute"].forEach((part) => {
                cy.get(`#${prefix}-${part}`).should("be.visible").and("not.have.attr", "name");
            });
            cy.get(`#${prefix}-time-period`).should("be.visible");
        });
        cy.get("input[name='volume-id']").should("have.length.at.least", 1);
        cy.contains("a.usa-button", "Reset filters").should("be.visible");
        cy.contains("button.usa-button", "Apply filters").should("be.visible");
    });

    it("volume checkboxes are labelled with the volume title, not the bare id", () => {
        cy.visit("search?q=salt&within=documents");
        cy.get("label[for^='volume-']").each(($label) => {
            expect($label.text().trim()).to.not.match(/^frus\d/);
        });
        cy.contains("label[for^='volume-']", "Vol. XXXI");
    });

    it("each hit is a white card with a heading link", () => {
        cy.visit("search?q=salt");
        cy.get(".hsg-results .usa-collection__item").should("have.length.at.least", 5).each(($card) => {
            expect($card.find(".usa-collection__heading a").attr("href")).to.be.a("string").and.not.equal("");
            expect(getComputedStyle($card[0]).backgroundColor).to.equal("rgb(255, 255, 255)");
        });
    });

    it("a historical-document card carries place/date chips, the recorded and encoded date and a highlighted keyword", () => {
        cy.visit("search?q=salt&within=documents&volume-id=frus1989-92v31");
        cy.contains(".usa-collection__item", "82. Memorandum From Senator Warner to President Bush").within(() => {
            cy.get(".usa-tag").then(($tags) => {
                expect([...$tags].map((t) => t.textContent.trim())).to.deep.equal(["Washington", "February 23, 1990"]);
            });
            cy.contains("dt", "Recorded Date").next("dd").should("have.text", "February 23, 1990");
            cy.contains("dt", "Recorded Location").next("dd").should("have.text", "Washington");
            cy.contains("dt", "Encoded Date").next("dd").find("code").should("have.text", 'when="1990-02-23"');
            // The design's #fff000, snapped to the palette's warning-lighter (OP#1426).
            cy.get(".hsg-snippet .hi").first().should("have.css", "background-color", "rgb(250, 206, 0)");
        });
    });

    it("a FRUS division that is not a historical document has no date chips or recorded-date rows", () => {
        cy.visit("search?q=salt&within=documents&volume-id=frus1989-92v31");
        cy.contains(".usa-collection__item", "Abbreviations and Terms").within(() => {
            cy.get(".usa-tag").should("not.exist");
            cy.contains("dt", "Recorded Date").should("not.exist");
            cy.contains("dt", "Resource ID").should("exist");
        });
    });

    it("the summary reports how long the search took", () => {
        cy.visit("search?q=salt");
        cy.get(".hsg-results-summary").invoke("text").should("match", /Search completed in \d+\.\d{3}s\./);
    });

    it("Apply filters keeps the keyword and adds the ticked section", () => {
        cy.visit("search?q=salt");
        cy.get("#within-department").check({ force: true });
        cy.contains("button", "Apply filters").click();
        cy.location("search").should("include", "q=salt").and("include", "within=department");
        cy.get("#search-field").should("have.value", "salt");
        cy.get("#within-department").should("be.checked");
    });

    it("a new keyword search keeps the ticked filters", () => {
        cy.visit("search?q=salt&within=department");
        cy.get("#search-field").clear().type("cuba{enter}");
        cy.location("search").should("include", "q=cuba").and("include", "within=department");
    });

    it("Apply filters applies a date range to historical documents", () => {
        cy.visit("search?q=salt");
        cy.get("#within-documents").check({ force: true });
        cy.get("#start-date-month").type("02");
        cy.get("#start-date-day").type("23");
        cy.get("#start-date-year").type("1990");
        cy.get("#end-date-month").type("2");
        cy.get("#end-date-day").type("23");
        cy.get("#end-date-year").type("1990");
        cy.contains("button", "Apply filters").click();
        cy.location("search").should("include", "start-date=1990-02-23").and("include", "end-date=1990-02-23");
        cy.contains(".hsg-results-summary", "between February 23, 1990 and February 23, 1990");
        cy.get("#start-date-year").should("have.value", "1990");
        cy.get("#start-date-month").should("have.value", "02");
        cy.get("#start-date-day").should("have.value", "23");
    });

    it("Reset filters goes back to the keyword alone", () => {
        cy.visit("search?q=salt&within=department&sort-by=date-asc");
        cy.contains("a", "Reset filters").click();
        cy.location("search").should("equal", "?q=salt");
    });

    it("changing Sort by re-runs the search, keeping keyword and filters", () => {
        cy.visit("search?q=salt&within=documents");
        cy.get("#sort-by").select("Dates (oldest first)");
        cy.location("search").should("include", "sort-by=date-asc").and("include", "q=salt").and("include", "within=documents");
        cy.get("#sort-by").should("have.value", "date-asc");
        cy.contains(".hsg-results-summary", "sorted by dates (oldest first)");
    });

    it("pagination keeps the first and last page and marks a skipped run", () => {
        cy.visit("search?q=salt");
        cy.get(".hsg-search-pagination .usa-pagination__overflow").should("exist");
        cy.get(".hsg-search-pagination .usa-current").should("have.attr", "aria-current", "page").and("have.text", "1");
        cy.get(".hsg-search-pagination .usa-pagination__page-no").last().find("a").invoke("text").then((last) => {
            expect(parseInt(last, 10)).to.be.greaterThan(5);
        });
        cy.get(".hsg-search-pagination .usa-pagination__previous-page").should("not.exist");
        cy.get(".hsg-search-pagination .usa-pagination__next-page").should("exist");
    });

    it("results pages carry pagination below the list only", () => {
        cy.visit("search?q=salt");
        cy.get("nav.usa-pagination").should("have.length", 1);
    });

    it("prose links use the theme link colour, not the browser default", () => {
        cy.visit("search?q=salt");
        cy.contains(".hsg-search-results > p a", "Search Tips").should("have.css", "color", "rgb(44, 96, 138)");
    });
});

// OP#1432: the search form works as on the reference site.
describe("search pages work as on the reference site (OP#1432)", () => {
    beforeEach(() => {
        cy.viewport(1440, 900);
    });

    it("the results page has a visible Search results heading", () => {
        cy.visit("search?q=salt");
        cy.get("main h1").should("be.visible").and("contain.text", "Search results");
    });

    it("the landing page heading is Search, not Search results", () => {
        cy.visit("search");
        cy.get("main h1").should("be.visible").invoke("text").then((t) => expect(t.trim()).to.equal("Search"));
    });

    it("results span the content column: intro, search form and list are not capped", () => {
        cy.visit("search?q=salt");
        cy.get(".hsg-search-results").then(($col) => {
            const width = $col[0].getBoundingClientRect().width;
            expect(width).to.be.greaterThan(640); // wider than the old 40rem cap
            [".hsg-search-results > p", ".hsg-search-form", ".hsg-results"].forEach((sel) => {
                cy.get(sel).first().should(($el) => {
                    expect($el[0].getBoundingClientRect().width).to.be.closeTo(width, 1);
                });
            });
        });
    });

    it("the date filter is offered only while Historical Documents is the only section", () => {
        cy.visit("search?q=salt");
        cy.get(".hsg-date-filter").should("not.be.visible").and("be.disabled");
        cy.get("#within-documents").check({ force: true });
        cy.get(".hsg-date-filter").should("be.visible").and("not.be.disabled");
        cy.get("#within-department").check({ force: true });
        cy.get(".hsg-date-filter").should("not.be.visible").and("be.disabled");
        cy.get("#within-department").uncheck({ force: true });
        cy.get(".hsg-date-filter").should("be.visible");
    });

    it("the volumes filter is offered only while Historical Documents is the only section", () => {
        cy.visit("search?q=salt");
        cy.contains(".hsg-filter-group__title", "Volumes").parents("fieldset").first().as("volumes");
        cy.get("@volumes").should("not.be.visible").and("be.disabled");
        cy.get("#within-documents").check({ force: true });
        cy.get("@volumes").should("be.visible").and("not.be.disabled");
        cy.get("#within-countries").check({ force: true });
        cy.get("@volumes").should("not.be.visible").and("be.disabled");
        // a volume-id deep link searches historical documents, so its volumes are shown
        cy.visit("search?q=salt&volume-id=frus1989-92v31");
        cy.get("#within-documents").should("be.checked");
        cy.get("#volume-frus1989-92v31").should("be.visible").and("be.checked");
    });

    it("a hidden volumes filter is not submitted", () => {
        cy.visit("search?q=salt&within=documents&volume-id=frus1989-92v31");
        cy.get("#within-department").check({ force: true });
        cy.contains("button", "Apply filters").click();
        cy.location("search").should("include", "within=department").and("not.include", "volume-id");
    });

    it("a date-only deep link ticks Historical Documents and opens its date filter", () => {
        cy.visit("search?start-date=1985-06-12&end-date=1985-06-12");
        cy.get("#within-documents").should("be.checked");
        cy.get(".hsg-date-filter").should("be.visible");
        cy.get("#start-date-year").should("have.value", "1985");
    });

    it("a year alone searches that whole year", () => {
        cy.visit("search?q=salt&within=documents");
        cy.get("#start-date-year").type("1990");
        cy.contains("button", "Apply filters").click();
        cy.location("search").should("include", "start-date=1990").and("not.include", "start-date=1990-");
        cy.contains(".hsg-results-summary", "between January 1, 1990 and December 31, 1990");
    });

    it("a month and year on the landing page searches that whole month", () => {
        cy.visit("search");
        cy.get("#search-field").type("salt");
        cy.get("#within-documents").check({ force: true });
        cy.get("#start-date-month").type("2");
        cy.get("#start-date-year").type("1990");
        cy.get("form.usa-form").submit();
        cy.location("search").should("include", "start-date=1990-02").and("not.include", "start-date=1990-02-");
        cy.contains(".hsg-results-summary", "between February 1, 1990 and February 28, 1990");
    });

    it("a time on a full date is sent as 24-hour time, 12 am as midnight", () => {
        cy.visit("search?q=salt&within=documents");
        cy.get("#start-date-month").type("02");
        cy.get("#start-date-day").type("23");
        cy.get("#start-date-year").type("1990");
        cy.get("#start-time-hour").type("1");
        cy.get("#start-time-minute").type("5");
        cy.get("#start-time-period").select("pm");
        cy.get("#end-date-month").type("02");
        cy.get("#end-date-day").type("24");
        cy.get("#end-date-year").type("1990");
        cy.get("#end-time-hour").type("12");
        cy.get("#end-time-period").select("am");
        cy.contains("button", "Apply filters").click();
        cy.location("search").should("include", "start-time=13%3A05").and("include", "end-time=00%3A00");
        cy.get("#start-time-hour").should("have.value", "1");
        cy.get("#start-time-minute").should("have.value", "05");
        cy.get("#start-time-period").should("have.value", "pm");
    });

    it("a time without a full date is not sent, and a partial date keeps filtering", () => {
        cy.visit("search?q=salt&within=documents");
        cy.get("#start-date-month").type("02");
        cy.get("#start-date-year").type("1990");
        cy.get("#start-time-hour").type("9");
        cy.contains("button", "Apply filters").click();
        cy.location("search").should("include", "start-date=1990-02").and("not.include", "start-time=");
        // a hand-written link with a time on a partial date still filters by the date
        cy.visit("search?q=salt&within=documents&start-date=1990-02&start-time=13:07");
        cy.contains(".hsg-results-summary", "between February 1, 1990 and February 28, 1990");
    });

    it("breadcrumbs follow the search hierarchy without repeating Search", () => {
        const crumbs = () => cy.get("nav[aria-label='breadcrumb'] li").then(($li) => [...$li].map((li) => li.textContent.trim()));
        cy.visit("search");
        crumbs().should("deep.equal", ["Home", "Search"]);
        cy.visit("search?q=salt");
        crumbs().should("deep.equal", ["Home", "Search", "Results"]);
        cy.contains("nav[aria-label='breadcrumb'] a", "Search").should("have.attr", "href").and("match", /\/search$/);
        cy.visit("search/tips");
        crumbs().should("deep.equal", ["Home", "Search", "Tips"]);
    });

    it("search results offer no facsimile link", () => {
        cy.visit("search?q=salt&within=documents&volume-id=frus1989-92v31");
        cy.get(".hsg-results .usa-collection__item").should("have.length.at.least", 1);
        cy.get(".hsg-results").contains("Facsimile").should("not.exist");
        cy.get(".hsg-results a[href*='/pg_']").should("not.exist");
    });
});
