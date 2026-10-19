// Official U.S. government banner (OP#1050, made site-wide including error
// pages in OP#1412): the standard USWDS banner, wired as an opt-in via
// theme.banner in config.json (markup from the theme-sourced
// templates/banner.html). Normal pages pick it up via templates/menu.html,
// which every page extending templates/layouts/base.html includes; the
// three standalone error templates (error-404.html, error-400.html,
// error-page.html) don't extend base.html, so each carries its own
// [% include "templates/banner.html" %] -- see the comment beside each one.
// error-page.html (the generic template-compile-error diagnostics page) has
// no stable URL to trigger it in a test and so isn't exercised below; the
// 404 and 400 pages below are the ones with a reliable trigger.
//
// The spec follows the flag rather than hard-coding one state: config.json
// is what gets built and deployed, so it is the source of truth for
// whether the banner must be visible or absent. OP#1412 requires it on
// *every* page, current and future, so this file asserts presence/absence
// across a representative sample of page kinds (mirroring the sample
// footer.cy.js uses for the same "site-wide chrome" claim) rather than one
// page, plus both error-page classes that don't go through base.html.

const { theme } = require("../../../../../config.json");
const bannerEnabled = theme.banner === true;

const VOLUME = "historicaldocuments/frus1981-88v05";

// Representative sample of normal (200-status) page kinds -- new page
// templates extend templates/layouts/base.html by default, so they inherit
// the banner automatically; this is a spot check, not the enforcement point.
const NORMAL_PAGES = [
    ["landing", "index.html"],
    ["search", "search"],
    ["about", "about"],
    ["volume landing", VOLUME],
    ["chapter", `${VOLUME}/ch1`],
    ["document", `${VOLUME}/d1`],
];

// The standalone error templates: each must carry its own banner include
// (see comment above) since none of them extend base.html.
const ERROR_PAGES = [
    ["404", { url: "asdfg", failOnStatusCode: false }],
    ["400", { url: "search?q=%22unbalanced", failOnStatusCode: false }],
];

if (bannerEnabled) {
    describe("government banner (enabled in config.json)", () => {
        NORMAL_PAGES.forEach(([kind, path]) => {
            it(`renders on the ${kind} page`, () => {
                cy.visit(path);
                cy.get(".usa-banner .usa-banner__header-text", { timeout: 15000 })
                    .should("contain.text", "An official website of the United States government");
            });
        });

        ERROR_PAGES.forEach(([status, visitOptions]) => {
            it(`renders on the ${status} error page`, () => {
                cy.visit(visitOptions);
                cy.get(".usa-banner .usa-banner__header-text", { timeout: 15000 })
                    .should("contain.text", "An official website of the United States government");
            });
        });

        it("renders above the navbar on the landing page", () => {
            cy.visit("index.html");
            cy.get(".usa-banner").then(($b) => {
                cy.get(".usa-navbar").then(($n) => {
                    expect($b[0].getBoundingClientRect().top).to.be.lessThan($n[0].getBoundingClientRect().top);
                });
            });
        });

        it("expands the guidance accordion", () => {
            cy.visit("index.html");
            cy.get(".usa-banner__button", { timeout: 15000 }).click();
            cy.get("#gov-banner-default").should("be.visible")
                .and("contain.text", "Official websites use .gov");
        });

        // Figma "USA Header" banner (I4336:64988;4159:47550): white text on
        // blue-70v, "Here's how you know" in #73b3e7. Without the flag (see
        // hsg-theme.css) the text, and the guidance below it, start at the
        // logo's edge.
        it("follows the theme's colours and lines up with the logo", () => {
            cy.viewport(1440, 900);
            cy.visit("index.html");
            cy.get(".usa-banner").should("have.css", "background-color", "rgb(11, 71, 120)");
            cy.get(".usa-banner__header-text").should("have.css", "color", "rgb(255, 255, 255)");
            cy.get(".usa-banner__button-text").should("have.css", "color", "rgb(115, 179, 231)");
            cy.get(".usa-logo").then(($logo) => {
                const logoLeft = $logo[0].getBoundingClientRect().left;
                cy.get(".usa-banner__header-text").should(($t) => {
                    expect($t[0].getBoundingClientRect().left).to.be.closeTo(logoLeft, 1);
                });
                cy.get(".usa-banner__button").click();
                cy.get(".usa-banner__content")
                    .should("be.visible")
                    .and("have.css", "color", "rgb(255, 255, 255)")
                    .and("have.css", "background-color", "rgba(0, 0, 0, 0)");
                cy.get(".usa-banner__icon").first().should(($i) => {
                    expect($i[0].getBoundingClientRect().left).to.be.closeTo(logoLeft, 1);
                });
            });
        });
    });
} else {
    describe("government banner (disabled in config.json)", () => {
        NORMAL_PAGES.forEach(([kind, path]) => {
            it(`does not render on the ${kind} page`, () => {
                cy.visit(path);
                cy.get("body", { timeout: 15000 }).should("exist");
                cy.get(".usa-banner").should("not.exist");
            });
        });

        ERROR_PAGES.forEach(([status, visitOptions]) => {
            it(`does not render on the ${status} error page`, () => {
                cy.visit(visitOptions);
                cy.get("body", { timeout: 15000 }).should("exist");
                cy.get(".usa-banner").should("not.exist");
            });
        });
    });
}
