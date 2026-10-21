// The FRUS History Appendix A chart draws with its title and axis labels,
// and its dataset toggles change what the legend reports. Ported from
// hsg-shell's WebdriverIO historical-documents/frus_history_appendix_a_chart.js,
// which no Cypress spec there covered (OP#1466). frus-history.cy.js covers
// the graph target and the three toggles' presence.

describe("the Appendix A chart", () => {
    beforeEach(() => {
        cy.visit("historicaldocuments/frus-history/appendix-a");
        cy.get("#graph canvas").should("exist");
    });

    it("has the title and both axis labels", () => {
        cy.get("#graph .dygraph-title").should("have.text", "Foreign Relations Series: Production & Timeliness, 1861-2015");
        cy.get("#graph .dygraph-ylabel").should("have.text", "Production (Volumes)");
        cy.get("#graph .dygraph-y2label").should("have.text", "Lag (Years)");
    });

    it("reports the ticked datasets in the legend", () => {
        cy.get("#graph").click();
        cy.get("#graph .dygraph-legend")
            .should("contain.text", "Production")
            .and("contain.text", "Average Lag")
            .and("not.contain.text", "Regular Lag");

        // the inputs sit under their labels; click the labels, as a reader does
        cy.get("#graph-fieldset label[for='2']").click();
        cy.get("#graph-fieldset label[for='0']").click();
        cy.get("#graph-fieldset label[for='1']").click();
        cy.get("#graph").click();
        cy.get("#graph .dygraph-legend")
            .should("contain.text", "Regular Lag")
            .and("not.contain.text", "Production")
            .and("not.contain.text", "Average Lag");
    });
});
