// Covers #1129 "Read a country's diplomatic history and find its archives
// information" -- click-through across the section's two independent TEI
// collections (rdcr/countries, wwdai/archives), which is this section's
// distinguishing shape (#1095).

describe("the countries section", () => {
    it("browses from the landing page to a country article and back", () => {
        cy.visit("countries");
        cy.get("main h1").should("contain.text", "Countries");
        cy.contains("a", "all countries").click();
        cy.location("pathname").should("match", /countries\/all$/);

        cy.contains("a", "Japan").click();
        cy.location("pathname").should("match", /countries\/japan$/);
        cy.get("main h1").should("contain.text", "Japan");
        cy.get("nav[aria-label='breadcrumb']").first().within(() => {
            cy.contains("a", "Countries");
            cy.contains("li", "Japan");
        });
    });

    it("follows Related Resources into the matching archives article and back", () => {
        cy.visit("countries/japan");
        cy.get("aside.after").contains("a", "World Wide Diplomatic Archives Index").click();
        cy.location("pathname").should("match", /countries\/archives$/);

        cy.contains("a", "all countries").click();
        cy.location("pathname").should("match", /countries\/archives\/all$/);

        cy.contains("a", "Japan").click();
        cy.location("pathname").should("match", /countries\/archives\/japan$/);
        cy.get("main h1").should("contain.text", "World Wide Diplomatic Archives Index: Japan");
        cy.get("nav[aria-label='breadcrumb']").first().within(() => {
            cy.contains("a", "Countries");
            cy.contains("a", "Archives");
            cy.contains("li", "World Wide Diplomatic Archives Index: Japan");
        });

        cy.get("aside.after").contains("a", "Countries").click();
        cy.location("pathname").should("match", /countries$/);
    });
});

describe("unknown or mistyped country URLs (#1130)", () => {
    it("gets a real 404 for an unknown country id", () => {
        cy.request({ url: "countries/nonexistent-country-xyz", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
    });

    it("gets a real 404 for an unknown archive id", () => {
        cy.request({ url: "countries/archives/nonexistent-country-xyz", failOnStatusCode: false }).then((response) => {
            expect(response.status).to.eq(404);
        });
    });

    it("resolves the reserved literal segments, never the {id} handler", () => {
        cy.request("countries/all").its("status").should("eq", 200);
        cy.request("countries/archives").its("status").should("eq", 200);
        cy.request("countries/archives/all").its("status").should("eq", 200);
    });
});
