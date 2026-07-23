// Covers #1148 "Look up a diplomat and their service record" -- every POCOM
// browse dimension (by-name, by-year, principal officers, chiefs of
// mission) into a person page, both the TEI-biography variant (Secretaries)
// and the computed-record variant (everyone else), plus the URL-retention
// and error-handling acceptance criteria.
//
// baseUrl is http://localhost:8080/exist/apps/hsg-jinks (cypress.config.cjs).
// Override for a remapped host port, e.g.
// `cypress run --config baseUrl=http://localhost:8090/exist/apps/hsg-jinks`.

describe("browsing into a person page", () => {
    it("People hub > Principal Officers and Chiefs of Mission > by name > letter > person", () => {
        cy.visit("departmenthistory/people");
        cy.contains("a", "Principal Officers of the Department of State and Chiefs of Mission").click();
        cy.location("pathname").should("match", /people\/principals-chiefs$/);

        cy.contains("a", "All Principal Officers and Chiefs of Mission, Listed by Name").click();
        cy.location("pathname").should("match", /people\/by-name$/);

        // Scoped to the letter-pill nav: a bare "A" as a global cy.contains
        // selector risks matching an unrelated link elsewhere on the page
        // (e.g. a hidden admin-menu "API Doc..." link, which contains "A").
        cy.get(".usa-button-group").contains("a", "A").click();
        cy.location("pathname").should("match", /people\/by-name\/a$/);
        cy.contains("a", "David Laurence Aaron").click();
        cy.location("pathname").should("match", /people\/aaron-david-laurence$/);
        cy.get("main h1").should("contain.text", "David Laurence Aaron");
    });

    it("by year: browse index > year > person, with the active role highlighted", () => {
        cy.visit("departmenthistory/people/by-year");
        cy.contains("a", "1800").click();
        cy.location("pathname").should("match", /people\/by-year\/1800$/);
        cy.get("main h1").should("contain.text", "1800");
        cy.get(".usa-collection__item--current").should("exist");
    });

    it("principal officers: index > role > officeholder, matching the dedicated Secretaries list", () => {
        cy.visit("departmenthistory/people/principalofficers");
        // "Secretaries" alone is ambiguous: several positions' plural names
        // also start with it (e.g. "Secretaries of Foreign Affairs
        // (Continental Congress)"), which sorts before "Secretaries of
        // State" and would otherwise be matched instead.
        cy.get('a[href$="/principalofficers/secretary"]').click();
        cy.location("pathname").should("match", /principalofficers\/secretary$/);
        cy.get("main ol li").should("have.length", 71);
        cy.contains("a", "Thomas Jefferson").click();
        cy.location("pathname").should("match", /people\/jefferson-thomas$/);
    });

    it("chiefs of mission: by-country index > country > chief, document order preserved", () => {
        cy.visit("departmenthistory/people/chiefsofmission/by-country");
        cy.contains("a", "Japan").click();
        cy.location("pathname").should("match", /chiefsofmission\/japan$/);
        cy.get("main h1").should("contain.text", "Japan");
        cy.get(".usa-collection__heading").first().should("contain.text", "Townsend Harris");
    });

    it("a Secretary's person page shows the TEI biography with the service record beside it", () => {
        cy.visit("departmenthistory/people/madison-james");
        cy.get("main h1").should("contain.text", "Biographies of the Secretaries of State");
        cy.get("main .usa-prose p").should("exist");
        cy.get("aside.usa-card, .usa-card").should("contain.text", "Secretary of State");
    });

    it("a non-Secretary's person page shows the computed record and hiatus notice, no biography", () => {
        cy.visit("departmenthistory/people/aaron-david-laurence");
        cy.get("main h1").should("contain.text", "David Laurence Aaron");
        cy.get(".usa-alert--warning").should("exist");
        cy.get(".usa-collection__heading").should("contain.text", "Organization for Economic Cooperation and Development");
    });
});

describe("URL retention, redirects, and error handling (#1148 acceptance criteria)", () => {
    it("preserves every old URL form", () => {
        const urls = [
            "departmenthistory/people",
            "departmenthistory/people/secretaries",
            "departmenthistory/people/by-name",
            "departmenthistory/people/by-name/a",
            "departmenthistory/people/by-year",
            "departmenthistory/people/by-year/1800",
            "departmenthistory/people/principalofficers",
            "departmenthistory/people/principalofficers/secretary",
            "departmenthistory/people/chiefsofmission",
            "departmenthistory/people/chiefsofmission/by-country",
            "departmenthistory/people/chiefsofmission/by-organization",
            "departmenthistory/people/chiefsofmission/japan",
            "departmenthistory/people/jefferson-thomas",
        ];
        urls.forEach((url) => {
            cy.request(url).its("status").should("eq", 200);
        });
    });

    it("302s a superseded old person id to its canonical id", () => {
        cy.request({ url: "departmenthistory/people/verveer-mellane", followRedirect: false }).then((response) => {
            expect(response.status).to.eq(302);
            expect(response.redirectedToUrl).to.match(/people\/verveer-melanne$/);
        });
    });

    it("404s an unknown letter, year, role, country, and person", () => {
        const unknown = [
            "departmenthistory/people/by-name/xyz",
            "departmenthistory/people/by-year/1700",
            "departmenthistory/people/principalofficers/nosuchrole",
            "departmenthistory/people/chiefsofmission/nosuchplace",
            "departmenthistory/people/nosuchperson",
        ];
        unknown.forEach((url) => {
            cy.request({ url, failOnStatusCode: false }).then((response) => {
                expect(response.status).to.eq(404);
            });
        });
    });

    it("resolves the reserved literal segments, never the {personId} handler", () => {
        // Every literal path segment under /people that a "person id" catch-all
        // could otherwise swallow -- the risk both #1136's and #1137's tickets
        // called out explicitly.
        const literals = ["secretaries", "by-name", "by-year", "principalofficers", "chiefsofmission"];
        literals.forEach((segment) => {
            cy.request(`departmenthistory/people/${segment}`).its("status").should("eq", 200);
        });
    });

    it("chiefsofmission's polymorphic route redirects a positions-principals id to the canonical principal-officers URL", () => {
        cy.request({ url: "departmenthistory/people/chiefsofmission/secretary", followRedirect: false }).then((response) => {
            expect(response.status).to.eq(302);
            expect(response.redirectedToUrl).to.match(/people\/principalofficers\/secretary$/);
        });
    });
});
