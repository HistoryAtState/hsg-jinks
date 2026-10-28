// The timelines above a Historical Documents search (srch:timeline): TEI
// Publisher's pb-timeline, loaded through its subscribe channel (see
// resources/scripts/search-timeline.js), and picking a bar searches again
// within its dates.
//
// baseUrl is http://localhost:8080/exist/apps/hsg-jinks (cypress.config.cjs).
// Override for a remapped host port, e.g.
// `cypress run --config baseUrl=http://localhost:8097/exist/apps/hsg-jinks`.

describe("search timelines", () => {
    it("draws the results by date above a Historical Documents search", () => {
        cy.visit("search?q=cuba&within=documents");
        cy.get(".hsg-timeline pb-timeline").should("have.length", 1);
        cy.get(".hsg-timeline pb-timeline")
            .shadow()
            .find(".bin-container[data-value]")
            .should("have.length.at.least", 2);
    });

    it("adds the semantic matches by date in hybrid mode", () => {
        cy.visit("search?q=cuba&within=documents&mode=hybrid");
        cy.get(".hsg-timeline pb-timeline").should("have.length", 2);
        cy.get(".hsg-timeline pb-timeline")
            .last()
            .shadow()
            .find(".bin-container[data-value]")
            .should("have.length.at.least", 2);
    });

    it("shows no timeline when the search covers the entire site", () => {
        cy.visit("search?q=cuba");
        cy.get(".usa-collection").should("exist");
        cy.get(".hsg-timelines").should("not.exist");
    });

    it("searches within a bar's dates when it is picked", () => {
        cy.visit("search?q=cuba&within=documents");
        cy.get(".hsg-timeline pb-timeline")
            .shadow()
            .find(".bin-container")
            .filter((i, bin) => Number(bin.dataset.value) > 0)
            .first()
            .trigger("mousedown", "center");
        cy.document().trigger("mouseup");
        cy.location("search").should("match", /start-date=\d{4}/);
        cy.location("search").should("include", "q=cuba");
        cy.get(".usa-collection__item").should("have.length.at.least", 1);
    });
});
