// Routes of the generated API that this app does not serve
// (modules/disabled-api.json): each answers like an unknown path, whoever
// asks. The other methods of the same paths still reach their handlers.

const disabled = [
    ["GET", "api/parts/disabled-test.xml/json"],
    ["PUT", "api/document/disabled-test.xml"],
    ["POST", "api/convert"],
    ["POST", "api/preview"],
    ["GET", "api/apps/download"],
    ["GET", "api/nlp/entities/disabled-test.xml"],
    ["GET", "api/nlp/patterns/disabled-test.xml"],
    ["GET", "api/nlp/strings/disabled-test"],
    ["POST", "api/nlp/strings"],
    ["GET", "api/nlp/text/disabled-test.xml"],
    ["GET", "api/nlp/status"],
    ["GET", "api/nlp/status/models"],
    ["GET", "api/nlp/train/disabled-test"],
    ["GET", "api/nlp/log/1"],
    ["GET", "api/nlp/data/disabled-test"],
    ["POST", "api/register/person/disabled-test"],
    ["PUT", "api/register"],
    ["DELETE", "api/register/disabled-test"],
    ["PUT", "api/register/disabled-test"],
    ["GET", "api/forms/template/person-default"],
];

// The generated controller.xql sends these to dedicated entry points; only
// the production build (ant -Dproduction=true) routes them through
// disabled-api.json. Run with --env PRODUCTION_BUILD=true against that build.
const productionOnly = [
    ["GET", "api/odd"],
    ["POST", "api/odd"],
    ["GET", "api/odd/teipublisher.odd"],
    ["POST", "api/odd/disabled-test"],
    ["PUT", "api/odd/disabled-test.odd"],
    ["DELETE", "api/odd/disabled-test.odd"],
    ["POST", "api/lint"],
    ["POST", "api/actions/fix-odds"],
    ["GET", "api/document/disabled-test.xml/tex"],
];

const productionBuild = String(Cypress.env("PRODUCTION_BUILD")) === "true";

const send = ([method, url]) =>
    cy.api({
        method,
        url,
        body: ["PUT", "POST"].includes(method) ? "<TEI/>" : undefined,
        headers: { "Content-Type": "application/xml" },
        failOnStatusCode: false,
    });

const expectNotFoundPage = (r) => {
    expect(r.status).to.eq(404);
    expect(r.headers["content-type"]).to.contain("text/html");
    expect(r.body).to.contain("Page not found");
};

describe("disabled generator routes", () => {
    it("an unknown path answers with the 404 page", () => {
        send(["GET", "api/does-not-exist"]).then(expectNotFoundPage);
    });

    disabled.forEach((route) => {
        it(`${route[0]} /${route[1]} answers like an unknown path`, () => {
            send(route).then(expectNotFoundPage);
        });
    });

    it("stay disabled for a logged-in user", () => {
        cy.login();
        disabled.forEach((route) => {
            send(route).then(expectNotFoundPage);
        });
    });
});

if (productionBuild) {
    describe("disabled in the production build", () => {
        productionOnly.forEach((route) => {
            it(`${route[0]} /${route[1]} answers like an unknown path`, () => {
                send(route).then(expectNotFoundPage);
            });
        });

        it("stay disabled for a logged-in user", () => {
            cy.login();
            productionOnly.forEach((route) => {
                send(route).then(expectNotFoundPage);
            });
        });
    });
} else {
    describe("kept in the development build", () => {
        it("GET /api/odd still lists the ODDs", () => {
            send(["GET", "api/odd"]).then((r) => {
                expect(r.status).to.eq(200);
                expect(r.headers["content-type"]).to.contain("application/json");
            });
        });
    });
}

describe("other methods on the disabled paths", () => {
    it("GET /api/register/{id} still reaches the register handler", () => {
        send(["GET", "api/register/disabled-test"]).its("status").should("eq", 200);
    });

    it("GET /api/register/{type}/{id} still reaches the register handler", () => {
        send(["GET", "api/register/person/disabled-test"]).then((r) => {
            expect(r.status).to.eq(404);
            expect(r.headers["content-type"]).to.contain("application/json");
        });
    });

    it("GET /api/document/{id} still reaches the document handler", () => {
        send(["GET", "api/document/disabled-test.xml"]).then((r) => {
            expect(r.status).to.eq(404);
            expect(r.headers["content-type"]).to.contain("application/json");
        });
    });

    it("DELETE /api/document/{id} still requires a login", () => {
        send(["DELETE", "api/document/disabled-test.xml"]).its("status").should("eq", 401);
    });
});
