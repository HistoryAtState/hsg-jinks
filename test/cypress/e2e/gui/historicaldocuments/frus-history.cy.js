// The FRUS History subsection (OP#1294): the "Toward 'Thorough, Accurate,
// and Reliable'" monograph landing and division pages, the documents /
// research / events collections and the Appendix A production chart, all
// backed by the frus-history data package. Reference parity with hsg-shell's
// pages/historicaldocuments/frus-history/*.
//
// Every count of data-derived content uses a lower bound per CLAUDE.md
// "Cypress assertions on data-package counts": frus-history's collections
// are slow-moving (monograph frozen since 2015) but the package keeps
// getting releases. Write-time values: 63 documents, 28 authored articles,
// 13 events, 29 monograph TOC entries.

const SECTION = "historicaldocuments/frus-history";

describe("the FRUS History landing page", () => {
    beforeEach(() => cy.visit(SECTION));

    it("shows the monograph title, editors and edition info", () => {
        cy.get("main h1", { timeout: 15000 }).should(
            "contain.text",
            "Foreign Relations of the United States"
        );
        cy.get("main dl dd")
            .should("have.length.at.least", 3)
            .and("contain.text", "William B. McAllister");
        cy.get("main").should("contain.text", "Office of the Historian, U.S. Department of State");
    });

    it("renders the full book TOC with links into the division pages", () => {
        cy.get("main .toc-inner a.toc-link", { timeout: 15000 }).should(
            "have.length.at.least",
            20
        );
        cy.get("main a#toc-chapter-1")
            .should("have.attr", "href")
            .and("match", /historicaldocuments\/frus-history\/chapter-1$/);
    });

    it("offers the ebook downloads derived from the monograph's relatedItems", () => {
        cy.get("aside.before #downloads a[href$='frus-history.epub']", { timeout: 15000 }).should(
            "exist"
        );
        cy.get("aside.before #downloads").should("contain.text", "EPUB");
        cy.get("aside.before #downloads a[href$='frus-history.pdf']").should("exist");
    });

    it("shows the FRUS History Resources panel with counted rollup links", () => {
        cy.get("aside.before #sections", { timeout: 15000 })
            .should("contain.text", "All Documents")
            .and("contain.text", "All Articles")
            .and("contain.text", "All events");
    });
});

describe("a monograph division page", () => {
    it("renders a chapter with prev/next and a highlighted TOC entry", () => {
        cy.visit(`${SECTION}/chapter-1`);
        cy.get("main h1", { timeout: 15000 }).should("contain.text", "Chapter 1");
        cy.get("main .usa-pagination__previous-page").should("exist");
        cy.get("main .usa-pagination__next-page").should("exist");
        cy.get("aside.before .usa-sidenav a.usa-current").should("contain.text", "Chapter 1");
    });

    it("renders a part as a contents list of its chapters", () => {
        cy.visit(`${SECTION}/part-1`);
        cy.get("main h1", { timeout: 15000 }).should("contain.text", "Part I");
        cy.get("main ul.usa-list a").should("have.length.at.least", 4);
    });

    it("returns 404 for an unknown section id", () => {
        cy.request({ url: `${SECTION}/no-such-section`, failOnStatusCode: false })
            .its("status")
            .should("eq", 404);
    });
});

describe("the documents list", () => {
    it("groups by posting batch by default, with the sort toggle", () => {
        cy.visit(`${SECTION}/documents`);
        cy.get("main h1", { timeout: 15000 }).should("have.text", "Documents");
        cy.get("main").should("contain.text", "sorted by date posted");
        cy.get("main ol a").should("have.length.at.least", 50);
        cy.get("main a[href='?sort-by=created']").should("exist");
    });

    it("sorts flat by document date with ?sort-by=created", () => {
        cy.visit(`${SECTION}/documents?sort-by=created`);
        cy.get("main ol > li", { timeout: 15000 }).should("have.length.at.least", 50);
        cy.get("main").should("contain.text", "sorted by document date");
        cy.get("main a[href='?sort-by=posted']").should("exist");
    });
});

describe("a document page", () => {
    it("renders the document with its source note and sidebar highlight", () => {
        cy.visit(`${SECTION}/documents/1957-03-21-kennan-to-leopold`);
        cy.get("main h1", { timeout: 15000 }).should(
            "contain.text",
            "Correspondence Between Richard Leopold and George Kennan"
        );
        cy.get("main").should(
            "contain.text",
            "A scan of the original document is available for download"
        );
        cy.get("aside.before .usa-sidenav a.usa-current").should("contain.text", "Leopold-Kennan");
        cy.get("aside.before .usa-sidenav a").should("have.length.at.least", 50);
    });

    it("returns 404 for an unknown document id", () => {
        cy.request({ url: `${SECTION}/documents/no-such-document`, failOnStatusCode: false })
            .its("status")
            .should("eq", 404);
    });
});

describe("the research list", () => {
    it("lists the authored sesquicentennial posts, most recent first", () => {
        cy.visit(`${SECTION}/research`);
        cy.get("main .article-container", { timeout: 15000 }).should("have.length.at.least", 25);
        cy.get("main .article-container h3 a")
            .first()
            .should("have.attr", "href")
            .and("match", /frus-history\/research\//);
        cy.get("main .article-container").first().should("contain.text", "By ");
    });
});

describe("an article page", () => {
    it("renders the byline with the Released date and sidebar highlight", () => {
        cy.visit(`${SECTION}/research/the-first-volume`);
        cy.get("main h1", { timeout: 15000 }).should(
            "contain.text",
            "Exploring the History of the First"
        );
        cy.get("main h4").should("contain.text", "Released");
        cy.get("aside.before .usa-sidenav a.usa-current").should("exist");
    });

    it("returns 404 for an unknown article id", () => {
        cy.request({ url: `${SECTION}/research/no-such-article`, failOnStatusCode: false })
            .its("status")
            .should("eq", 404);
    });
});

describe("the events page", () => {
    it("shows Recent Events with one block per event", () => {
        cy.visit(`${SECTION}/events`);
        cy.get("main h1", { timeout: 15000 }).should("contain.text", "Recent Events");
        cy.get("main div.frus-history-event").should("have.length.at.least", 10);
    });
});

describe("the Appendix A chart page", () => {
    it("serves the graph target, dataset toggles and highlighted TOC entry", () => {
        cy.visit(`${SECTION}/appendix-a`);
        cy.get("main #graph", { timeout: 15000 }).should("exist");
        cy.get("main #graph-fieldset input[type=checkbox]").should("have.length", 3);
        cy.get("aside.before .usa-sidenav a.usa-current").should("contain.text", "Appendix A");
    });
});
