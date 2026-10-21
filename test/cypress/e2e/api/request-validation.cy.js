// URL input on the app's own routes: ids that would leave their collection,
// query parameters the routes do not declare, and malformed numbers.

const get = (url) => cy.api({ method: "GET", url, failOnStatusCode: false });

// Resolves to /db/apps/jinks/repo.xml if an id were joined to a path unchecked.
const outsideId = "..%2F..%2Fjinks%2Frepo";
const outsideTemplate = "..%2F..%2F..%2Fjinks%2Frepo.xml";

const expectNotFoundPage = (r) => {
    expect(r.status).to.eq(404);
    expect(r.body).to.contain("Page not found");
};

// The ids' "pattern" in the route specs, enforced by the schema-constraints
// middleware (modules/schema-constraints.xqm).
describe("path parameters", () => {
    it("declare a pattern in every app route, except the not-found catch-alls", () => {
        cy.task("findFiles", { pattern: "modules/*-api.json" }).then((files) => {
            const missing = [];
            files.forEach((file) => {
                cy.readFile(file).then((spec) => {
                    Object.entries(spec.paths || {}).forEach(([path, item]) => {
                        Object.values(item)
                            .filter((op) => op.operationId && !/not-found$/.test(op.operationId))
                            .flatMap((op) => (op.parameters || []).filter((p) => p.in === "path"))
                            .filter((p) => !p.schema?.pattern)
                            .forEach((p) => missing.push(`${file} ${path} ${p.name}`));
                    });
                });
            });
            cy.then(() => expect(missing).to.deep.eq([]));
        });
    });
});

describe("ids that leave their collection", () => {
    [
        "countries",
        "countries/archives",
        "historicaldocuments/frus-history/documents",
        "historicaldocuments/frus-history/research",
        "historicaldocuments",
        "historicaldocuments/frus1977-80v27",
        "departmenthistory/people",
        "education/modules",
    ].forEach((section) => {
        it(`/${section}/{id} answers 404`, () => {
            get(`${section}/${outsideId}`).then(expectNotFoundPage);
        });
    });
});

describe("template is not a parameter of the view routes", () => {
    [
        "countries/mexico",
        "countries/archives/mexico",
        "historicaldocuments/frus1977-80v27",
        "historicaldocuments/frus1977-80v27/comp1",
    ].forEach((url) => {
        it(`/${url}?template= renders the route's own page`, () => {
            get(`${url}?template=${outsideTemplate}`).then((r) => {
                expect(r.status).to.eq(200);
                expect(r.headers["content-type"]).to.contain("text/html");
                expect(r.body).not.to.contain("exist-db.org/xquery/repo");
            });
        });
    });
});

describe("malformed numeric parameters", () => {
    ["search?q=cuba&start=abc", "open/frus-latest.xml?n=abc"].forEach((url) => {
        it(`/${url} answers 400 without diagnostics`, () => {
            get(url).then((r) => {
                expect(r.status).to.eq(400);
                expect(r.body).to.contain("Invalid request");
                expect(r.body).not.to.contain("FORG0001");
            });
        });
    });
});
