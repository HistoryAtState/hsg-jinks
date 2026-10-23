// Footnote markers show their footnote in a popover on hover and jump to it
// on click. Ported from hsg-shell's WebdriverIO
// footnote/prod_footnote_popover.spec.js, which no Cypress spec there
// covered (OP#1466). The popover is a pb-popover rendered by tippy, the
// same on touch devices, so hsg-shell's separate touch modal has no
// counterpart here.

const PAGE = "historicaldocuments/frus-history/introduction";
const popover = () => cy.get(".tippy-box[data-state='visible']");

describe("footnote popover", () => {
    beforeEach(() => cy.visit(PAGE));

    it("numbers the marker and links it to the footnote", () => {
        cy.get("#fnref_introductionfn1")
            .should("have.text", "1")
            .and("have.attr", "href", "#fn_introductionfn1");
        cy.get("#fn_introductionfn1 .fn-number").should("have.text", "1");
    });

    it("appears on hover with the footnote text", () => {
        cy.get(".tippy-box").should("not.exist");
        cy.get("#fnref_introductionfn1").scrollIntoView().trigger("mouseenter");
        popover().should("contain.text", "Congressional Record—Senate");
    });

    it("has no back link", () => {
        cy.get("#fnref_introductionfn1").scrollIntoView().trigger("mouseenter");
        popover().should("be.visible").find(".fn-back").should("not.exist");
    });

    it("disappears when the cursor leaves the marker", () => {
        cy.get("#fnref_introductionfn1").scrollIntoView().trigger("mouseenter");
        popover().should("be.visible");
        cy.get("#fnref_introductionfn1").trigger("mouseleave");
        popover().should("not.exist");
    });

    it("shows the other footnote for the other marker", () => {
        cy.get("#fnref_introductionfn2").scrollIntoView().trigger("mouseenter");
        popover().should("contain.text", "Skowronek").and("not.contain.text", "Congressional Record");
    });

    it("scrolls to the footnote when the marker is clicked", () => {
        cy.get("#fnref_introductionfn1").click();
        cy.location("hash").should("eq", "#fn_introductionfn1");
        cy.get("#fn_introductionfn1").should(($fn) => {
            const { top, bottom } = $fn[0].getBoundingClientRect();
            expect(top, "top").to.be.at.least(-1);
            expect(bottom, "bottom").to.be.at.most(Cypress.config("viewportHeight"));
        });
    });
});
