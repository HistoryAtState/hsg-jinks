// Interior division page chrome and sidebar (PR #32 review comment):
// the volume-title h2 above the content, prev/next on section pages, the
// "Page N" page-break markers, and the right-hand sidebar (Persons,
// Abbreviations & Terms, Historical Documents). Reference parity with
// hsg-shell's volume-interior template (navigation title, fh:facets,
// site.xml "sections" aside).
//
// frus1958-60v05mSupp is a frozen microfiche supplement (published 2020,
// content stable), so exact assertions against its data are safe; the
// Historical Documents panel is fixed UI chrome, so its 7-link count is
// asserted exactly.

const VOLUME_TITLE =
    "Foreign Relations of the United States, 1958–1960, Volume V, Microfiche Supplement, American Republics";

describe("section page (sec6)", () => {
    beforeEach(() => cy.visit("historicaldocuments/frus1958-60v05mSupp/sec6"));

    it("shows the volume title as navigation heading", () => {
        cy.get("main h2.hsg-navigation-title").should("have.text", VOLUME_TITLE);
    });

    it("has prev/next navigation to the neighboring sections", () => {
        cy.get(".hsg-frus__pager-prev").should("have.attr", "href").and("match", /\/frus1958-60v05mSupp\/sec5$/);
        cy.get(".hsg-frus__pager-next").should("have.attr", "href").and("match", /\/frus1958-60v05mSupp\/sec7$/);
    });

    it("renders page breaks as 'Page N' margin markers, not bare numbers", () => {
        cy.get("main pb-facs-link.hsg-facs-link").first().should("contain.text", "Page 66");
    });

    it("shows the Persons panel with described entries", () => {
        cy.get(".hsg-frus__register").eq(0).within(() => {
            cy.get(".hsg-sidebar-title").should("contain.text", "Persons");
            // 8 persName refs in sec6; the supplement is frozen.
            cy.get("li a").should("have.length", 8);
            cy.get("li a").first()
                .should("contain.text", "Betancourt, Romulo")
                .and("have.attr", "title")
                .and("contain", "President of Venezuela");
        });
    });

    it("shows the Abbreviations & Terms panel", () => {
        cy.get(".hsg-frus__register").eq(1).within(() => {
            cy.get(".hsg-sidebar-title").should("contain.text", "Abbreviations & Terms");
            cy.get("li a").should("have.length", 1)
                .first().should("contain.text", "OAS")
                .and("have.attr", "title")
                .and("contain", "Organization of American States");
        });
    });

    it("shows the Historical Documents section navigation", () => {
        cy.get(".hsg-frus__section-nav").within(() => {
            cy.get(".hsg-sidebar-title").should("contain.text", "Historical Documents");
            cy.get("li a").should("have.length", 7);
            cy.get("li a").first().should("have.attr", "href").and("contain", "about-frus");
        });
    });
});

describe("document page (eta_d1) chrome", () => {
    beforeEach(() => cy.visit("historicaldocuments/frus1958-60v05mSupp/eta_d1"));

    it("shows the volume title as navigation heading", () => {
        cy.get("main h2.hsg-navigation-title").should("have.text", VOLUME_TITLE);
    });

    it("stacks title, content and pager in one column", () => {
        // Regression: content and pager used to render side by side because
        // the layout's main is a flex row assigning flex: 1 per child.
        cy.get("main > *").should("have.length", 1);
        cy.get("main .hsg-frus__pager").then(($pager) => {
            cy.get("main .tei-TEI").then(($content) => {
                expect($pager[0].getBoundingClientRect().top).to.be.greaterThan(
                    $content[0].getBoundingClientRect().bottom - 1
                );
            });
        });
    });

    it("shows the register panels in the sidebar", () => {
        cy.get(".hsg-frus__register").should("have.length.at.least", 1);
        cy.get(".hsg-frus__section-nav").should("exist");
    });
});

describe("container pages keep the sidebar minimal", () => {
    it("chapter page has the section nav but no register panels", () => {
        cy.visit("historicaldocuments/frus1958-60v05mSupp/ch1");
        cy.get(".hsg-frus__section-nav").should("exist");
        cy.get(".hsg-frus__register").should("not.exist");
        cy.get("main h2.hsg-navigation-title").should("have.text", VOLUME_TITLE);
    });

    it("compilation page has the section nav but no register panels", () => {
        cy.visit("historicaldocuments/frus1958-60v05mSupp/comp1");
        cy.get(".hsg-frus__section-nav").should("exist");
        cy.get(".hsg-frus__register").should("not.exist");
    });
});

describe("ODD audit regressions (PR #32 review)", () => {
    it("resolves FRUS document graphics against static.history.state.gov/frus", () => {
        cy.visit("historicaldocuments/frus1981-88v05/appC");
        cy.get("main img.tei-graphic")
            .first()
            .should("have.attr", "src")
            .and("match", /^https:\/\/static\.history\.state\.gov\/frus\/frus1981-88v05\/.+\.png$/);
    });

    it("keeps cell renditions from the source", () => {
        cy.visit("historicaldocuments/frus1861/d180");
        cy.get("main td.document_middle").should("have.length.at.least", 1);
    });
});
