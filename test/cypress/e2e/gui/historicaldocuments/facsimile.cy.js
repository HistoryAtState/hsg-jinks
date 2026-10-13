// Page-image deep links and the IIIF facsimile viewer (OP#1335).
//
// hsg-shell served every printed page at
// /historicaldocuments/{volume}/pg_{n} in an OpenSeadragon IIIF viewer, and
// the "[Page N]" links in documents point there; hsg-jinks 404ed the route
// and its pb-facs-link webcomponents had no viewer to talk to. The fix
// renders the links with IIIF Image API identifiers against the production
// image server (ci.history.state.gov), adds a pb-facsimile panel to the
// interior pages and serves the legacy pg_* route from a standalone
// facsimile page.
//
// The viewer-loads assertions depend on the external image server: the
// pb-facsimile component sets its "loaded" attribute once the page scans
// arrive on its channel, and the OpenSeadragon canvas needs the actual
// info.json from ci.history.state.gov. frus1981-88v05 is a published,
// frozen volume, so exact page/image numbers are safe to assert.

const VOLUME = "frus1981-88v05";
const VOLUME_TITLE_START = "Foreign Relations of the United States, 1981–1988, Volume V";
const IIIF_BASE = "https://ci.history.state.gov/iiif/2/";

describe("pg_* facsimile page", () => {
    beforeEach(() => cy.visit(`historicaldocuments/${VOLUME}/pg_316`));

    it("shows the volume title as navigation heading", () => {
        cy.get("main h2.hsg-navigation-title")
            .invoke("text")
            .should("contain", VOLUME_TITLE_START);
    });

    it("has the reference breadcrumb trail ending in the page crumb", () => {
        cy.get('nav[aria-label="breadcrumb"] li').should("have.length", 4);
        cy.get('nav[aria-label="breadcrumb"] li[aria-current="page"]')
            .should("contain.text", "Page 316");
        // the volume crumb links back to the volume landing page
        cy.get('nav[aria-label="breadcrumb"] li a')
            .last()
            .should("have.attr", "href")
            .and("match", new RegExp(`/historicaldocuments/${VOLUME}$`));
    });

    it("mounts the viewer against the production IIIF image server", () => {
        cy.get("main pb-facsimile").should("have.attr", "base-uri", IIIF_BASE);
        // page 316 of this volume is scan 0347 (reference parity with the
        // identifier hsg-shell's viewer built)
        cy.get("main pb-facs-link.hsg-frus__facsimile-trigger")
            .should("have.attr", "facs", `frus%2F${VOLUME}%2Ftiff%2F0347.tif`);
    });

    it("loads the page scan into the deep-zoom viewer", () => {
        // "loaded" reflects once the emit-on-load link has pushed its image
        // into the viewer; the OpenSeadragon canvas then needs the real
        // info.json from the image server.
        cy.get("main pb-facsimile[loaded]", { timeout: 20000 }).should("exist");
        cy.get("main pb-facsimile", { timeout: 20000 })
            .shadow()
            .find("#viewer canvas")
            .should("exist");
    });

    it("shows the volume table of contents in the sidebar (OP#1445)", () => {
        // the same "Contents" sidenav as the volume's document pages; the
        // reference marks no entry current on a page view
        cy.get("aside nav.toc").within(() => {
            cy.get("h5").should("contain.text", "Contents");
            cy.get(".usa-sidenav a").should("have.length", 15);
            cy.get(".usa-current").should("not.exist");
        });
    });

    it("pages to the neighboring scans", () => {
        cy.get(".hsg-frus__pager-prev")
            .should("have.attr", "href")
            .and("match", new RegExp(`/historicaldocuments/${VOLUME}/pg_315$`));
        cy.get(".hsg-frus__pager-next")
            .should("have.attr", "href")
            .and("match", new RegExp(`/historicaldocuments/${VOLUME}/pg_317$`));
    });

    it("keeps the noscript fallback to the static page image", () => {
        cy.get("main noscript").invoke("text")
            .should("contain", `https://static.history.state.gov/frus/${VOLUME}/medium/0347.png`);
    });

    it("lists the documents printed on this page", () => {
        // reference parity with hsg-shell's docs-on-page aside: page 316
        // carries only Document 80
        cy.get(".hsg-frus__docs-on-page").within(() => {
            cy.get(".hsg-sidebar-title").should("contain.text", "Show Documents on this Page");
            cy.get("li a").should("have.length", 1)
                .first()
                .should("contain.text", "Document 80")
                .and("have.attr", "href")
                .and("match", new RegExp(`/historicaldocuments/${VOLUME}/d80$`));
        });
    });
});

describe("documents on this page across page boundaries", () => {
    it("lists both documents when a page spans a document break", () => {
        // page 317 holds the end of d80 and the start of d81
        cy.visit(`historicaldocuments/${VOLUME}/pg_317`);
        cy.get(".hsg-frus__docs-on-page li a").should("have.length", 2);
        cy.get(".hsg-frus__docs-on-page li a").eq(0).should("contain.text", "Document 80");
        cy.get(".hsg-frus__docs-on-page li a").eq(1).should("contain.text", "Document 81");
    });

    it("attributes pages inside an attachment to the parent document", () => {
        // page 35's scan lives in attachment d10-a1, which has no page of
        // its own; the reference lists Document 10
        cy.visit(`historicaldocuments/${VOLUME}/pg_35`);
        cy.get(".hsg-frus__docs-on-page li a").should("have.length", 1)
            .first()
            .should("contain.text", "Document 10")
            .and("have.attr", "href")
            .and("match", new RegExp(`/historicaldocuments/${VOLUME}/d10$`));
    });

    it("drops the panel on front matter pages without documents", () => {
        // deliberate deviation from the reference, which rendered an empty
        // panel shell here; hsg-jinks hides empty panels (register-panel
        // convention)
        cy.visit(`historicaldocuments/${VOLUME}/pg_XIX`);
        cy.get(".hsg-frus__docs-on-page").should("not.exist");
    });
});

describe("pg_* route resolution", () => {
    it("resolves roman-numeral front matter pages", () => {
        cy.visit(`historicaldocuments/${VOLUME}/pg_XIX`);
        cy.get("main pb-facs-link.hsg-frus__facsimile-trigger")
            .should("have.attr", "facs", `frus%2F${VOLUME}%2Ftiff%2F0020.tif`);
    });

    it("404s for a page the volume does not have", () => {
        cy.request({
            url: `historicaldocuments/${VOLUME}/pg_9999`,
            failOnStatusCode: false,
        }).its("status").should("eq", 404);
    });

    it("404s for a volume without page images", () => {
        // frus1977-80v27 is deployed but carries no page breaks or scans
        cy.request({
            url: "historicaldocuments/frus1977-80v27/pg_1",
            failOnStatusCode: false,
        }).its("status").should("eq", 404);
    });
});

describe("document page facsimile links", () => {
    beforeEach(() => cy.visit(`historicaldocuments/${VOLUME}/d80`));

    it("renders page-break markers as links to the facsimile pages", () => {
        // d80 starts mid page 315 and runs through 316/317; the continuation
        // pb at the top carries no xml:id but its @n still yields the link
        cy.get("main a.hsg-facs-link").should("have.length", 3);
        cy.get("main a.hsg-facs-link").first()
            .should("contain.text", "[Page 315]")
            .and("have.attr", "href", "pg_315");
    });

    it("navigates a page marker to the facsimile page", () => {
        cy.get("main a.hsg-facs-link").first().click();
        cy.location("pathname").should("match", new RegExp(`historicaldocuments/${VOLUME}/pg_315$`));
        cy.get("main pb-facsimile").should("exist");
        cy.get(".hsg-frus__docs-on-page li a").should("contain.text", "Document 80");
    });
});

describe("bare page-break ids (OP#1315)", () => {
    it("pg{n} without the underscore 404s instead of serving an accidental page", () => {
        // the v2 data's internal page-break ids (pg316) used to resolve via
        // id() into near-empty division pages; the public URL is pg_316
        cy.request({ url: `historicaldocuments/${VOLUME}/pg316`, failOnStatusCode: false })
            .its("status")
            .should("eq", 404);
    });

    it("the underscore form keeps working", () => {
        cy.request(`historicaldocuments/${VOLUME}/pg_316`).its("status").should("eq", 200);
    });
});
