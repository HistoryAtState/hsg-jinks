// Date-filtered FRUS searches find the expected documents and finish within
// 5 seconds. Ported from hsg-shell's search/new-indexes.cy.js (OP#1466),
// whose bar was one second; on the full FRUS data these searches take just
// over a second, so 5 seconds leaves room for a loaded server while still
// catching a search that falls back to scanning the documents.
//
// hsg-shell pinned counts from the full corpus. Search specs run against
// the frus-data-jinks baseline instead (OP#1318), where only China and
// Tokyo have hits in 1940-1960 (frus1958-60v05mSupp); its Indochina and
// Sudan cases are left out. Counts are lower bounds.

const range = { within: "documents", "start-date": "1940", "end-date": "1960" };

[
    ["China", 10],
    ["Tokyo", 1],
].forEach(([q, atLeast]) => {
    describe(`search for ${q}, 1940-1960`, () => {
        it(`finds at least ${atLeast} documents`, () => {
            cy.visit("search", { qs: { q, ...range, "sort-by": "date-asc" } });
            cy.get(".search-count")
                .invoke("text")
                .then((count) => {
                    expect(Number(count.replace(/,/g, ""))).to.be.at.least(atLeast);
                });
        });

        it("completes within 5 seconds", () => {
            cy.visit("search", { qs: { q, ...range } });
            cy.get(".hsg-results-summary")
                .invoke("text")
                .then((summary) => {
                    const [, seconds] = summary.match(/Search completed in (\d+\.\d+)s\./);
                    expect(parseFloat(seconds)).to.be.below(5);
                });
        });
    });
});
