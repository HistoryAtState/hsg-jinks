// Covers the user story "Arrive at a conference section via deep link"
// (OP#1116): landing directly on a division page (e.g. from a search engine
// or a shared link) still renders complete chrome, and malformed/unknown ids
// 404 for real rather than serving a 200 error page or a wrong-but-plausible
// one -- the same id()-whitespace-tokenization guard as
// hsgapi:is-exact-division (modules/hsg-api.xql), reused here as
// confapi:is-exact-division (modules/conferences-api.xql).
//
// baseUrl: see the note in ../document-view.cy.js.

const CONFERENCE = "conferences/2010-southeast-asia";
const CONFERENCE_TITLE = "The American Experience in Southeast Asia, 1946-1975";
const SECTION_PATH = `${CONFERENCE}/secretary-clinton`;
const SECTION_TITLE = "Opening Address by Secretary of State Hillary Rodham Clinton";

describe("direct deep link to a conference section", () => {
    it("renders complete on first load: heading, prose, and the video embed", () => {
        cy.visit(SECTION_PATH);
        cy.get("main h1").should("contain.text", SECTION_TITLE);
        cy.get("main .usa-prose").should("exist");
        // The raw Brightcove <script> embedded in the source TEI is replaced
        // at render time (resources/odd/hsg-jinks.odd) with a safe iframe --
        // no third-party inline script ever reaches the page.
        cy.get("main iframe[src*='players.brightcove.net']").should("exist");
        cy.get("script[src*='brightcove']").should("not.exist");
    });

    it("breadcrumb shows Home > Conferences > conference > section, each crumb navigable", () => {
        cy.visit(SECTION_PATH);
        cy.get('nav[aria-label="breadcrumb"] ul:not(:empty) li').then(($lis) => {
            const texts = Cypress._.map($lis, (li) => li.textContent.replace(/\s+/g, " ").trim());
            expect(texts).to.deep.equal([
                "Home",
                "Conferences",
                CONFERENCE_TITLE,
                SECTION_TITLE,
            ]);
        });
        cy.get('nav[aria-label="breadcrumb"] li').last()
            .should("have.attr", "aria-current", "page")
            .find("a")
            .should("not.exist");

        cy.get('nav[aria-label="breadcrumb"]').contains("a", "Home").click();
        cy.location("pathname").should("match", /\/(index\.html)?$/);
    });

    it("the TOC sidebar shows the whole conference with my section highlighted", () => {
        cy.visit(SECTION_PATH);
        cy.get("nav[aria-label='Table of contents'] a.usa-current")
            .should("have.attr", "aria-current", "page")
            .and("contain.text", "Clinton");
        // The wider conference has more than this one section listed.
        cy.get("nav[aria-label='Table of contents'] a").its("length").should("be.gte", 5);
    });
});

describe("malformed or unknown ids 404 for real", () => {
    it("unknown conference id: 404 status, not a 200 error page", () => {
        cy.request({ url: "conferences/1999-does-not-exist", failOnStatusCode: false }).then(
            (resp) => expect(resp.status).to.eq(404),
        );
    });

    it("unknown section id within a real conference: 404", () => {
        cy.request({
            url: `${CONFERENCE}/no-such-section`,
            failOnStatusCode: false,
        }).then((resp) => expect(resp.status).to.eq(404));
    });

    it("whitespace-tokenized id (id()'s multi-node bug): 404, not a crash or a silent match", () => {
        cy.request({
            url: `${CONFERENCE}/program%20photos`,
            failOnStatusCode: false,
        }).then((resp) => expect(resp.status).to.eq(404));
    });

    it("trailing-space id (id()'s single-node bug): 404, not silently served as the base id", () => {
        cy.request({
            url: `${CONFERENCE}/program%20`,
            failOnStatusCode: false,
        }).then((resp) => expect(resp.status).to.eq(404));
    });
});
