// Covers OP#1097/OP#1158 "Find an answer or committee record without knowing
// which publication holds it" -- the About Us section landing page, the
// FAQ/HAC TOC + interior pages (the monograph-toc/monograph-section pattern
// shared with departmenthistory's Short History/Buildings), the section's
// five static pages, and the site-wide footer Content Warning link.
//
// baseUrl comes from CYPRESS_BASE_URL (this worktree's .env) -- see
// cypress.config.cjs and README "Parallel worktrees".

describe("About Us section landing page", () => {
    it("lists links to every about/* subsection", () => {
        cy.visit("about");
        cy.get("main h1").should("contain.text", "About Us");
        cy.get("nav[aria-label='Side navigation'], .usa-sidenav").should("exist");
        cy.contains(".usa-sidenav a", "Frequently Asked Questions").should("have.attr", "href").and("match", /\/about\/faq$/);
        cy.contains(".usa-sidenav a", "Historical Advisory Committee").should("have.attr", "href").and("match", /\/about\/hac$/);
    });

    it("sidebar order and labels match the reference site's aside#sections exactly", () => {
        // https://history.state.gov/about (read-only mirror: /exist/apps/hsg-shell/about)
        // lists these 7 entries in this order, with no separate "Overview"
        // self-link -- confirmed live, not just against controller.xql's
        // route order.
        cy.visit("about");
        cy.get(".usa-sidenav a").then(($links) => {
            const labels = [...$links].map((el) => el.textContent.trim());
            expect(labels).to.deep.equal([
                "Contact Us",
                "Frequently Asked Questions",
                "The Historian",
                "Historical Advisory Committee",
                "Recent Publications",
                "Reports",
                "Content Warning",
            ]);
        });
    });
});

describe("FAQ: TOC, section, prev/next, exact-division guard", () => {
    it("TOC lists questions, opens a section, and the sidebar marks it current", () => {
        cy.visit("about/faq");
        cy.get("main h1").should("contain.text", "Frequently Asked Questions");
        cy.contains(".usa-sidenav a", "Foreign Relations of the United States").click();
        cy.location("pathname").should("match", /faq\/what-is-frus$/);
        cy.get("nav[aria-label='Side navigation'] a.usa-current").should("exist");
    });

    it("breadcrumb links back through the FAQ TOC", () => {
        cy.visit("about/faq/what-is-frus");
        cy.get("nav[aria-label='breadcrumb']").first().within(() => {
            cy.contains("a", "About Us");
            cy.contains("li", "Where can I find information");
        });
        cy.get("nav[aria-label='breadcrumb']").first().contains("a", "Frequently Asked Questions").click();
        cy.location("pathname").should("match", /\/about\/faq$/);
    });

    it("rejects a whitespace-mangled or unknown section id (exact-division guard)", () => {
        cy.request({ url: "about/faq/what-is-frus%20", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
        cy.request({ url: "about/faq/no-such-question", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
    });
});

describe("HAC: TOC, nested meeting-notes subchapters, video embed, exact-division guard", () => {
    it("TOC lists top-level sections plus a Meeting Notes chapter", () => {
        cy.visit("about/hac");
        cy.get("main h1").should("contain.text", "Historical Advisory Committee");
        cy.contains(".usa-sidenav a", "Members").should("have.attr", "href").and("match", /\/about\/hac\/members$/);
        cy.contains(".usa-sidenav a", "Meeting Notes").should("exist");
    });

    it("opens a meeting-notes subchapter and shows its Brightcove video embed", () => {
        // The raw video-js markup pasted into the TEI (with its third-party
        // inline script) is replaced by the ODD's CSP-safe iframe embed --
        // the conferences xhtml:div model (OP#1099/#1114), which also covers
        // HAC's videos since they share the same encoding shape. This spec
        // predates that model (OP#1158) and originally asserted the raw
        // <video> tag.
        cy.request("about/hac/September-2024").its("body")
            .should("match", /<iframe src="https:\/\/players\.brightcove\.net\/[^"]*videoId=6365048608112"/)
            .and("not.match", /<script[^>]*players\.brightcove\.net/);
    });

    it("mixed-case and lowercase meeting subchapter ids both resolve (no casing normalization)", () => {
        cy.visit("about/hac/March-2025");
        cy.get("main h1").should("exist");
        cy.visit("about/hac/december-1996");
        cy.get("main h1").should("exist");
    });

    it("rejects a whitespace-mangled or unknown section id (exact-division guard)", () => {
        cy.request({ url: "about/hac/members%20", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
        cy.request({ url: "about/hac/no-such-meeting", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
    });
});

describe("Static pages: contact-us, the-historian, reports, content-warning", () => {
    it("Contact Us page reads and links the FAQ", () => {
        cy.visit("about/contact-us");
        cy.get("main h1").should("contain.text", "Contact Us");
        cy.contains("a", "Frequently Asked Questions").should("have.attr", "href").and("match", /\/about\/faq$/);
    });

    it("The Historian page lists past directors", () => {
        cy.visit("about/the-historian");
        cy.get("main h1").should("contain.text", "The Historian");
        cy.contains("li", "John Powers").should("exist");
    });

    it("Reports page links its PDF report", () => {
        cy.visit("about/reports");
        cy.get("main h1").should("contain.text", "Reports to Congress");
        cy.contains("a", "Report to Congress").should("have.attr", "href").and("match", /static\.history\.state\.gov/);
    });

    it("Content Warning page shows the notice", () => {
        cy.visit("about/content-warning");
        cy.get("main h1").should("contain.text", "Content Warning");
        cy.get(".usa-alert").should("exist");
    });
});

describe("Recent Publications: cross-collection FRUS listing", () => {
    it("renders the page even when no volume falls in the current/prior year window", () => {
        // frus-data-jinks' baseline is one fixed sample volume with an old
        // publication date, so this dev environment's list is legitimately
        // empty -- this only checks the page itself renders without error,
        // not a volume count (see CLAUDE.md "Cypress assertions on
        // data-package counts": counts here depend on upstream data, not on
        // this section's own code).
        cy.visit("about/recent-publications");
        cy.get("main h1").should("contain.text", "Recent Publications");
    });
});

describe("Content Warning link is reachable from outside the About Us section", () => {
    it("footer links to /about/content-warning from a non-about page", () => {
        cy.visit("historicaldocuments");
        cy.get("footer").contains("a", "Content Warning").should("have.attr", "href").and("match", /\/about\/content-warning$/);
    });
});
