// The landing page lives at /. The controller's root redirects build their Location
// from $config:context-path, which is "" behind a proxy (X-Forwarded-Host set).
describe("Root redirects", () => {
    const root = Cypress.config("baseUrl").replace(/\/$/, "");
    const appPath = new URL(root).pathname;
    const proxied = { "X-Forwarded-Host": "history.example.org" };

    it("serves the landing page at / without a redirect", () => {
        cy.request({ url: `${root}/`, followRedirect: false }).then((response) => {
            expect(response.status).to.eq(200);
            expect(response.headers["content-type"]).to.contain("text/html");
        });
    });

    it("redirects /index.html to /", () => {
        cy.request({ url: `${root}/index.html`, followRedirect: false }).then((response) => {
            expect(response.status).to.eq(302);
            expect(response.headers.location).to.eq(`${appPath}/`);
        });
    });

    it("keeps the query string when redirecting /index.html", () => {
        cy.request({ url: `${root}/index.html?lang=en`, followRedirect: false }).then((response) => {
            expect(response.status).to.eq(302);
            expect(response.headers.location).to.eq(`${appPath}/?lang=en`);
        });
    });

    it("redirects /index.html to the site root behind a proxy", () => {
        cy.request({ url: `${root}/index.html`, headers: proxied, followRedirect: false }).then((response) => {
            expect(response.status).to.eq(302);
            expect(response.headers.location).to.eq("/");
        });
    });

    it("redirects the app path without a trailing slash to the site root behind a proxy", () => {
        cy.request({ url: root, headers: proxied, followRedirect: false }).then((response) => {
            expect(response.status).to.eq(302);
            expect(response.headers.location).to.eq("/");
        });
    });
});
