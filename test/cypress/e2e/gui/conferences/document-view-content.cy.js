// Reference-parity regression coverage for the document view (PR #20 review):
// two bugs found only by comparing against the live reference mirror
// (port 8080, https://history.state.gov/conferences/...), not by reading
// code or by the earlier acceptance specs (which happen to only exercise
// 2012-national-security-policy-salt's single, leaf-only division).
//
// 1. Graphics whose @url is already a full https:// URL (the photo
//    gallery's static.history.state.gov/gallery/... images) rendered no
//    <img> at all: resources/odd/hsg-jinks.odd's graphic elementSpec (mode
//    "change") only had predicated models for *bare filenames*, with no
//    catch-all for an already-qualified URL.
// 2. The document view inlined every division's full content uniformly,
//    including "container" divisions (top-level sections that are
//    themselves just an organizing head over several subchapters/sections,
//    e.g. "Videos and Transcripts", "Background Materials") -- the
//    reference site (hsg-shell's frus.odd, reused for conferences with
//    document-list=true) instead collapses a container division to its own
//    heading + a link list to each child, only showing full content on the
//    child's own page. conf:is-container-division / conf:render-division
//    (modules/templates/conferences.xqm) replicate that distinction.
//
// baseUrl: see the note in ../../document-view.cy.js.

describe("document view: container vs. leaf division rendering (reference parity)", () => {
    it("2010-southeast-asia: the photo gallery's images render (fully-qualified @url)", () => {
        cy.visit("conferences/2010-southeast-asia");
        cy.get("#photos img").should("have.length.at.least", 1);
        cy.get("#photos img")
            .first()
            .should("have.attr", "src")
            .and("match", /^https:\/\/static\.history\.state\.gov\/gallery\//);
    });

    it("2010-southeast-asia: a container division (Videos and Transcripts) collapses to a link list, not inlined transcripts", () => {
        cy.visit("conferences/2010-southeast-asia");
        cy.contains("main h2", "Videos and Transcripts")
            .next("ul.usa-list")
            .find("li")
            .should("have.length", 11);
        // A line of dialogue from deep inside one of those transcripts must
        // not leak onto the document view -- it belongs only on that
        // transcript's own page.
        cy.get("main").should(
            "not.contain.text",
            "Myra is always one who keeps us on a straight and narrow path",
        );
    });

    it("2010-southeast-asia: a leaf division (Program) still renders its full content inline", () => {
        cy.visit("conferences/2010-southeast-asia");
        cy.get("#program").should("contain.text", "Registration and Refreshments");
    });

    it("2006-china-cold-war: the container division (Panel) collapses to a link list", () => {
        cy.visit("conferences/2006-china-cold-war");
        cy.contains("main h2", "Panel of Former Diplomats and Government Officials")
            .next("ul.usa-list")
            .find("li")
            .should("have.length", 8);
    });

    it("2011-foreign-economic-policy: the container division (Audio and Transcripts) collapses, preserving inline emphasis in a child's title", () => {
        cy.visit("conferences/2011-foreign-economic-policy");
        cy.contains("main h2", "Audio and Transcripts")
            .next("ul.usa-list")
            .within(() => {
                cy.get("li").should("have.length", 3);
                cy.contains("a", "Foreign Economic Policy, 1973-1976").find("em").should("exist");
            });
    });

    it("2007-detente: every top-level division is a leaf, so nothing collapses", () => {
        cy.visit("conferences/2007-detente");
        cy.get("main ul.usa-list").should("not.exist");
    });
});
