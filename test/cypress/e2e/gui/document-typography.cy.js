// Document page type and left sidebar (OP#1462, Figma node 4298:27011): the
// volume title above the content is a small semi-bold overline in the
// secondary blue, the division title a 28px semi-bold Merriweather (the
// variable cut from profile-theme-uswds, which has the 500 weight), and the
// table of contents is the USWDS side navigation on white as the design kit
// draws it (Figma node 4290:19930): no "Contents" headline, top-level entries
// 16px regular in the body text colour, nested entries 14px medium indented
// 32px, the current entry bold in primary-dark, and each document range inside
// its entry's link as on the reference site.

const DOCUMENT = "historicaldocuments/frus1981-88v05/d1";

describe("document page typography", () => {
    beforeEach(() => {
        cy.viewport(1440, 1000);
        cy.visit(DOCUMENT);
    });

    it("loads the variable Merriweather with a 500 weight", () => {
        cy.document().then((doc) => doc.fonts.ready.then(() => doc));
        cy.document().should((doc) => {
            expect(doc.fonts.check('500 1rem "Merriweather Variable"')).to.equal(true);
        });
    });

    it("sets the volume title as a small semi-bold overline in the secondary blue", () => {
        cy.get("main .hsg-navigation-title")
            .should("have.css", "font-weight", "500")
            .and("have.css", "color", "rgb(0, 129, 161)")
            .and("have.css", "font-family")
            .and("match", /^"?Merriweather Variable/);
        cy.get("main .hsg-navigation-title")
            .invoke("css", "font-size")
            .then((size) => expect(parseFloat(size)).to.be.closeTo(15.7, 0.5));
    });

    it("sets the division title at 28px, semi-bold", () => {
        cy.get("main .hsg-frus__prose h1.tei-head")
            .first()
            .should("have.css", "font-size", "28px")
            .and("have.css", "font-weight", "500");
    });

    it("renders a semi-bold title wider than regular and narrower than bold", () => {
        cy.get("main .hsg-frus__prose h1.tei-head")
            .first()
            .then(($h) => {
                const el = $h[0];
                const width = (weight) => {
                    el.style.fontWeight = weight;
                    const range = el.ownerDocument.createRange();
                    range.selectNodeContents(el);
                    return range.getBoundingClientRect().width;
                };
                el.style.whiteSpace = "nowrap";
                const regular = width("400");
                const semibold = width("500");
                const bold = width("700");
                el.style.fontWeight = "";
                el.style.whiteSpace = "";
                expect(semibold).to.be.greaterThan(regular);
                expect(semibold).to.be.lessThan(bold);
            });
    });

    it("styles the table of contents as the design kit's side navigation", () => {
        cy.visit("historicaldocuments/frus1981-88v05/ch1");
        cy.get("nav.toc > ul.usa-sidenav > li > a")
            .first()
            .should("have.css", "font-size", "16px")
            .and("have.css", "font-weight", "400")
            .and("have.css", "color", "rgb(46, 46, 46)");
        cy.get("nav.toc .usa-sidenav__sublist a:not(.usa-current)")
            .first()
            .should("have.css", "font-weight", "500")
            .and("have.css", "padding-left", "32px")
            .invoke("css", "font-size")
            .then((size) => expect(parseFloat(size)).to.be.closeTo(14, 0.5));
        cy.get("nav.toc a.usa-current")
            .should("have.css", "font-weight", "700")
            .and("have.css", "color", "rgb(44, 96, 138)");
        cy.get("nav.toc .usa-sidenav__item")
            .first()
            .should("have.css", "border-top-color", "rgb(230, 230, 230)");
    });

    it("puts the table of contents on a white panel without a headline", () => {
        cy.get('aside nav.toc[aria-label="Side navigation"]')
            .should("have.css", "background-color", "rgb(255, 255, 255)")
            .within(() => {
                cy.get("h1, h2, h3, h4, h5, h6").should("not.exist");
            });
    });

    it("shows each document range inside its entry's link", () => {
        cy.get("aside nav.toc .toc-range")
            .should("have.length.at.least", 1)
            .each(($range) => {
                expect($range.parent().is("a")).to.equal(true);
                // numbered or lettered (appendix) documents, e.g. "(Documents A–C)"
                expect($range.text()).to.match(/^ \(Documents? [^()]+\)$/);
            });
        cy.get("aside nav.toc a")
            .contains("Soviet Union, March 1985–October 1986")
            .should("contain.text", "(Documents 1–309)");
    });
});
