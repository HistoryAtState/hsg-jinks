describe("landing page", () => {
    beforeEach(() => {
        cy.visit("index.html");

        cy.wait(500);
    });

    it("The admin dropdown works", () => {
        cy.get(".menubar details").click();
        cy.get(".menubar details ul").compareSnapshot({
            name: "admin drop",
        });
    });

    it("The login works", () => {
        cy.get(".menubar pb-login").first().click();
        cy.get(".menubar pb-login")
            .shadow()
            .find("pb-dialog[open]")
            .shadow()
            .find("dialog")
            .compareSnapshot({ name: "login modal" });
    });
});
