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
