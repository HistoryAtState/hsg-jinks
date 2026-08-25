// SEO head metadata (OP#629): document-derived meta description and
// link rel prev/next on FRUS pages, one description tag per page (the
// layout's generic tag yields to the derived one), all server-rendered
// from the teiHeader with no ODD cycle.

const VOLUME = "historicaldocuments/frus1981-88v05";

describe("head metadata (OP#629)", () => {
    it("a document page describes itself and links its reading order", () => {
        cy.request(`${VOLUME}/d57`).its("body").then((body) => {
            const descs = [...body.matchAll(/<meta name="description" content="([^"]*)"/g)];
            expect(descs, "one description tag").to.have.length(1);
            expect(descs[0][1]).to.contain("Document 57 of Foreign Relations of the United States");
            expect(body).to.match(/<link rel="prev" href="[^"]*frus1981-88v05\/d56"/);
            expect(body).to.match(/<link rel="next" href="[^"]*frus1981-88v05\/d58"/);
        });
    });

    it("a chapter page links compilation and first document", () => {
        cy.request(`${VOLUME}/ch1`).its("body").then((body) => {
            expect(body).to.match(/<link rel="prev" href="[^"]*frus1981-88v05\/comp"/);
            expect(body).to.match(/<link rel="next" href="[^"]*frus1981-88v05\/d1"/);
        });
    });

    it("pages without a derivable description keep the single generic one", () => {
        cy.request("about/faq").its("body").then((body) => {
            const descs = [...body.matchAll(/<meta name="description" content="([^"]*)"/g)];
            expect(descs).to.have.length(1);
            expect(descs[0][1]).to.eq("Office of the Historian");
            expect(body).to.not.match(/<link rel="(prev|next)"/);
        });
    });
});
