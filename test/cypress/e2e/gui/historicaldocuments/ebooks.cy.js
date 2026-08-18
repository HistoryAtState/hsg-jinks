// The "Foreign Relations Ebooks" page (OP#1293), reference parity with
// hsg-shell: https://history.state.gov/historicaldocuments/ebooks
//
// The FAQ is static content (exact assertions, including the deep-link
// anchor ids that exist in the wild); the catalog is data-derived from the
// FRUS volumes carrying epub relatedItems, so its counts use lower bounds
// per CLAUDE.md "Cypress assertions on data-package counts" (the dev
// container has 6 volumes with ebooks plus the frus-history monograph).

describe("the ebooks page", () => {
    beforeEach(() => cy.visit("historicaldocuments/ebooks"));

    it("returns HTTP 200", () => {
        cy.request("historicaldocuments/ebooks").its("status").should("eq", 200);
    });

    it("shows the page heading", () => {
        cy.get("main h1", { timeout: 15000 }).should("have.text", "Ebooks");
    });

    it("keeps every FAQ deep-link anchor from the reference page", () => {
        cy.get("main #faq", { timeout: 15000 }).should("exist");
        cy.get("main #tested-devices-and-apps").should("exist");
        cy.get("main #adding-ebooks-to-devices").should("exist");
        cy.get("main #side-loading").should("exist");
        cy.get("main #embedding-the-catalog").should("exist");
        cy.get("main #citing-frus-ebooks").should("exist");
        cy.get("main #known-issues").should("exist");
        cy.get("main #helpful-tips").should("exist");
        cy.get("main #feedback").should("exist");
    });

    it("renders the ebook catalog with an entry per volume", () => {
        cy.get("main #catalog", { timeout: 15000 })
            .find("> div")
            .should("have.length.at.least", 3);
        cy.get("main #catalog > p").should("contain.text", "volumes are currently available");
    });

    it("includes the frus-history monograph entry (package installed in dev)", () => {
        cy.get("main #catalog > div#frus-history", { timeout: 15000 }).should("exist");
    });

    it("links EPUB downloads to the static S3 bucket", () => {
        cy.get("main #catalog a:contains('EPUB')", { timeout: 15000 })
            .first()
            .should("have.attr", "href")
            .and("match", /static\.history\.state\.gov/);
    });

    it("documents the OPDS catalog URL in the embedding section", () => {
        cy.get("main a[href='https://history.state.gov/api/v1/catalog']", { timeout: 15000 })
            .should("exist");
    });

    it("has the section navigation in the left sidebar", () => {
        cy.get("aside.before ul.usa-sidenav", { timeout: 15000 }).should("exist");
    });
});
