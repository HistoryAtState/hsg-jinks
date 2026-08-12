// Sidebar table of contents (#1089): the volume's TOC as a USWDS side
// navigation, in the layout's left `before` area, on the comp, chapter and
// document pages.
//
// Shape is reference parity: front matter flat, each compilation as a node with
// its chapters nested beneath, then the back matter. Documents are never listed
// and the print table of contents (front/toc.xml, subtype table-of-contents) is
// omitted.
//
// The tree comes from hsg:volume-toc() in modules/templates/hsg.xqm, which is
// also what #1080 will render in the landing page's main content -- one
// traversal, two placements.
//
// baseUrl: see the note in document-view.cy.js.

const VOLUME = "historicaldocuments/frus1981-88v05";

// Front matter, in the volume's own include order; the print TOC ("Contents")
// sits between Preface and Sources in the data and must not appear.
const FRONT = [
    "Press Release",
    "About the Series",
    "Preface",
    "Sources",
    "Abbreviations and Terms",
    "Persons",
];
const COMPILATION = "Soviet Union, March 1985–October 1986";
const BACK = ["Appendix", "Index"];

const text = (el) => el.textContent.replace(/\s+/g, " ").trim();

describe("sidebar table of contents", () => {
    ["comp", "ch1", "d1"].forEach((page) => {
        it(`${page}: renders the volume TOC as a USWDS side navigation`, () => {
            cy.visit(`${VOLUME}/${page}`);
            cy.get("nav.toc ul.usa-sidenav").should("exist");
            cy.get("nav.toc").should("have.attr", "aria-label");
        });
    });

    it("the volume landing has no sidebar TOC", () => {
        // Its table of contents belongs in the main content instead (#1080).
        // The volume file carries no typed bibl ids -- only its divisions do --
        // which is what the helper guards on.
        cy.visit(VOLUME);
        cy.get("main h1").should("be.visible");
        cy.get("nav.toc").should("not.exist");
    });

    describe("shape", () => {
        beforeEach(() => cy.visit(`${VOLUME}/ch1`));

        it("lists front matter, the compilation and back matter at the top level", () => {
            cy.get("nav.toc > ul.usa-sidenav > li.usa-sidenav__item > a").then(($as) => {
                expect([...$as].map(text)).to.deep.eq([
                    ...FRONT,
                    COMPILATION,
                    ...BACK,
                ]);
            });
        });

        it("omits the print table of contents", () => {
            // front/toc.xml is titled "Contents" and is excluded by its
            // frus-division-subtype, not by a hardcoded path.
            cy.get("nav.toc ul.usa-sidenav a").each(($a) => {
                expect($a.attr("href")).not.to.match(/\/toc$/);
            });
        });

        it("nests the six chapters under the compilation", () => {
            cy.get("nav.toc ul.usa-sidenav__sublist").should("have.length", 1);
            cy.get("nav.toc ul.usa-sidenav__sublist > li.usa-sidenav__item").should(
                "have.length",
                6,
            );
            // the sublist belongs to the compilation's own list item
            cy.get("nav.toc > ul.usa-sidenav > li")
                .contains("a", COMPILATION)
                .parent()
                .find("ul.usa-sidenav__sublist")
                .should("exist");
        });

        it("never lists documents", () => {
            cy.get("nav.toc ul.usa-sidenav a").each(($a) => {
                expect($a.attr("href")).not.to.match(/\/d\d+(-a\d+)?$/);
            });
        });
    });

    describe("current page", () => {
        it("ch1: marks the chapter being viewed, and only it", () => {
            cy.visit(`${VOLUME}/ch1`);
            cy.get("nav.toc a.usa-current")
                .should("have.length", 1)
                .and("have.attr", "aria-current", "page")
                .invoke("text")
                .should("contain", "March 1985");
        });

        it("comp: marks the compilation, not its chapters", () => {
            cy.visit(`${VOLUME}/comp`);
            cy.get("nav.toc a.usa-current")
                .should("have.length", 1)
                .then(($a) => expect(text($a[0])).to.eq(COMPILATION));
        });

        it("d1: marks the chapter that includes the document", () => {
            // documents are not listed, so the containing chapter stands in
            cy.visit(`${VOLUME}/d1`);
            cy.get("nav.toc a.usa-current")
                .should("have.length", 1)
                .and("have.attr", "href")
                .and("match", /\/ch1$/);
        });

        it("preface: marks a front-matter page", () => {
            cy.visit(`${VOLUME}/preface`);
            cy.get("nav.toc a.usa-current")
                .should("have.length", 1)
                .then(($a) => expect(text($a[0])).to.eq("Preface"));
        });
    });

    it("every link resolves", () => {
        // the TOC links into #519's retained URL space
        cy.visit(`${VOLUME}/ch1`);
        cy.get("nav.toc ul.usa-sidenav a").each(($a) => {
            cy.request($a.attr("href")).its("status").should("eq", 200);
        });
    });

    it("nested items are indented past their parent", () => {
        // USWDS's own indent rule is dropped by browsers -- its selector puts a
        // pseudo-element inside :not() -- so hsg-theme.css restores it. Without
        // it the chapters render flush with their compilation.
        cy.visit(`${VOLUME}/ch1`);
        cy.get("nav.toc ul.usa-sidenav__sublist li a")
            .first()
            .should(($a) => {
                expect(parseFloat(getComputedStyle($a[0]).paddingLeft)).to.be.greaterThan(0);
            });
    });

    describe("USWDS link chrome", () => {
        // Same root cause as the indent fix above (pb-login::part(trigger)
        // extends .usa-button, which pollutes every a:not(.usa-button) rule
        // sitewide with an invalid :not() clause, so browsers drop it) -- but
        // it also drops display/padding/hover/color for every sidenav link,
        // not just the sublist indent. hsg-theme.css restores those too.
        beforeEach(() => cy.visit(`${VOLUME}/ch1`));

        it("gives top-level and nested links block display with padding", () => {
            cy.get("nav.toc ul.usa-sidenav > li > a")
                .first()
                .should(($a) => {
                    const style = getComputedStyle($a[0]);
                    expect(style.display).to.eq("block");
                    expect(parseFloat(style.paddingTop)).to.be.greaterThan(0);
                    expect(parseFloat(style.paddingRight)).to.be.greaterThan(0);
                    expect(parseFloat(style.paddingBottom)).to.be.greaterThan(0);
                });

            cy.get("nav.toc ul.usa-sidenav__sublist li a")
                .first()
                .should(($a) => {
                    const style = getComputedStyle($a[0]);
                    expect(style.display).to.eq("block");
                    expect(parseFloat(style.paddingTop)).to.be.greaterThan(0);
                });
        });

        it("gives non-current links a muted color, distinct from the current page", () => {
            cy.get("nav.toc a.usa-current").then(($current) => {
                const currentColor = getComputedStyle($current[0]).color;
                cy.get("nav.toc ul.usa-sidenav a:not(.usa-current)")
                    .first()
                    .should(($a) => {
                        const color = getComputedStyle($a[0]).color;
                        // default UA link blue/visited-purple, not the USWDS muted gray
                        expect(color).not.to.eq("rgb(0, 0, 238)");
                        expect(color).not.to.eq(currentColor);
                    });
            });
        });

        it("keeps the current page bold (unaffected by the selector bug -- regression guard)", () => {
            cy.get("nav.toc a.usa-current")
                .first()
                .should("have.css", "font-weight", "700");
        });
    });

    // Unpublished chapters, marked li.pending like the reference site marks
    // them on the volume landing page. Here the distinction is the italic
    // alone: every sidebar link already carries the theme's muted grey (see
    // resources/css/hsg-theme.css), so a second grey would not read.
    describe("unpublished chapters", () => {
        const PARTIAL = "historicaldocuments/frus1977-80v27/ch2";

        beforeEach(() => cy.visit(PARTIAL));

        it("marks chapters with no published documents as pending", () => {
            cy.get("nav.toc .usa-sidenav__item.pending").should(
                "have.length.at.least",
                1,
            );
            cy.get("nav.toc .usa-sidenav__item.pending > a")
                .first()
                .should("have.css", "font-style", "italic");
        });

        it("leaves chapters that do have published documents unmarked", () => {
            cy.contains("nav.toc .usa-sidenav__item", "Canada").should(
                "not.have.class",
                "pending",
            );
        });
    });
});
