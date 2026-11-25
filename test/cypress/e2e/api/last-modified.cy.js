// Page routes send Last-Modified and answer a conditional request that is not
// older with 304 Not Modified (OP#1471, modules/last-modified.xqm).
describe("Last-Modified and 304 Not Modified", () => {
    const root = Cypress.config("baseUrl").replace(/\/$/, "");

    // one page per subsection
    const PAGES = [
        "/",
        "/historicaldocuments",
        "/historicaldocuments/about-frus",
        "/historicaldocuments/frus1981-88v05",
        "/historicaldocuments/frus1981-88v05/d57",
        "/historicaldocuments/frus-history",
        "/historicaldocuments/pre-1861/serial-set",
        "/about",
        "/about/faq",
        "/conferences",
        "/countries",
        "/countries/argentina",
        "/countries/archives/argentina",
        "/departmenthistory",
        "/departmenthistory/people/secretaries",
        "/departmenthistory/travels/president",
        "/departmenthistory/visits",
        "/developer",
        "/education",
        "/milestones",
        "/open",
        "/search?q=soviet",
        "/search/tips",
        "/tags",
    ];

    const get = (url, headers = {}) =>
        cy.request({ url: `${root}${url}`, headers, followRedirect: false, failOnStatusCode: false });

    PAGES.forEach((url) => {
        it(`${url} answers 304 when not modified since its Last-Modified`, () => {
            get(url).then((first) => {
                expect(first.status).to.eq(200);
                const lastModified = first.headers["last-modified"];
                expect(lastModified, "Last-Modified").to.match(/^\w{3}, \d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2} GMT$/);

                get(url, { "If-Modified-Since": lastModified }).then((conditional) => {
                    expect(conditional.status).to.eq(304);
                    expect(conditional.body).to.be.empty;
                    expect(conditional.headers["last-modified"]).to.eq(lastModified);
                });

                const older = new Date(Date.parse(lastModified) - 86400000).toUTCString();
                get(url, { "If-Modified-Since": older }).then((stale) => {
                    expect(stale.status).to.eq(200);
                    expect(stale.headers["last-modified"]).to.eq(lastModified);
                });
            });
        });
    });

    it("ignores an unparseable If-Modified-Since", () => {
        get("/about", { "If-Modified-Since": "yesterday" }).then((response) => {
            expect(response.status).to.eq(200);
        });
    });

    it("sends no Last-Modified with a 404 page", () => {
        get("/asdfg", { "If-Modified-Since": new Date().toUTCString() }).then((response) => {
            expect(response.status).to.eq(404);
            expect(response.headers).not.to.have.property("last-modified");
        });
    });

    it("leaves the services routes alone", () => {
        get("/services/volume-ids").then((response) => {
            expect(response.status).to.eq(200);
            expect(response.headers).not.to.have.property("last-modified");
        });
    });
});
