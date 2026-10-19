// Division listing pages (OP#1479, Figma node 4290-19925): chapters,
// compilations and subchapters, rendered by hsg:division-listing() in
// modules/templates/hsg.xqm through templates/pages/volume/division-listing.html.
// The volume title as an overline, the division title and notes, pagination
// above and below, one card per entry, and no right-hand sidebar.

const CHAPTER = "historicaldocuments/frus1981-88v05/ch1";

describe("division listing page", () => {
    beforeEach(() => cy.visit(CHAPTER));

    it("links the volume title above the division title", () => {
        cy.get(".hsg-frus__overline a")
            .should("contain.text", "Foreign Relations of the United States, 1981–1988, Volume V")
            .and("have.attr", "href").and("match", /\/historicaldocuments\/frus1981-88v05$/);
        cy.get("h1.hsg-frus__division-title").should("contain.text", "Gorbachev");
    });

    it("has the volume table of contents but no right sidebar", () => {
        cy.get("pb-page > aside.before .usa-sidenav").should("be.visible");
        cy.get("pb-page > aside.after").should("not.be.visible");
    });

    it("pages the documents with USWDS pagination above and below the list", () => {
        cy.get(".hsg-frus__pagination").should("have.length", 2);
        cy.get(".hsg-frus__pagination").first().within(() => {
            cy.get(".usa-pagination__button.usa-current").should("have.text", "1").and("have.attr", "aria-current", "page");
            cy.get(".usa-pagination__next-page").should("have.attr", "href", "?start=31");
        });
        cy.get(".hsg-frus__pagination").first().should("have.css", "justify-content", "flex-end");
        cy.get(".hsg-frus__pagination").last().should("have.css", "justify-content", "center");
    });

    it("gives each document a card with its title, source, location and date", () => {
        cy.get(".hsg-frus__doc-entry").first().within(() => {
            cy.get(".hsg-frus__doc-title a").should("have.attr", "href").and("match", /\/d1$/);
            cy.get(".hsg-frus__doc-meta dt").then(($dts) => {
                expect([...$dts].map((dt) => dt.textContent)).to.deep.equal(["Source", "Location", "Date"]);
            });
            cy.get(".hsg-frus__doc-meta").should("contain.text", "Washington").and("contain.text", "March 11, 1985");
        });
        cy.get(".hsg-frus__doc-entry").first().should("have.css", "background-color", "rgb(255, 255, 255)");
    });

    it("links each document's first page scan", () => {
        cy.get(".hsg-frus__doc-entry").first().find("a.hsg-frus__facsimile")
            .should("contain.text", "Facsimile Page")
            .invoke("attr", "href")
            .then((href) => {
                expect(href).to.match(/\/frus1981-88v05\/pg_\d+$/);
                // Root-relative: cy.request would resolve it against baseUrl.
                cy.location("origin").then((origin) => cy.request(origin + href)).its("status").should("eq", 200);
            });
    });
});

describe("division listing page without volume page scans", () => {
    // The microfiche supplement's documents number their pages on their own
    // ("eta_d1-1"), so a pg_{n} link would open an unrelated volume page.
    it("shows no facsimile link", () => {
        cy.visit("historicaldocuments/frus1958-60v05mSupp/ch1");
        cy.get(".hsg-frus__doc-entry").should("have.length", 30);
        cy.get("a.hsg-frus__facsimile").should("not.exist");
    });
});

describe("subchapter listing", () => {
    // A subchapter holds documents like a chapter; it used to fall through to
    // the prose rendering, which showed nothing but the prev/next links.
    it("lists its documents", () => {
        cy.visit("historicaldocuments/frus1861/subch1");
        cy.get("h1.hsg-frus__division-title").should("contain.text", "Case of the Perthshire");
        cy.get(".hsg-frus__doc-entry").should("have.length", 5);
        cy.get(".hsg-frus__doc-entry .hsg-frus__doc-title a").first()
            .should("have.attr", "href").and("match", /\/frus1861\/d106$/);
        cy.get(".hsg-frus__pagination").should("not.exist");
    });
});

describe("pending chapter listing", () => {
    it("shows the chapter's publication notice below its title", () => {
        cy.visit("historicaldocuments/frus1977-80v27/ch9");
        cy.get(".hsg-frus__division-notes")
            .should("contain.text", "will be published once all documents have been cleared")
            .find("a").should("have.attr", "href").and("match", /\/frus1977-80v27\/about-the-digital-edition$/);
    });
});
