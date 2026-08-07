// Visual-regression spec that arrived with the jinks/USWDS profile update.
// Skipped in this app, for two independent reasons (reassess if either
// changes):
// - it needs a compareSnapshot plugin (cypress-visual-regression or
//   similar) that this repo's Cypress setup does not install or register,
//   so both tests die with "compareSnapshot is not a function";
// - it snapshots the stock admin dropdown and pb-login dialog, and this
//   app disables the login UI altogether (config.json "login": false, see
//   gui/authentication.cy.js).
describe.skip("landing page", () => {
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
