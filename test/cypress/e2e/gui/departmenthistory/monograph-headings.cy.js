// Monograph-section headings render once, with dates as encoded (OP#1336).
// Previously the ODD transform emitted the division's own head a second
// time, and each tei:date in it carried its normalized @when value as
// visible popover text next to the display text.

[
    ["departmenthistory/short-history/foundations", "Foundations of Foreign Affairs, 1775-1823"],
    ["departmenthistory/buildings/section2", "Carpenters’ Hall, Philadelphia Sept. 5, 1774—Oct. 26, 1774"],
    [
        "departmenthistory/buildings/section3",
        "Pennsylvania State House (Independence Hall), Philadelphia Intermittingly from May 10, 1775 to March 1, 1781",
    ],
].forEach(([path, heading]) => {
    describe(`/${path}`, () => {
        beforeEach(() => cy.visit(path));

        it("renders exactly one h1, without normalized @when text", () => {
            cy.get("h1").should("have.length", 1);
            cy.get("h1")
                .invoke("text")
                .then((t) => {
                    expect(t.replace(/\s+/g, " ").trim()).to.eq(heading);
                });
        });

        it("renders no date popover alternates in the content", () => {
            cy.get("main pb-popover.alternate.tei-date").should("not.exist");
        });
    });
});
