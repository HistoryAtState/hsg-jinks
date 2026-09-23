// Site favicon (OP#1415): the Department of State seal already used on
// history.state.gov, replacing the default Jinks/TEI Publisher logo. The layout
// declares a single .ico link, as the live site does; leftover size-specific
// PNG links would win over it in Chrome and keep showing the old logo.

const iconLinks = (body) => [...body.matchAll(/<link[^>]*rel="[^"]*icon[^"]*"[^>]*>/g)].map((m) => m[0]);

describe("favicon (OP#1415)", () => {
    it("a content page declares only the .ico favicon", () => {
        cy.request("about/faq").its("body").then((body) => {
            const links = iconLinks(body);
            expect(links, "icon links").to.have.length(1);
            expect(links[0]).to.match(/href="[^"]*\/resources\/images\/favicon\.ico"/);
        });
    });

    it("the 404 page declares only the .ico favicon", () => {
        cy.request({ url: "asdfg", failOnStatusCode: false }).its("body").then((body) => {
            const links = iconLinks(body);
            expect(links, "icon links").to.have.length(1);
            expect(links[0]).to.match(/href="[^"]*\/resources\/images\/favicon\.ico"/);
        });
    });

    it("serves the State Department seal icon, not the Jinks default", () => {
        cy.request({ url: "resources/images/favicon.ico", encoding: "binary" }).then((r) => {
            expect(r.status).to.eq(200);
            expect(r.headers["content-type"]).to.match(/^image\//);
            // The seal .ico is 2902 bytes (16px + 24px frames); the Jinks
            // default it replaces is 34494 bytes (5 frames up to 64px).
            expect(r.body.length).to.eq(2902);
        });
    });
});
