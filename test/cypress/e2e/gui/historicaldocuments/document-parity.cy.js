// Acceptance criteria for OP#520 "Document rendering shows all relevant data":
// the four FRUS page types show every piece of content the reference site
// (history.state.gov, mirrored by hsg-shell) shows for them. Backed by a
// whitespace-insensitive text diff of the rendered pages against the local
// hsg-shell mirror (2026-08-19): zero reference content chunks are missing on
// any of the four page types, and the chapter page is a superset (it renders
// each entry's full source note). This spec pins the per-page data inventory
// so parity regressions surface.
//
// frus1981-88v05 is part of the frozen baseline data, so exact assertions on
// its counts and strings are fine. Out of scope, tracked elsewhere: citation
// <head> metadata (OP#629, SEO) and page-image (pg_*) views (OP#1315).

const volume = "historicaldocuments/frus1981-88v05";

describe("volume landing shows all relevant data", () => {
    beforeEach(() => cy.visit(volume));

    it("shows the complete volume title", () => {
        cy.get("main", { timeout: 15000 })
            .should("contain.text", "Foreign Relations of the United States, 1981–1988")
            .and("contain.text", "Soviet Union, March 1985–October 1986");
    });

    it("lists every division in the TOC with its document range", () => {
        // 1 compilation + 6 chapters carry document ranges.
        cy.get("main .hsg-frus__toc a", { timeout: 15000 }).should("have.length.at.least", 7);
        cy.get("main .hsg-frus__toc").should("contain.text", "Documents 1–309")
            .and("contain.text", "Documents 1–50")
            .and("contain.text", "Documents 267–309");
    });
});

describe("compilation page shows all relevant data", () => {
    beforeEach(() => cy.visit(`${volume}/comp`));

    it("shows the compilation title and a Contents heading", () => {
        cy.get("main", { timeout: 15000 })
            .should("contain.text", "Soviet Union, March 1985–October 1986")
            .and("contain.text", "Contents");
    });

    it("lists all six chapters with their document ranges", () => {
        cy.get("main .hsg-frus__division-entry", { timeout: 15000 }).should("have.length", 6);
        cy.get("main .hsg-frus__doclist")
            .should("contain.text", "Documents 1–50")
            .and("contain.text", "Documents 267–309");
    });
});

describe("chapter page shows all relevant data", () => {
    beforeEach(() => cy.visit(`${volume}/ch1`));

    it("lists all 50 documents, 30 per page (#1079)", () => {
        cy.get("main .hsg-frus__doc-entry", { timeout: 15000 }).should("have.length", 30);
        cy.visit(`${volume}/ch1?start=31`);
        cy.get("main .hsg-frus__doc-entry", { timeout: 15000 }).should("have.length", 20)
            .first().should("contain.text", "31.");
    });

    it("gives each entry number, linked title, dateline and source note", () => {
        cy.get("main .hsg-frus__doc-entry", { timeout: 15000 }).first().within(() => {
            cy.contains("Letter From President Reagan to Soviet General Secretary Gorbachev")
                .should("have.attr", "href").and("match", /\/d1$/);
            cy.root().should("contain.text", "Washington")
                .and("contain.text", "March 11, 1985")
                .and("contain.text", "Source:")
                .and("contain.text", "Reagan Library");
        });
    });

    it("shows document summaries where the data carries them", () => {
        // d2's summary, shown by the reference too.
        cy.get("main", { timeout: 15000 })
            .should("contain.text", "In a March 11 covering memorandum");
    });
});

describe("document page shows all relevant data", () => {
    beforeEach(() => cy.visit(`${volume}/d1`));

    it("shows number, title, dateline and salutation", () => {
        // Two single-line phrases: contain.text is whitespace-sensitive
        // and the TEI's line wrapping splits the document title.
        cy.get("main", { timeout: 15000 })
            .should("contain.text", "Letter From President Reagan to")
            .and("contain.text", "Soviet General Secretary Gorbachev")
            .and("contain.text", "Washington")
            .and("contain.text", "March 11, 1985")
            .and("contain.text", "Dear Mr. General Secretary");
    });

    it("shows the source note", () => {
        cy.get("main", { timeout: 15000 })
            .should("contain.text", "Source:")
            .and("contain.text", "Reagan Library, Executive Secretariat");
    });

    it("renders the footnote apparatus with backlinks", () => {
        cy.get("main .footnote-ref", { timeout: 15000 }).should("have.length", 2);
        cy.get("main .footnotes").should("exist");
        cy.get("main .footnote-backlink").should("have.length", 2);
    });

    it("mounts the register lists and the volume TOC beside the text", () => {
        cy.get("aside .hsg-frus__register-list", { timeout: 15000 }).should("have.length", 2);
        cy.get("aside ul.usa-sidenav").should("exist");
    });

    it("offers previous/next navigation", () => {
        cy.get("main .hsg-frus__pager a", { timeout: 15000 }).should("have.length.at.least", 1)
            .last().should("have.attr", "href").and("match", /\/d2$/);
    });
});
