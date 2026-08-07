// Document view + article architecture (PR #20 review, several rounds):
//
// The document view (/conferences/{id}) is a plain table of contents: the
// conference title plus a link list, one entry per top-level division --
// leaf or container alike. It never inlines a division's own content.
// Every division (leaf or container, top-level or nested) is instead its
// own complete, independent article on its own page
// (confapi:view-section / conf:section-content), with exactly one <h1> of
// its own -- only one article is ever displayed at a time, reached via
// this list, the persistent TOC sidebar (conf:toc), or prev/next
// (conf:section-pagination) on each division's own page. This replaced an
// earlier version that inlined every leaf division's full content directly
// into the document view (matching the reference site's own behavior,
// itself flagged as a bug worth fixing rather than reproducing) -- which
// in turn had two of its own bugs, fixed along the way and still relevant
// to a division's own standalone page:
//
// 1. Graphics whose @url is already a full https:// URL (the photo
//    gallery's static.history.state.gov/gallery/... images) rendered no
//    <img> at all: resources/odd/hsg-jinks.odd's graphic elementSpec (mode
//    "change") only had predicated models for *bare filenames*, with no
//    catch-all for an already-qualified URL.
// 2. A container division (a top-level section that is itself just an
//    organizing head over several subchapters/sections, e.g. "Videos and
//    Transcripts", "Background Materials") renders as its own heading +
//    intro prose + a link list to each child, not each child's full
//    content inlined -- conf:is-container-division / conf:render-division
//    (modules/templates/conferences.xqm).
//
// baseUrl: see the note in ../../document-view.cy.js.

describe("document view: a plain table of contents, one entry per top-level division", () => {
    it("2010-southeast-asia: lists every top-level division as a link, leaf or container alike, no inlined content", () => {
        cy.visit("conferences/2010-southeast-asia");
        cy.get("main h1").filter(":visible").should("have.length", 1);
        cy.get("main ul.usa-list > li").should("have.length", 5);
        [
            ["Program", "program"],
            ["Videos and Transcripts", "videos-transcripts"],
            ["Vietnam Photo Gallery", "photos"],
            ["Background Materials", "background-materials"],
            ["Post-Conference Reviews", "reviews"],
        ].forEach(([label, id]) => {
            cy.contains("main ul.usa-list a", label)
                .should("have.attr", "href")
                .and("match", new RegExp(`conferences/2010-southeast-asia/${id}$`));
        });
        // None of this division's own content -- text, headings, images --
        // belongs on the document view; it belongs only on its own page.
        cy.get("main").should(
            "not.contain.text",
            "Myra is always one who keeps us on a straight and narrow path",
        );
        cy.get("main img").should("not.exist");
    });

    it("2012-national-security-policy-salt: a single-division conference still lists that division as a link, not its content", () => {
        cy.visit("conferences/2012-national-security-policy-salt");
        cy.get("main ul.usa-list > li").should("have.length", 1);
        cy.contains("main ul.usa-list a", "National Security Policy and SALT I, 1969-1972")
            .should("have.attr", "href")
            .and("match", /conferences\/2012-national-security-policy-salt\/overview$/);
    });
});

describe("each division is its own complete article, on its own page", () => {
    it("2010-southeast-asia/photos: a leaf division's full content, including images, renders on its own page", () => {
        cy.visit("conferences/2010-southeast-asia/photos");
        cy.get("main h1").filter(":visible").should(($h1s) => {
            expect($h1s).to.have.length(1);
            expect($h1s.text()).to.contain("Vietnam Photo Gallery");
        });
        cy.get("main img").should("have.length.at.least", 1);
        cy.get("main img")
            .first()
            .should("have.attr", "src")
            .and("match", /^https:\/\/static\.history\.state\.gov\/gallery\//);
    });

    it("2010-southeast-asia/videos-transcripts: a container division's own page shows its intro + a link list to its children, exactly one h1", () => {
        cy.visit("conferences/2010-southeast-asia/videos-transcripts");
        cy.get("main h1").filter(":visible").should(($h1s) => {
            expect($h1s).to.have.length(1);
            expect($h1s.text()).to.contain("Videos and Transcripts");
        });
        cy.get("main ul.usa-list > li").should("have.length", 11);
    });

    it("2006-china-cold-war/panel: a container division's own page lists its children", () => {
        cy.visit("conferences/2006-china-cold-war/panel");
        cy.get("main ul.usa-list > li").should("have.length", 8);
    });

    it("2011-foreign-economic-policy/audio-transcripts: preserves inline emphasis in a child's title", () => {
        cy.visit("conferences/2011-foreign-economic-policy/audio-transcripts");
        cy.get("main ul.usa-list").within(() => {
            cy.get("li").should("have.length", 3);
            cy.contains("a", "Foreign Economic Policy, 1973-1976").find("em").should("exist");
        });
    });

    it("moving between top-level divisions via prev/next reaches every one, including leaves that used to be inlined", () => {
        cy.visit("conferences/2010-southeast-asia/program");
        cy.get("nav.usa-pagination .usa-pagination__next-page").click();
        cy.location("pathname").should(
            "match",
            /conferences\/2010-southeast-asia\/videos-transcripts$/,
        );
    });
});

// Persistent TOC sidebar (PR review, further round): it was still nesting a
// container's own children beneath it (Videos and Transcripts' 11
// subchapters, Background Materials' 6 sections) in a usa-sidenav__sublist
// -- correct in isolation, but not what was wanted once every division
// became its own standalone article: the persistent nav should list only
// the top-level articles, flat, since a nested division's own list of
// content lives on its container's own page instead (the same link list
// tested above), not duplicated into the sidebar too.
describe("TOC sidebar: flat, top-level articles only", () => {
    it("2010-southeast-asia: lists exactly the 5 top-level articles, no nested children", () => {
        cy.visit("conferences/2010-southeast-asia/secretary-clinton");
        cy.get("nav[aria-label='Table of contents'] ul.usa-sidenav > li").should(
            "have.length",
            5,
        );
        cy.get("nav[aria-label='Table of contents'] ul.usa-sidenav__sublist").should("not.exist");
        [
            "Program",
            "Videos and Transcripts",
            "Vietnam Photo Gallery",
            "Background Materials",
            "Post-Conference Reviews",
        ].forEach((label) => {
            cy.get("nav[aria-label='Table of contents']").contains("a", label).should("exist");
        });
        // None of the nested subchapter/section titles appear as entries.
        cy.get("nav[aria-label='Table of contents']").should(
            "not.contain.text",
            "Address by Dr. Henry A. Kissinger",
        );
    });
});
