// Print view of a document page (OP#1464): under print media only the
// logo and the division's content are shown. Media emulation goes through the Chrome
// DevTools protocol, so this spec needs a Chromium-based browser (Electron,
// the default, is one).

const setMedia = (media) =>
    Cypress.automation("remote:debugger:protocol", {
        command: "Emulation.setEmulatedMedia",
        params: { media },
    });

const HIDDEN = {
    "USA banner": ".page-header .usa-banner",
    "main navigation": ".page-header .usa-nav",
    "menu button": ".page-header .usa-menu-btn",
    "left sidebar": "aside.before",
    "right sidebar": "aside.after",
    "page links": "main a.hsg-facs-link",
    "previous/next links": ".hsg-frus__pager",
    "historical documents navigation": ".hsg-historicaldocuments-nav",
    "page footer": "footer.usa-footer",
    "mobile footer": "footer.mobile-footer",
};

describe("print view of a document page", () => {
    beforeEach(() => {
        cy.visit("historicaldocuments/frus1981-88v05/d1");
        cy.then(() => setMedia("print"));
    });

    afterEach(() => cy.then(() => setMedia("")));

    for (const [label, selector] of Object.entries(HIDDEN)) {
        it(`hides the ${label}`, () => {
            cy.get(selector).should("exist").and("not.be.visible");
        });
    }

    it("shows the navy logo", () => {
        cy.get(".page-header .usa-logo__img")
            .should("be.visible")
            .and(($img) => {
                expect($img[0].getBoundingClientRect().width).to.equal(300);
                expect(getComputedStyle($img[0]).content).to.contain(
                    "oh-logo-navy.png",
                );
            });
    });

    it("shows the document's content, footnotes included", () => {
        cy.get("main .tei-body").should("be.visible");
        cy.get("main ol.footnotes").should("be.visible");
    });

    it("gives the content the full page width", () => {
        cy.get("main").then(($main) => {
            expect($main[0].getBoundingClientRect().left).to.be.lessThan(50);
        });
    });
});

describe("screen view of a document page", () => {
    it("keeps the chrome that print hides", () => {
        cy.visit("historicaldocuments/frus1981-88v05/d1");
        cy.get(".page-header").should("be.visible");
        cy.get(".hsg-frus__pager").should("be.visible");
    });
});
