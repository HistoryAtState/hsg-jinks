// The controller's root redirects build their Location from $config:context-path,
// which is "" behind a proxy (X-Forwarded-Host set).
describe("Root redirects", () => {
    const root = Cypress.config("baseUrl").replace(/\/$/, "");
    const appPath = new URL(root).pathname;
    const proxied = { "X-Forwarded-Host": "history.example.org" };

    it("redirects / to the landing page", () => {
        cy.request({ url: `${root}/`, followRedirect: false }).then((response) => {
            expect(response.status).to.eq(302);
            expect(response.headers.location).to.eq(`${appPath}/index.html`);
        });
    });

    it("redirects / to the landing page at the site root behind a proxy", () => {
        cy.request({ url: `${root}/`, headers: proxied, followRedirect: false }).then((response) => {
            expect(response.status).to.eq(302);
            expect(response.headers.location).to.eq("/index.html");
        });
    });

    it("redirects the app path without a trailing slash to the site root behind a proxy", () => {
        cy.request({ url: root, headers: proxied, followRedirect: false }).then((response) => {
            expect(response.status).to.eq(302);
            expect(response.headers.location).to.eq("/");
        });
    });
});
