// The Historical documents nav band below every Historical Documents page
// (OP#1400): heading size, card grid and inline extent (OP#1469).
//
// The heading is USWDS's 2xl heading size in Merriweather (39.04px) from
// tablet width up, xl (31.2px) below. The cards line up with the heading's
// inline edges, stack on phones and never reach past the band's content box.

const WIDTHS = [320, 390, 480, 768, 1024, 1440, 1920];

const columns = (w) => (w < 480 ? 1 : w < 1024 ? 2 : 4);

describe("historical documents nav band", () => {
    WIDTHS.forEach((w) => {
        it(`fits its content box at ${w}px`, () => {
            cy.viewport(w, 900);
            cy.visit("historicaldocuments/about-frus");
            cy.get(".hsg-historicaldocuments-nav h2", { timeout: 15000 }).then(($h) => {
                const heading = $h[0].getBoundingClientRect();
                expect($h.css("font-size"), "heading size").to.eq(w < 640 ? "31.2px" : "39.04px");

                cy.get(".hsg-historicaldocuments-nav-cards").should(($list) => {
                    const list = $list[0].getBoundingClientRect();
                    expect(list.left, "cards left").to.be.closeTo(heading.left, 1);
                    expect(list.right, "cards right").to.be.closeTo(heading.right, 1);

                    $list[0].querySelectorAll("*").forEach((el) => {
                        const r = el.getBoundingClientRect();
                        if (r.width === 0) return;
                        expect(r.left, `${el.className} left`).to.be.at.least(list.left - 1);
                        expect(r.right, `${el.className} right`).to.be.at.most(list.right + 1);
                    });

                    const lefts = new Set(
                        [...$list[0].children].map((card) => Math.round(card.getBoundingClientRect().left))
                    );
                    expect(lefts.size, "columns").to.eq(columns(w));
                });
            });
        });
    });
});
