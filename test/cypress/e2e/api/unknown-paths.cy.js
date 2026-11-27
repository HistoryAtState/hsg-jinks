// Paths that do not equal their route (OP#1527). Roaster 1.x anchors route
// patterns at the start only, so a fixed route such as /about also matched
// /about/anything and answered with the About page and 200. The path-match
// middleware (modules/path-match.xqm) answers those with 404, and redirects a
// trailing or repeated slash permanently to the path without it, as the live
// site does.

import opds from "../../../../modules/opds-catalog-api.json";
import menu from "../../../../modules/menu-api.json";
import services from "../../../../modules/services-api.json";
import opengov from "../../../../modules/opengov-api.json";
import conferences from "../../../../modules/conferences-api.json";
import education from "../../../../modules/education-api.json";
import developer from "../../../../modules/developer-api.json";
import search from "../../../../modules/search-api.json";
import milestones from "../../../../modules/milestones-api.json";
import tags from "../../../../modules/tags-api.json";
import about from "../../../../modules/about-api.json";
import departmenthistory from "../../../../modules/departmenthistory-api.json";
import countries from "../../../../modules/countries-api.json";
import hsg from "../../../../modules/hsg-api.json";

// The specs modules/lib/api.xql routes (build.xml, target app-routes).
const specs = [opds, menu, services, opengov, conferences, education, developer, search,
    milestones, tags, about, departmenthistory, countries, hsg];

// GET routes without path parameters. A route that requires a query
// parameter answers 400 before the path is checked, so it is left out.
const fixedRoutes = specs.flatMap((spec) =>
    Object.entries(spec.paths)
        .filter(([path, item]) => item.get && !path.includes("{"))
        .filter(([, item]) => !(item.get.parameters || []).some((p) => p.in === "query" && p.required))
        .map(([path]) => path));

describe("Unknown paths below fixed routes", () => {
    it("covers the fixed routes of every routed spec", () => {
        expect(fixedRoutes.length).to.be.at.least(60);
    });

    fixedRoutes.forEach((route) => {
        it(`${route}/no-such-page answers 404`, () => {
            const path = route === "/" ? "/no-such-page" : `${route}/no-such-page`;
            cy.request({ url: path.replace(/^\//, ""), failOnStatusCode: false, followRedirect: false })
                .its("status").should("eq", 404);
        });
    });

    it("renders the Page not found page for a page route", () => {
        cy.request({ url: "about/no-such-page", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
            expect(response.body).to.contain("Page not found");
        });
    });
});

// Static files are served at the app root only (controller.xql): below any
// path, every page address could be extended into an endless number of
// addresses answering 200.
describe("Static files below a page path", () => {
    it("serves static files at the app root", () => {
        cy.request("resources/css/components.css").its("status").should("eq", 200);
        cy.request("resources/i18n/app/en.json").its("status").should("eq", 200);
    });

    ["about/resources/css/components.css", "historicaldocuments/about-frus/resources/i18n/app/en.json",
        "x/y/transform/hsg-jinks.css", "countries/cuba/templates/layouts/base.html"].forEach((path) => {
        it(`answers /${path} with 404`, () => {
            cy.request({ url: path, failOnStatusCode: false, followRedirect: false })
                .its("status").should("eq", 404);
        });
    });
});

describe("Trailing and repeated slashes", () => {
    const root = Cypress.config("baseUrl").replace(/\/$/, "");
    const appPath = new URL(root).pathname;
    const proxied = { "X-Forwarded-Host": "history.example.org" };

    const redirects = (from, to, headers = {}) =>
        cy.request({ url: `${root}${from}`, headers, followRedirect: false }).then((response) => {
            expect(response.status, from).to.eq(301);
            expect(response.headers.location, from).to.eq(to);
        });

    it("redirects a fixed route's trailing slash", () => redirects("/about/", `${appPath}/about`));

    it("redirects a parameter route's trailing slash", () => redirects("/countries/cuba/", `${appPath}/countries/cuba`));

    it("keeps the query string", () => redirects("/about/?a=1&b=2", `${appPath}/about?a=1&b=2`));

    it("collapses repeated slashes", () => redirects("/historicaldocuments//about-frus/", `${appPath}/historicaldocuments/about-frus`));

    it("redirects to the site path behind a proxy", () => redirects("/about/", "/about", proxied));

    it("redirects the OPDS catalog too", () => redirects("/api/v1/catalog/all/", `${appPath}/api/v1/catalog/all`));

    it("leaves the landing page at /", () => {
        cy.request({ url: `${root}/`, followRedirect: false }).its("status").should("eq", 200);
    });
});
