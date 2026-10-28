// Keyword results as ft:passages' best sentences (srch:keyword-snippets,
// srch:flow-passages). ft:passages isn't in eXist's develop branch yet, and
// without it the cards fall back to the keyword-in-context snippets that
// search.cy.js covers, so this spec runs only against an eXist that has it:
// `cypress run --env ftPassages=true --spec test/cypress/e2e/gui/search/passages.cy.js`.
//
// baseUrl is http://localhost:8080/exist/apps/hsg-jinks (cypress.config.cjs).
// Override for a remapped host port, e.g.
// `cypress run --config baseUrl=http://localhost:8097/exist/apps/hsg-jinks`.

(Cypress.env("ftPassages") ? describe : describe.skip)("keyword results as passages", () => {
    it("shows a FRUS hit's matching sentences as one paragraph, the matches marked", () => {
        cy.visit("search?q=kennedy%20khrushchev&within=documents");
        cy.get(".usa-collection__item").first().within(() => {
            cy.contains("dt", "Keyword Results").next("dd").find(".hsg-flow__text").as("text");
            cy.get("@text").find(".hi").should("have.length.at.least", 2);
            cy.get("@text").invoke("text").should("match", /Khrushchev/i);
        });
        cy.get(".hsg-snippet").should("not.exist");
    });

    it("joins a hit's passages with an ellipsis", () => {
        cy.visit("search?q=kennedy%20khrushchev&within=documents");
        cy.get(".hsg-flow__text").first().invoke("text").should("include", " … ");
    });

    it("holds a long paragraph to three lines until Show more is opened", () => {
        cy.visit("search?q=kennedy%20khrushchev&within=documents");
        cy.get(".hsg-flow:has(.hsg-flow__more)").first().within(() => {
            cy.get(".hsg-flow__text").then(($text) => {
                const clamped = $text[0].getBoundingClientRect().height;
                cy.get(".hsg-flow__more summary").click();
                cy.get(".hsg-flow__more").should("have.attr", "open");
                cy.get(".hsg-flow__text").should(($open) => {
                    expect($open[0].getBoundingClientRect().height).to.be.greaterThan(clamped);
                });
            });
        });
    });

    it("gives the other publications' hits passages too", () => {
        cy.visit("search?q=cuba&within=department");
        cy.get(".usa-collection__item a[href*='/departmenthistory/short-history/']")
            .first()
            .closest(".usa-collection__item")
            .find(".hsg-flow__text .hi")
            .should("exist");
    });
});
