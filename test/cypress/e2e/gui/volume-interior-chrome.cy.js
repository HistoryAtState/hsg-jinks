// Interior division page chrome and sidebar: the volume-title h2 above the
// content, prev/next on section pages, the "Page N" page-break markers, and
// the right-hand sidebar (Persons, Abbreviations & Terms as one USWDS in-page
// navigation). Reference parity with hsg-shell's volume-interior template
// (navigation title, fh:facets).
//
// frus1958-60v05mSupp is a frozen microfiche supplement (published 2020,
// content stable), so exact assertions against its data are safe.

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

    it("renders page breaks as 'Page N' facsimile links, not bare numbers", () => {
        // plain links to the pg_* facsimile pages since OP#1335
        cy.get("main a.hsg-facs-link").first()
            .should("contain.text", "Page 66")
            .and("have.attr", "href", "pg_66");
    });

    it("lists the registers in one in-page navigation", () => {
        cy.get("aside nav.usa-in-page-nav__nav").within(() => {
            cy.get(".usa-in-page-nav__heading").should("contain.text", "On this page");
            cy.get("ul.usa-in-page-nav__list").should("have.length", 2);
        });
    });

    it("leads the Persons list with a link to the register", () => {
        cy.get(".hsg-frus__register-list").eq(0).within(() => {
            cy.get(".usa-in-page-nav__item--primary").should("have.length", 1)
                .and("contain.text", "Persons")
                .find("a").should("have.attr", "href")
                .and("match", /\/frus1958-60v05mSupp\/persons$/);
            // 8 persName refs in sec6, plus the primary item; the supplement
            // is frozen.
            cy.get("li").should("have.length", 9);
            cy.get("li").eq(1).find("a")
                .should("contain.text", "Betancourt, Romulo")
                .and("have.attr", "href").and("match", /\/persons#p_/);
        });
    });

    it("leads the Abbreviations & Terms list with a link to the register", () => {
        cy.get(".hsg-frus__register-list").eq(1).within(() => {
            cy.get(".usa-in-page-nav__item--primary").should("contain.text", "Abbreviations & Terms")
                .find("a").should("have.attr", "href").and("match", /\/terms$/);
            cy.get("li").should("have.length", 2);
            cy.get("li").eq(1).should("contain.text", "OAS");
        });
    });

    it("shows a register entry's description as a USWDS tooltip", () => {
        // The USWDS script moves the title into the tooltip body and wraps
        // the link; the body shows on hover.
        cy.contains(".hsg-frus__register-list a", "Betancourt, Romulo")
            .should("have.class", "usa-tooltip__trigger")
            .and("not.have.attr", "title");
        cy.contains(".hsg-frus__register-list a", "Betancourt, Romulo").trigger("mouseover");
        cy.contains(".usa-tooltip__body", "President of Venezuela").should("be.visible");
        cy.contains(".hsg-frus__register-list a", "OAS").trigger("mouseover");
        cy.contains(".usa-tooltip__body", "Organization of American States").should("be.visible");
    });

    it("keeps register links working", () => {
        // USWDS cancels clicks on usa-in-page-nav__link; register links must
        // not carry it.
        cy.get(".hsg-frus__register-list a.usa-in-page-nav__link").should("not.exist");
        cy.contains(".hsg-frus__register-list a", "Betancourt, Romulo").click();
        cy.location("pathname").should("match", /\/frus1958-60v05mSupp\/persons$/);
        cy.location("hash").should("match", /^#p_/);
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

    it("shows the register lists in the sidebar", () => {
        cy.get(".hsg-frus__register-list").should("have.length.at.least", 1);
    });
});

describe("container pages keep the sidebar minimal", () => {
    it("chapter page has no register lists", () => {
        cy.visit("historicaldocuments/frus1958-60v05mSupp/ch1");
        cy.get(".hsg-frus__registers").should("not.exist");
        cy.get("main h2.hsg-navigation-title").should("have.text", VOLUME_TITLE);
    });

    it("compilation page has no register lists", () => {
        cy.visit("historicaldocuments/frus1958-60v05mSupp/comp1");
        cy.get(".hsg-frus__registers").should("not.exist");
    });
});

describe("FRUS cross-reference resolution (PR #32 review)", () => {
    // The corpus encodes document references as bare fragments ("#bl_d5")
    // and cross-volume pointers ("frusXXX#dN"); both must become app URLs
    // (shell's pmf:ref parity), since in the per-division v2 data the
    // target is a different file and a fragment href goes nowhere.
    it("resolves same-volume document refs on a section page", () => {
        cy.visit("historicaldocuments/frus1958-60v05mSupp/sec2");
        cy.contains("main a", "BL–5")
            .should("have.attr", "href")
            .and("match", /\/historicaldocuments\/frus1958-60v05mSupp\/bl_d5$/);
        cy.contains("main a", "BL–15")
            .should("have.attr", "href")
            .and("match", /\/historicaldocuments\/frus1958-60v05mSupp\/bl_d15$/);
    });

    it("navigates a document ref to the document page", () => {
        cy.visit("historicaldocuments/frus1958-60v05mSupp/sec2");
        cy.contains("main a", "BL–5").click();
        cy.location("pathname").should("match", /historicaldocuments\/frus1958-60v05mSupp\/bl_d5$/);
        cy.get("main h2.hsg-navigation-title").should("contain.text", "Microfiche Supplement");
    });

    it("resolves cross-volume refs to the other volume's document URL", () => {
        cy.visit("historicaldocuments/frus1958-60v05mSupp/eta_d1");
        cy.get('main a[href$="/historicaldocuments/frus1958-60v10p2/d303"]').should("exist");
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
