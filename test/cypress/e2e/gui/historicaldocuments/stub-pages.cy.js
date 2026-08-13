// "To be implemented" stub landing pages for the five Historical Documents
// menu entries whose hsg-shell content has not been ported yet. Every link in
// the primary nav (mirroring hsg-shell templates/site.xml) must resolve; these
// stubs keep that guarantee until the real pages are ported. Labels are fixed
// UI chrome, so exact text is asserted (see CLAUDE.md's data-package caveat).

const PAGES = [
    ["historicaldocuments/about-frus", "About the Foreign Relations Series"],
    ["historicaldocuments/status-of-the-series", "Status of the Foreign Relations Series"],
    ["historicaldocuments/frus-history", "History of the Foreign Relations Series"],
    ["historicaldocuments/ebooks", "Ebooks Initiative"],
    ["historicaldocuments/quarterly-releases", "Quarterly Releases"],
];

describe("historicaldocuments stub landing pages", () => {
    PAGES.forEach(([path, title]) => {
        describe(path, () => {
            it("returns HTTP 200", () => {
                cy.request(path).its("status").should("eq", 200);
            });

            it(`renders the "${title}" stub`, () => {
                cy.visit(path);
                // pb-i18n carries the English label as fallback content, so the
                // heading text is right even before i18n resolves.
                cy.get("main h1", { timeout: 15000 }).should("contain.text", title);
                cy.get(".usa-alert.usa-alert--info")
                    .should("contain.text", "To be implemented")
                    .find("a")
                    .should("have.attr", "href", `https://history.state.gov/${path}`);
            });
        });
    });

    it("an unknown historicaldocuments subpage still 404s via the volume route", () => {
        cy.request({ url: "historicaldocuments/no-such-page", failOnStatusCode: false })
            .its("status")
            .should("eq", 404);
    });
});
