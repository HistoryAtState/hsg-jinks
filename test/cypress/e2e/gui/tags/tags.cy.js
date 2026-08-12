// Covers #1178 "Discover resources by subject tag" -- the full /tags
// section flow (landing > full taxonomy / drill-down > tag page > linked
// resource) and its acceptance criteria: URL preservation, 404 handling,
// /tags/all never captured as a tag id, taxonomy links, ptr cross-reference
// resolution, drill-down hit counts matching the target page, live-computed
// landing counts, and non-blank empty/dig-deeper states.
//
// Data-derived counts (taxonomy subjects, tagged volumes/bios) come from the
// "tags" external data package (HistoryAtState/tags, fetched like the other
// 7 external packages) plus whatever FRUS volumes/secretary bios happen to
// carry tei:keywords locally -- both grow over time, so assertions on those
// counts use a lower bound, not an exact match, per CLAUDE.md's guidance for
// data-derived content from these packages.
//
// baseUrl is http://localhost:8080/exist/apps/hsg-jinks (cypress.config.cjs).
// Override for a remapped host port, e.g.
// `cypress run --config baseUrl=http://localhost:8095/exist/apps/hsg-jinks`.

describe("tags section landing and full taxonomy", () => {
    it("landing page shows the reference site's narrative, with live-computed counts and links into the section", () => {
        cy.visit("tags");
        cy.get("main h1").should("have.text", "Tags");

        cy.get("main p").eq(0).invoke("text").then((text) => {
            expect(text).to.include("Subject Taxonomy of the History of U.S.");
            const match = text.match(/covers\s+(\d+)\s+subjects/);
            expect(parseInt(match[1], 10)).to.be.at.least(500);
        });
        cy.get("main p").eq(1).invoke("text").then((text) => {
            const match = text.match(/website:\s*(\d+)/);
            expect(parseInt(match[1], 10)).to.be.at.least(60);
        });
        cy.get("main a[href$='/tags/people']").should("exist");
        cy.get("main a[href$='/tags/places']").should("exist");
        cy.get("main a[href$='/tags/topics']").should("exist");
        cy.get("main a[href$='/departmenthistory/people/secretaries']").should("exist");
        cy.get("main a[href$='/historicaldocuments']").should("exist");

        cy.contains("main a", "the full").click();
        cy.location("pathname").should("match", /\/tags\/all$/);
    });

    it("/tags/all renders the whole taxonomy as one nested list, every entry linking to its own tag page", () => {
        cy.visit("tags/all");
        cy.get("main h1").should("contain.text", "Full Taxonomy");
        // Data-derived count (the taxonomy package can grow) -- lower bound only.
        cy.get("main li").should("have.length.at.least", 500);
        cy.contains("main a", "Reagan, Ronald").should("have.attr", "href").and("match", /\/tags\/reagan-ronald$/);
    });

    it("/tags/all is served as the taxonomy listing, never captured as tag id \"all\"", () => {
        cy.request("tags/all").its("status").should("eq", 200);
        cy.visit("tags/all");
        // The literal /tags/all route, not tagapi:view's browse template --
        // confirmed by the page title, not just the URL, since a
        // mis-routed request would still show a 200 at this same path.
        cy.get("main h1").should("contain.text", "Full Taxonomy");
    });
});

describe("tag browse page: direct hits, dig-deeper, and empty states", () => {
    it("a directly-tagged FRUS volume renders as a direct hit, linking into historicaldocuments", () => {
        cy.visit("tags/reagan-ronald");
        cy.get("main h1").should("contain.text", "Reagan, Ronald");
        cy.contains("main h2", "Foreign Relations").parent().within(() => {
            cy.get("a").should("have.length.at.least", 1);
        });
        cy.contains("main .usa-collection a", "Foreign Relations of the United States").click();
        cy.location("pathname").should("match", /\/historicaldocuments\/frus1981-88v05$/);
    });

    it("a directly-tagged Secretary of State biography renders as a direct hit, linking into departmenthistory", () => {
        cy.visit("tags/acheson-dean-gooderham");
        cy.get("main h1").should("contain.text", "Acheson, Dean Gooderham");
        cy.contains("main h2", "Secretaries of State").should("exist");
        cy.contains("main .usa-collection a", "Dean Gooderham Acheson").click();
        cy.location("pathname").should("match", /\/departmenthistory\/people\/acheson-dean-gooderham$/);
    });

    it("a category with no direct hits but tagged descendants shows the dig-deeper drill-down, hit counts matching the target pages", () => {
        cy.visit("tags/presidents");
        cy.get("main h1").should("contain.text", "Presidents");
        cy.contains("main p", "Please dig deeper");
        // The drill-down's own count for reagan-ronald must equal the
        // number of resources actually listed on /tags/reagan-ronald
        // itself (#1178's own acceptance criterion).
        cy.contains(".tags-drilldown a", "Reagan, Ronald").find(".usa-tag").invoke("text").then((countText) => {
            const drilldownCount = parseInt(countText, 10);
            cy.visit("tags/reagan-ronald");
            cy.get("main .usa-collection__item").its("length").should("eq", drilldownCount);
        });
    });

    it("an entry with nothing tagged anywhere beneath it renders a non-blank empty state", () => {
        // washington-george, not lincoln-abraham: FRUS coverage starts in
        // 1861, so a Washington entry can never gain a tagged volume, while
        // Lincoln legitimately picked one up as soon as frus1861 joined the
        // deployed data (the spec was written against a two-volume sample).
        cy.visit("tags/washington-george");
        cy.get("main h1").should("contain.text", "Washington, George");
        cy.contains("main p", "No resources have been tagged");
    });

    it("a definition's ptr cross-reference resolves to a working link to the target tag page", () => {
        cy.visit("tags/military-intervention-presence-and-withdrawal");
        cy.contains("main a", "Warfare").click();
        cy.location("pathname").should("match", /\/tags\/warfare$/);
    });

    it("an unknown tag id returns 404 with the error page; a valid id returns 200", () => {
        cy.request({ url: "tags/not-a-real-tag-id", failOnStatusCode: false }).its("status").should("eq", 404);
        cy.request("tags/reagan-ronald").its("status").should("eq", 200);
    });
});

describe("volume-landing sidebar tags coupling", () => {
    it("a tagged FRUS volume's landing page links each of its own tags into the tags section", () => {
        cy.visit("historicaldocuments/frus1981-88v05");
        cy.get(".tags-panel").should("exist").within(() => {
            cy.contains("a", "Arms Control and Disarmament").should("have.attr", "href").and("match", /\/tags\/arms-control-and-disarmament$/);
        });
        cy.get(".tags-panel").contains("a", "Arms Control and Disarmament").click();
        cy.location("pathname").should("match", /\/tags\/arms-control-and-disarmament$/);
    });
});
