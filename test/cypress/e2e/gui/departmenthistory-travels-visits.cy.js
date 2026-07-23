// Covers #1150 "Retrieve travel and visit data as tables" -- the
// person-or-country polymorphic travels listings and the year-or-country
// polymorphic visits listing, plus the URL-retention and error-handling
// acceptance criteria shared with #1142-#1145.
//
// baseUrl is http://localhost:8080/exist/apps/hsg-jinks (cypress.config.cjs).
// Override for a remapped host port, e.g.
// `cypress run --config baseUrl=http://localhost:8090/exist/apps/hsg-jinks`.

describe("travels: browse by president/secretary, and by destination", () => {
    it("president index > president > trip table, Country column shown (Name suppressed)", () => {
        cy.visit("departmenthistory/travels/president");
        cy.contains("a", "Richard M. Nixon").click();
        cy.location("pathname").should("match", /travels\/president\/nixon-richard-m$/);
        cy.get("main h1").should("contain.text", "Richard M. Nixon");
        cy.get("table thead th").should("not.contain.text", "Name");
        cy.get("table thead th").should("contain.text", "Country");
        cy.get("table tbody tr").first().should("contain.text", "Belgium");
    });

    it("president index > destination > trip table, Name column shown (Country suppressed), hiatus notice present", () => {
        cy.visit("departmenthistory/travels/president");
        cy.contains("a", "Belgium").click();
        cy.location("pathname").should("match", /travels\/president\/belgium$/);
        cy.get("main h1").should("contain.text", "Belgium");
        cy.get("table thead th").should("contain.text", "Name");
        cy.get("table thead th").should("not.contain.text", "Country");
        cy.get(".usa-alert--warning").should("exist");
    });

    it("a past administration's own listing does not carry the hiatus notice", () => {
        cy.visit("departmenthistory/travels/president/nixon-richard-m");
        cy.get(".usa-alert--warning").should("not.exist");
    });

    it("secretary index > secretary > trip table", () => {
        cy.visit("departmenthistory/travels/secretary");
        cy.contains("a", "John Forbes Kerry").click();
        cy.location("pathname").should("match", /travels\/secretary\/kerry-john-forbes$/);
        cy.get("main h1").should("contain.text", "John Forbes Kerry");
    });

    it("trip tables are responsive (usa-table--stacked) and stay in chronological order", () => {
        cy.visit("departmenthistory/travels/president/nixon-richard-m");
        cy.get("table").should("have.class", "usa-table--stacked");
        cy.get("table tbody tr td[data-label='Date']").then(($cells) => {
            // Cross-month ranges (e.g. "February 28-March 2, 1969") put the
            // year only once, at the end -- take the leading "Month Day" and
            // the trailing year separately rather than splitting on the dash,
            // which would leave the first half with no year to parse.
            const dates = Cypress._.map($cells, (td) => {
                const text = td.textContent.trim();
                const monthDay = text.match(/^([A-Za-z]+ \d{1,2})/)[1];
                const year = text.match(/(\d{4})\s*$/)[1];
                return new Date(`${monthDay}, ${year}`);
            });
            const sorted = [...dates].sort((a, b) => a - b);
            expect(dates.map((d) => d.getTime())).to.deep.equal(sorted.map((d) => d.getTime()));
        });
    });
});

describe("visits: browse by year and by country", () => {
    it("year index > year > visit table, From column shown", () => {
        cy.visit("departmenthistory/visits");
        cy.contains("a", "1970").click();
        cy.location("pathname").should("match", /visits\/1970$/);
        cy.get("main h1").should("contain.text", "1970");
        cy.get("table thead th").should("contain.text", "From");
        cy.get("table tbody tr").first().should("contain.text", "Harold Wilson");
    });

    it("country index > country > visit table, From column suppressed", () => {
        cy.visit("departmenthistory/visits");
        cy.contains("a", "United Kingdom").click();
        cy.location("pathname").should("match", /visits\/united-kingdom$/);
        cy.get("main h1").should("contain.text", "United Kingdom");
        cy.get("table thead th").should("not.contain.text", "From");
    });

    it("the visits index 'Last updated' line is derived text, not a fixed date", () => {
        cy.visit("departmenthistory/visits");
        cy.contains("em", /Last updated, [A-Z][a-z]+ \d{4}\./).should("exist");
    });
});

describe("URL retention and error handling (#1150 acceptance criteria)", () => {
    it("preserves every old URL form", () => {
        const urls = [
            "departmenthistory/travels",
            "departmenthistory/travels/president",
            "departmenthistory/travels/president/nixon-richard-m",
            "departmenthistory/travels/president/belgium",
            "departmenthistory/travels/secretary",
            "departmenthistory/travels/secretary/kerry-john-forbes",
            "departmenthistory/visits",
            "departmenthistory/visits/1970",
            "departmenthistory/visits/united-kingdom",
        ];
        urls.forEach((url) => {
            cy.request(url).its("status").should("eq", 200);
        });
    });

    it("404s an unknown id on all three listing routes", () => {
        const unknown = [
            "departmenthistory/travels/president/nosuchid",
            "departmenthistory/travels/secretary/nosuchid",
            "departmenthistory/visits/nosuchcountry",
            "departmenthistory/visits/1500",
        ];
        unknown.forEach((url) => {
            cy.request({ url, failOnStatusCode: false }).then((response) => {
                expect(response.status).to.eq(404);
            });
        });
    });

    it("resolves the reserved literal segments (president/secretary), never the {personOrCountryId} handler", () => {
        cy.request("departmenthistory/travels/president").its("status").should("eq", 200);
        cy.request("departmenthistory/travels/secretary").its("status").should("eq", 200);
    });
});

// The secretary travels route's old-id 302 reuses #1141's
// dh:person-canonical-id-for-old-id unchanged (already covered end-to-end by
// that ticket's own person-page redirect test) -- not re-tested here, since
// no secretary in the current data has both a POCOM old-id and a travel file
// to exercise the /travels/secretary/{oldId} path specifically.
