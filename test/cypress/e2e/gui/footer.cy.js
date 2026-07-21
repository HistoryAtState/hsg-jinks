// All historicaldocuments page types share templates/layouts/hsg-content.html,
// which fills base10's shared "footer" block (present since base10 already
// carries the [% block footer %][% endblock %] container -- see the reference
// implementation in eeditiones/jinks commit dc65621e, "feat(serafin): add
// footer; fix styling") with the app's own templates/footer.html. Previously
// only templates/index.html included the footer directly.

const VOLUME = "historicaldocuments/frus1981-88v05";

[
    ["landing", VOLUME],
    ["comp", `${VOLUME}/comp`],
    ["chapter", `${VOLUME}/ch1`],
    ["document", `${VOLUME}/d1`],
].forEach(([kind, path]) => {
    it(`${kind} page has a footer`, () => {
        cy.visit(path);
        cy.get("footer.usa-footer").should("exist");
    });
});

// The footer carries the reference site's real content (#1086): four link
// columns, the Office of the Historian address block, and nothing from the
// USWDS example (no placeholder text, no dead javascript:void(0) links, no
// sign-up form, no social-media icons -- history.state.gov has neither).
describe("footer content", () => {
    beforeEach(() => cy.visit(`${VOLUME}/ch1`));

    it("has the four link columns of the reference site", () => {
        cy.get("footer.usa-footer .usa-footer__primary-link").then(($h) =>
            expect([...$h].map((el) => el.textContent.trim())).to.deep.equal([
                "Learn more",
                "Topics",
                "Contact",
                "Policies",
            ])
        );
    });

    it("links Historical Documents within this app, unbuilt sections to the reference site", () => {
        cy.get("footer.usa-footer a")
            .contains("Historical Documents")
            .should("have.attr", "href")
            .and("match", /\/historicaldocuments$/);
        cy.get("footer.usa-footer a")
            .contains("Privacy Policy")
            .should("have.attr", "href", "https://www.state.gov/privacy-policy/");
    });

    it("names the office and its contact address", () => {
        cy.get("footer.usa-footer .usa-footer__logo-heading").should(
            "contain.text",
            "Office of the Historian"
        );
        cy.get("footer.usa-footer .usa-footer__address a").should(
            "have.attr",
            "href",
            "mailto:history@state.gov"
        );
    });

    it("has no leftover USWDS example scaffold", () => {
        cy.get("footer.usa-footer").within(() => {
            cy.get('a[href="javascript:void(0);"]').should("not.exist");
            cy.get(".usa-sign-up").should("not.exist");
            cy.get(".usa-social-link").should("not.exist");
        });
        cy.get("footer.usa-footer")
            .invoke("text")
            .should("not.match", /<Secondary link|<Topic>|<Name of Agency>/);
    });
});
