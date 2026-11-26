// HEAD is answered like GET, without a body (eeditiones/roaster#181), and
// OPTIONS lists the methods of the matched route (eeditiones/roaster#89).
// Both are handled in controller.xql.
describe("HEAD and OPTIONS", () => {
    const root = Cypress.config("baseUrl").replace(/\/$/, "");

    const send = (method, url, headers = {}) =>
        cy.request({ method, url: `${root}${url}`, headers, followRedirect: false, failOnStatusCode: false });

    it("HEAD answers like GET, without a body", () => {
        send("GET", "/departmenthistory").then((get) => {
            send("HEAD", "/departmenthistory").then((head) => {
                expect(head.status).to.eq(200);
                expect(head.body).to.be.empty;
                expect(head.headers["content-type"]).to.eq(get.headers["content-type"]);
                expect(head.headers["last-modified"]).to.eq(get.headers["last-modified"]);
            });
        });
    });

    it("HEAD answers 304 when not modified since", () => {
        send("GET", "/departmenthistory").then((get) => {
            send("HEAD", "/departmenthistory", { "If-Modified-Since": get.headers["last-modified"] })
                .its("status").should("eq", 304);
        });
    });

    it("HEAD answers 404 for a path no route serves", () => {
        send("HEAD", "/no-such-page").its("status").should("eq", 404);
    });

    it("OPTIONS lists only the methods a page defines", () => {
        send("OPTIONS", "/departmenthistory").then((res) => {
            expect(res.status).to.eq(204);
            expect(res.headers.allow).to.eq("GET, HEAD, OPTIONS");
            expect(res.headers["access-control-allow-methods"]).to.eq("GET, HEAD, OPTIONS");
        });
    });

    it("OPTIONS answers 404 for a path no route serves", () => {
        send("OPTIONS", "/no-such-page").its("status").should("eq", 404);
    });

    it("pages send no Cache-Control of their own", () => {
        send("GET", "/departmenthistory").its("headers").should("not.have.property", "cache-control");
    });
});
