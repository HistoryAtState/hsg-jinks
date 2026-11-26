// A volume that is not published yet shows its production stage instead of
// cover, editors and publisher, as hsg-shell does. frus1981-88v37 has
// revisionDesc status "being-researched".

describe("landing page of an unpublished volume", { testIsolation: false }, () => {
    before(() => cy.visit("historicaldocuments/frus1981-88v37"));

    it("shows the volume title", () => {
        cy.get(".hsg-frus__landing h1").should("contain.text", "Volume XXXVII");
    });

    it("notes the volume's current status, linking the Status of the Series", () => {
        cy.get(".hsg-frus__status-note")
            .should("contain.text", "the current status of this volume is “Being Researched.”")
            .find("a")
            .should("have.attr", "href")
            .and("match", /\/historicaldocuments\/status-of-the-series$/);
    });

    it("shows no editors, publisher, cover or Open button", () => {
        cy.get(".hsg-frus__landing .hsg-frus__meta").should("not.exist");
        cy.get(".hsg-frus__landing .hsg-frus__cover").should("not.exist");
        cy.get(".hsg-frus__landing .hsg-frus__open").should("not.exist");
    });
});

describe("landing page of a published volume", () => {
    it("shows editors and publisher, and no status note", () => {
        cy.visit("historicaldocuments/frus1981-88v05");
        cy.get(".hsg-frus__meta").should("contain.text", "Editor:").and("contain.text", "Publisher:");
        cy.get(".hsg-frus__status-note").should("not.exist");
    });
});
