// Volume landing page content tests (#1080, layout OP#1478).
//
// Rendered by templates/pages/volume/landing.html and hsg:volume-ways-to-explore() in
// modules/templates/hsg.xqm, after Figma node 4298-66032: a white card with
// the administration tags, title, cover, the editor/publisher metadata list,
// and the "Open" call to action; the volume TOC in the left sidebar, the same
// one its child pages show; a right-hand sidebar with "Ways to Explore"
// (search within the volume, ebook downloads), tags and administrations.

const VOLUME = "historicaldocuments/frus1981-88v05";

describe("volume landing page", () => {
    beforeEach(() => cy.visit(VOLUME));

    it("puts the volume on a card with its administration tag above the title", () => {
        cy.get("main article.hsg-frus__landing").should("have.css", "background-color", "rgb(255, 255, 255)");
        cy.get(".hsg-frus__tags .usa-tag").should("have.length", 1).and("contain.text", "Ronald Reagan Administration");
        cy.get(".hsg-frus__tags a.usa-tag").should("have.attr", "href").and("match", /\/historicaldocuments\/reagan$/);
        cy.get(".hsg-frus__landing-header h1").should("contain.text", "Soviet Union, March 1985–October 1986");
    });

    it("has the volume TOC in the left sidebar and none in the card", () => {
        cy.get("pb-page > aside.before nav.toc .usa-sidenav").should("be.visible");
        cy.get("main .hsg-frus__landing").find(".usa-sidenav, .hsg-frus__toc").should("not.exist");
    });

    it("shows the cover image in its square frame", () => {
        cy.get(".hsg-frus__cover-frame img.hsg-frus__cover")
            .should("have.attr", "src", "https://static.history.state.gov/frus/frus1981-88v05/covers/frus1981-88v05.jpg")
            .and("have.attr", "alt")
            .and("contain", "Book Cover of");
        cy.get(".hsg-frus__cover-frame").then(($frame) => {
            const { width, height } = $frame[0].getBoundingClientRect();
            expect(Math.abs(width - height)).to.be.lessThan(2);
        });
    });

    it("lists editors, publisher, place, and publication year", () => {
        cy.get(".hsg-frus__meta dt").eq(0).should("have.text", "Editor:");
        cy.get(".hsg-frus__meta dt").eq(0).next("dd").should("contain.text", "Elizabeth C. Charles");
        cy.get(".hsg-frus__meta dt").eq(1).should("have.text", "General Editor:");
        cy.get(".hsg-frus__meta dt").eq(1).next("dd").should("contain.text", "Kathleen B. Rasmussen");
        cy.get(".hsg-frus__publisher").should("contain.text", "United States Government Publishing Office")
            .and("contain.text", "Washington");
        cy.get(".hsg-frus__pubdate").should("have.text", "2020");
    });

    it("opens the volume at its first body division", () => {
        cy.get("a.hsg-frus__open").should("have.text", "Open").and("have.attr", "href").and("match", /\/frus1981-88v05\/comp$/);
    });

    it("lists the compilation with nested chapters and document ranges in the sidebar TOC", () => {
        cy.get("pb-page > aside.before .usa-sidenav").within(() => {
            cy.get("a[href$='/comp']").should("contain.text", "Documents 1–309");
            cy.get(".usa-sidenav__sublist > li").should("have.length.at.least", 6);
            cy.get(".usa-sidenav__sublist a[href$='/ch1']").should("contain.text", "Documents 1–50");
            cy.get(".usa-current").should("not.exist");
        });
    });

    it("shows the same TOC as its child pages", () => {
        const hrefs = ($as) => [...$as].map((el) => el.getAttribute("href"));
        cy.get("pb-page > aside.before .usa-sidenav a").then(($as) => {
            const landing = hrefs($as);
            expect(landing).to.have.length.at.least(10);
            cy.visit(`${VOLUME}/ch1`);
            cy.get("pb-page > aside.before .usa-sidenav a").then(($child) => {
                expect(hrefs($child)).to.deep.equal(landing);
            });
        });
    });

    it("has a 'Ways to Explore' panel with volume search and ebook downloads", () => {
        cy.get(".hsg-frus__ways-to-explore").within(() => {
            cy.get("h2").should("contain.text", "Ways to Explore");
            cy.get("form[action$='/search']").within(() => {
                cy.get("input[name='q']").should("exist");
                cy.get("input[name='within']").should("have.value", "documents");
                cy.get("input[name='volume-id']").should("have.value", "frus1981-88v05");
            });
            cy.get("a.hsg-frus__download").should("have.length", 3);
            cy.get("a.hsg-frus__download").eq(0).should("contain.text", "EPUB").and("have.attr", "href").and("match", /\.epub$/);
            cy.get("a.hsg-frus__download").eq(1).should("contain.text", "Mobi").and("have.attr", "href").and("match", /\.mobi$/);
            cy.get("a.hsg-frus__download").eq(2).should("contain.text", "PDF").and("have.attr", "href").and("match", /\.pdf$/);
        });
    });

    it("lists tags and administrations in the sidebar", () => {
        cy.get("pb-page > aside.after .tags-panel .usa-in-page-nav__list li").should("have.length.at.least", 5);
        cy.get("pb-page > aside.after .hsg-frus__administrations").should("contain.text", "All Administrations");
    });
});

// Regression: a microfiche supplement's notesStmt carries one relatedItem per
// associated file (frus1958-60v05mSupp has 562 type="pdf" entries, one per
// document) alongside the volume's own downloads. Selecting ebook links by
// @type alone matched all 562 and the page died with an XPTY0004 cardinality
// error; the volume's own items are identified by @corresp = "#<volume-id>",
// the same gate hsg-shell's fh:exists-pdf and friends use.
// Unpublished ("pending") chapters, which the reference site marks with
// li.pending on this page: italic in the sidebar TOC.
describe("volume landing page, unpublished chapters", () => {
    const PARTIAL = "historicaldocuments/frus1977-80v27";

    beforeEach(() => cy.visit(PARTIAL));

    it("marks chapters with no published documents as pending", () => {
        cy.get("pb-page > aside.before .usa-sidenav__item.pending").should("have.length.at.least", 1);
        cy.get("pb-page > aside.before .usa-sidenav__item.pending > a")
            .first()
            .should("have.css", "font-style", "italic");
    });

    it("leaves chapters that do have published documents unmarked", () => {
        cy.contains("pb-page > aside.before .usa-sidenav__item", "Canada").should("not.have.class", "pending");
    });
});

describe("volume landing page for a microfiche supplement", () => {
    const SUPPLEMENT = "historicaldocuments/frus1958-60v05mSupp";

    beforeEach(() => cy.visit(SUPPLEMENT));

    it("renders instead of erroring on the per-document relatedItems", () => {
        cy.get("main h1").should("contain.text", "Microfiche Supplement");
        cy.get(".hsg-frus__ways-to-explore").should("exist");
    });

    it("links only the volume-level ebook downloads, not the per-document PDFs", () => {
        cy.get(".hsg-frus__ways-to-explore").within(() => {
            cy.get("a.hsg-frus__download").should("have.length", 3);
            cy.get("a.hsg-frus__download[href$='frus1958-60v05mSupp.epub']").should("exist");
            cy.get("a.hsg-frus__download[href$='frus1958-60v05mSupp.mobi']").should("exist");
            // The volume PDF, not one of the 562 per-document ones.
            cy.get("a.hsg-frus__download[href$='frus1958-60v05mSupp.pdf']").should("exist");
        });
    });

    it("still shows the cover image", () => {
        cy.get("img.hsg-frus__cover")
            .should("have.attr", "src", "https://static.history.state.gov/frus/frus1958-60v05mSupp/covers/frus1958-60v05mSupp.jpg");
    });
});
