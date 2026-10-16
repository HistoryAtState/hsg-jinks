// FRUS volume front- and back-matter division pages (OP#1306), served by the
// generic volume-interior route; reference parity with e.g.
// https://history.state.gov/historicaldocuments/frus1981-88v05/persons
//
// frus1981-88v05 is part of the frozen baseline data, so its division
// vocabulary is stable; per-division content asserts a fixed phrase from
// each division's opening.

const volume = "historicaldocuments/frus1981-88v05";

describe("volume front- and back-matter pages", () => {
    // Every front/back-matter division of the volume answers 200; "toc"
    // regressed once (the volume root's <divGen xml:id="toc"/> placeholder
    // collided with the division id). "index" is left out: rendering it is
    // slow (OP#1470), and the render test below visits it once.
    ["toc", "preface", "persons", "terms", "sources",
        "abouttheseries", "pressrelease", "app"].forEach((division) => {
        it(`serves the ${division} division`, () => {
            cy.request(`${volume}/${division}`).its("status").should("eq", 200);
        });
    });

    it("renders the persons register with its entries", () => {
        cy.visit(`${volume}/persons`);
        // Single-line phrase: contain.text is whitespace-sensitive and the
        // TEI's line wrapping splits names.
        cy.get("main", { timeout: 15000 })
            .should("contain.text", "Persons")
            .and("contain.text", "Lieutenant General, USAF");
    });

    it("renders the terms register with its entries", () => {
        cy.visit(`${volume}/terms`);
        cy.get("main", { timeout: 15000 })
            .should("contain.text", "Abbreviations and Terms")
            .and("contain.text", "Anti-Ballistic Missile");
    });

    it("renders the printed table of contents", () => {
        cy.visit(`${volume}/toc`);
        cy.get("main", { timeout: 15000 })
            .should("contain.text", "Contents")
            .and("contain.text", "About the Series");
    });

    // The only test that renders the index (OP#1470: ~10 s locally, close to
    // 30 s on CI runners), so it also carries list-dateline-design's
    // structural check: register entries are their own blocks, never divs
    // inside a ul. One retry and a longer response timeout instead of three
    // attempts at the default 30 s.
    it("renders the back-matter index", { retries: 1, responseTimeout: 45000 }, () => {
        cy.visit(`${volume}/index`);
        cy.get("main", { timeout: 45000 })
            .should("contain.text", "Index")
            .and("contain.text", "Able Archer");
        cy.get("main div.list").should("have.length.at.least", 100);
        cy.get("main ul > div").should("not.exist");
    });

    it("gives interior divisions the volume title and a prev/next pager", () => {
        cy.visit(`${volume}/preface`);
        cy.get("main h2", { timeout: 15000 })
            .should("contain.text", "Foreign Relations of the United States");
        cy.get("main .hsg-frus__prose", { timeout: 15000 }).should("exist");
    });
});
