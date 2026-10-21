// The app serves only its own API specs: the build leaves the base profile's
// modules/lib/api.json out of the router (build.xml, target app-routes), so
// every operation declared there answers like an unknown path.

import libApi from "../../../../modules/lib/api.json";

// The generated controller.xql sends these paths to dedicated entry points
// that load lib/api.json themselves. Only the production build
// (ant -Dproduction=true) routes them through api.xql as well. Run with
// --env PRODUCTION_BUILD=true against that build.
const entryPointPaths = [
    /^\/+api\/+(?:odd|lint)/,
    /^\/+api\/+actions\/+fix-odds$/,
    /\/+tex$/,
    /\/+api\/+(?:actions\/reindex|actions\/file-sync)$/,
];

const productionBuild = String(Cypress.env("PRODUCTION_BUILD")) === "true";

const sample = (param) => {
    if (param.schema?.enum) return param.schema.enum[0];
    if (param.schema?.type === "integer") return "1";
    return "base-route-test";
};

const operations = Object.entries(libApi.paths).flatMap(([path, item]) =>
    ["get", "put", "post", "delete"]
        .filter((method) => item[method])
        .map((method) => {
            const params = (item[method].parameters || []).filter((p) => p.in === "path");
            const url = params.reduce((u, p) => u.replace(`{${p.name}}`, sample(p)), path);
            return {
                method: method.toUpperCase(),
                url: url.replace(/^\//, ""),
                entryPoint: entryPointPaths.some((re) => re.test(path)),
            };
        }),
);

const send = ({ method, url }) =>
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

describe("base profile routes", () => {
    it("an unknown path answers with the 404 page", () => {
        send({ method: "GET", url: "api/does-not-exist" }).then(expectNotFoundPage);
    });

    operations
        .filter((op) => productionBuild || !op.entryPoint)
        .forEach((op) => {
            it(`${op.method} /${op.url} answers like an unknown path`, () => {
                send(op).then(expectNotFoundPage);
            });
        });

    it("the generic path cannot reach other resources", () => {
        send({ method: "GET", url: "base-route-test.md?suffix=/../controller.xql" }).then(
            expectNotFoundPage,
        );
    });

    it("the ODD editor page is not served", () => {
        send({ method: "GET", url: "odd-editor.html" }).then(expectNotFoundPage);
    });
});

describe("top-level pages with their own routes", () => {
    ["/", "/index.html"].forEach((url) => {
        it(`GET ${url} serves the landing page`, () => {
            send({ method: "GET", url }).then((r) => {
                expect(r.status).to.eq(200);
                expect(r.headers["content-type"]).to.contain("text/html");
            });
        });
    });
});

if (!productionBuild) {
    describe("kept in the development build", () => {
        it("GET /api/odd still lists the ODDs", () => {
            send({ method: "GET", url: "api/odd" }).then((r) => {
                expect(r.status).to.eq(200);
                expect(r.headers["content-type"]).to.contain("application/json");
            });
        });
    });
}
