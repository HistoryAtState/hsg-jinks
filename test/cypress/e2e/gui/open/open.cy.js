// Covers OP#1104 "Render HSG open data feeds" -- the three static
// Open Government Initiative pages (landing, "Latest Volumes" explainer,
// bibliographic-metadata explainer) plus the URL-preservation and 404
// acceptance criteria from OP#1198. The two machine feeds
// (frus-latest.xml, frus-metadata.xml) are XML, not HTML pages, so their
// status/content-type/shape are asserted via cy.request rather than a
// rendered-page visit.
//
// baseUrl comes from CYPRESS_BASE_URL (this worktree's .env) -- see
// cypress.config.cjs and README "Parallel worktrees".

describe("Open Government Initiative landing page", () => {
    it("renders the overview and links to both datasets", () => {
        cy.visit("open");
        cy.get("main h1").should("contain.text", "Open Government Initiative");
        cy.contains("main a", "Bibliographic Metadata of the")
            .should("have.attr", "href")
            .and("match", /\/open\/frus-metadata$/);
        cy.contains("main a", "Latest Volumes of")
            .should("have.attr", "href")
            .and("match", /\/open\/frus-latest$/);
    });

    it("lists both datasets in the sidebar", () => {
        cy.visit("open");
        cy.get("aside.before ul.usa-in-page-nav__list").within(() => {
            cy.contains("a", "Bibliographic Metadata of the").should("have.attr", "href").and("match", /\/open\/frus-metadata$/);
            cy.contains("a", "Latest Volumes of").should("have.attr", "href").and("match", /\/open\/frus-latest$/);
        });
    });
});

describe("Latest Volumes explainer page", () => {
    it("links to the Atom feed and the Data.gov catalog entry", () => {
        cy.visit("open/frus-latest");
        cy.get("main h1").should("contain.text", "Latest Volumes");
        cy.contains("main a", "View the feed").should("have.attr", "href").and("match", /\/open\/frus-latest\.xml$/);
        cy.contains("main a", "Data.gov catalog entry").should("have.attr", "href", "https://catalog.data.gov/dataset/latest-volumes-of-foreign-relations-of-the-united-states");
    });

    it("breadcrumb links back to the Open Government Initiative landing page", () => {
        cy.visit("open/frus-latest");
        cy.get("nav[aria-label='breadcrumb']").first().within(() => {
            cy.contains("a", "Open Government Initiative").click();
        });
        cy.location("pathname").should("match", /\/open$/);
    });
});

describe("Bibliographic metadata explainer page", () => {
    it("links to the XML dump and the Data.gov catalog entry", () => {
        cy.visit("open/frus-metadata");
        cy.get("main h1").should("contain.text", "Bibliographic Metadata");
        cy.contains("main a", "Download the raw data").should("have.attr", "href").and("match", /\/open\/frus-metadata\.xml$/);
        cy.contains("main a", "Data.gov catalog entry").should("have.attr", "href", "https://catalog.data.gov/dataset/bibliographical-metadata-of-the-foreign-relations-of-the-united-states-series");
    });
});

describe("Machine feeds (OP#1195, OP#1196)", () => {
    it("frus-latest.xml is an Atom feed served as text/xml with at least one entry", () => {
        cy.request("open/frus-latest.xml").then((response) => {
            expect(response.status).to.eq(200);
            expect(response.headers["content-type"]).to.match(/^text\/xml/);
            expect(response.body).to.match(/<feed xmlns="http:\/\/www\.w3\.org\/2005\/Atom">/);
            expect(response.body).to.match(/<entry>/);
        });
    });

    it("frus-latest.xml honors n and rejects a non-integer n with a clean 4xx", () => {
        cy.request("open/frus-latest.xml?n=1").then((response) => {
            expect(response.status).to.eq(200);
            expect(response.body.match(/<entry>/g)?.length).to.eq(1);
        });
        cy.request({ url: "open/frus-latest.xml?n=abc", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.be.within(400, 499);
        });
    });

    it("frus-metadata.xml is the bespoke bibliographic dump served as text/xml", () => {
        cy.request("open/frus-metadata.xml").then((response) => {
            expect(response.status).to.eq(200);
            expect(response.headers["content-type"]).to.match(/^text\/xml/);
            expect(response.body).to.match(/<volumes xmlns="http:\/\/history\.state\.gov\/ns\/1\.0">/);
            expect(response.body).to.match(/<volume id="/);
        });
    });
});

describe("URL preservation and 404 handling (OP#1198 acceptance criteria)", () => {
    it("all five /open URLs resolve at their exact hsg-shell paths", () => {
        cy.request("open").its("status").should("eq", 200);
        cy.request("open/frus-latest").its("status").should("eq", 200);
        cy.request("open/frus-metadata").its("status").should("eq", 200);
        cy.request("open/frus-latest.xml").its("status").should("eq", 200);
        cy.request("open/frus-metadata.xml").its("status").should("eq", 200);
    });

    it("any other path segment under /open returns 404", () => {
        cy.request({ url: "open/no-such-page", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
    });
});
