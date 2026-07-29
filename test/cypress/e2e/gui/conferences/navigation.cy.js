// Covers the user story "Browse and read a conference" (OP#1115): scan the
// conference list, open a conference, read section by section via prev/next
// without returning to the TOC, and navigate back via the breadcrumb.
//
// conferences is the 8th external data package (README "External data
// packages"), frozen content per the epic (last addition 2012) -- unlike the
// 7 append-only packages (CLAUDE.md "Cypress assertions on data-package
// counts"), an exact count of 5 is expected to stay stable.
//
// baseUrl: see the note in ../document-view.cy.js. This worktree's own
// devcontainer port is in .env (CYPRESS_BASE_URL).

const SECTION = "conferences";
const CONFERENCE = "conferences/2010-southeast-asia";
const CONFERENCE_TITLE = "The American Experience in Southeast Asia, 1946-1975";

describe("the section landing", () => {
    it("lists every conference as a data-driven link with a date", () => {
        cy.visit(SECTION);
        cy.get("main h1").should("contain.text", "Conferences");
        cy.get("main ol.usa-collection > li.usa-collection__item").should(
            "have.length",
            5,
        );
        cy.contains("main .usa-collection__heading a", CONFERENCE_TITLE)
            .should("have.attr", "href")
            .and("match", new RegExp(`${CONFERENCE}$`));
        cy.contains("main .usa-collection__item", CONFERENCE_TITLE)
            .find(".usa-collection__meta-item")
            .should("not.be.empty");
    });

    it("matches the reference site's exact order, numbering, and text (hsg-shell pages/conferences/index.xml)", () => {
        cy.visit(SECTION);
        // usa-collection sets display:flex on its <li>, which suppresses
        // native ::marker rendering regardless of list-style-type -- the
        // visible "1." etc. come from a CSS counter (hsg-theme.css,
        // .conf-conference-list), not the browser's own <ol> numbering.
        // getComputedStyle can't read a pseudo-element's *rendered* counter
        // text (only the literal `content` declaration, unresolved), so the
        // counter's own presence is checked structurally here; the actual
        // rendered "1." through "5." was confirmed visually via a Cypress
        // screenshot during development.
        cy.get("main .conf-conference-list").should(($ol) => {
            expect(window.getComputedStyle($ol[0]).counterReset).to.match(/conf-conference/);
        });
        cy.get("main .conf-conference-list > li.usa-collection__item")
            .first()
            .should(($li) => {
                expect(window.getComputedStyle($li[0], "::before").content).to.include(
                    "counter(conf-conference)",
                );
            });
        cy.get("main .conf-conference-list > li.usa-collection__item h3").then(($hs) => {
            expect([...$hs].map((h) => h.textContent.trim())).to.deep.equal([
                "National Security Policy and SALT I, 1969-1972",
                "Foreign Economic Policy, 1973-1976",
                "The American Experience in Southeast Asia, 1946-1975",
                "U.S.-Soviet Relations in the Era of Détente, 1969-1976",
                "Transforming the Cold War: The United States and China, 1969-1980",
            ]);
        });
        cy.get("main h3").contains("Past Conferences").should("exist");
        cy.get("main p")
            .first()
            .should("contain.text", "The Office of the Historian periodically hosts or co-hosts");
        cy.get("main p")
            .last()
            .should("contain.text", "The Office of the Historian also participates in other events");
        cy.get("main p").last().find("a").contains("Events")
            .should("have.attr", "href")
            .and("match", /historicaldocuments\/frus-history\/events$/);
    });

    it("lists the same 5 conferences in the sidebar", () => {
        cy.visit(SECTION);
        cy.get("aside.before nav[aria-label='Side navigation'] li.usa-sidenav__item").should(
            "have.length",
            5,
        );
    });

    it("is what the breadcrumb's Conferences crumb points at", () => {
        cy.visit(CONFERENCE);
        cy.get("nav[aria-label='breadcrumb']").contains("a", "Conferences").click();
        cy.location("pathname").should("match", new RegExp(`${SECTION}$`));
        cy.get("main ol.usa-collection > li").should("have.length", 5);
    });
});

describe("navigate from the conference landing into a section and back out", () => {
    it("clicks through section -> conference -> a TOC section", () => {
        cy.visit(SECTION);
        cy.contains("a", CONFERENCE_TITLE).click();
        cy.location("pathname").should("match", new RegExp(`${CONFERENCE}$`));
        cy.get("main h1").should("contain.text", CONFERENCE_TITLE);

        // Document view: both the TOC and the conference-list sidebar are present.
        cy.get("aside.before nav[aria-label='Table of contents']").should("exist");
        cy.get("aside.before nav[aria-label='Side navigation'] li").should(
            "have.length",
            5,
        );

        cy.get("nav[aria-label='Table of contents']").contains("a", "Program").click();
        cy.location("pathname").should("match", new RegExp(`${CONFERENCE}/program$`));
        cy.get("main h1").should("be.visible");
    });

    it("moves forward with prev/next without returning to the TOC, TOC highlight follows", () => {
        cy.visit(`${CONFERENCE}/secretary-clinton`);
        cy.get("nav[aria-label='Table of contents'] a.usa-current")
            .should("have.attr", "aria-current", "page")
            .and("contain.text", "Clinton");

        cy.get("nav.usa-pagination .usa-pagination__next-page").click();
        cy.location("pathname").should(
            "match",
            new RegExp(`${CONFERENCE}/secretary-kissinger$`),
        );
        cy.get("nav[aria-label='Table of contents'] a.usa-current").should(
            "contain.text",
            "Kissinger",
        );

        cy.get("nav.usa-pagination .usa-pagination__previous-page").click();
        cy.location("pathname").should(
            "match",
            new RegExp(`${CONFERENCE}/secretary-clinton$`),
        );
    });

    it("the division view has no conference-list sidebar, only the TOC", () => {
        cy.visit(`${CONFERENCE}/program`);
        cy.get("aside.before nav[aria-label='Table of contents']").should("exist");
        cy.get("aside.before nav[aria-label='Side navigation']").should("not.exist");
    });

    it("breadcrumb takes me back to the conference from a section", () => {
        cy.visit(`${CONFERENCE}/program`);
        cy.get("nav[aria-label='breadcrumb']").contains("a", CONFERENCE_TITLE).click();
        cy.location("pathname").should("match", new RegExp(`${CONFERENCE}$`));
    });
});
