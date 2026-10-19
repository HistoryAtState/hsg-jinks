// Print view of a document page (OP#1464): under print media only the
// division's content is shown. Media emulation goes through the Chrome
// DevTools protocol, so this spec needs a Chromium-based browser (Electron,
// the default, is one).

const setMedia = (media) =>
    Cypress.automation("remote:debugger:protocol", {
        command: "Emulation.setEmulatedMedia",
        params: { media },
    });

const HIDDEN = {
    "page header": ".page-header",
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
