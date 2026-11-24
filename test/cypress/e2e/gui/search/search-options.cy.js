// The search options under the search field: "Match word forms" (stem),
// "Match case" (case) and "Match punctuation" (punct), next to hybrid mode
// in one "Search options" disclosure. Each searches a sibling of the
// hsg-fulltext field that the data packages define with its own analyzer
// chain (hsg-fulltext-stemmed, -cased, -punct, -literal).
//
// The form tests run everywhere. What the options find needs those fields,
// which need data packages with the option fields on an eXist with analyzer
// chains (eXist-db/exist#6916); without them the options find nothing new.
// So those tests run only when asked for:
// `cypress run --env searchOptions=true --spec test/cypress/e2e/gui/search/search-options.cy.js`.
// They search Historical Documents and compare counts with and without an
// option rather than pinning them, since the FRUS data grows (see CLAUDE.md).
//
// baseUrl is http://localhost:8080/exist/apps/hsg-jinks (cypress.config.cjs).
// Override for a remapped host port, e.g.
// `cypress run --config baseUrl=http://localhost:8097/exist/apps/hsg-jinks`.

const resultCount = (query) => {
    cy.visit(`search?within=documents&${query}`);
    return cy.get(".search-count").invoke("text").then((text) => Number(text.replace(/,/g, "")));
};

describe("the search options form", () => {
    it("is a closed disclosure holding hybrid mode and the three match options", () => {
        cy.visit("search");
        cy.get("details.hsg-search-options").should("not.have.attr", "open");
        cy.get(".hsg-search-options summary").should("have.text", "Search options");
        cy.get(".hsg-search-options input[type='checkbox']")
            .then(($boxes) => [...$boxes].map((box) => box.name))
            .should("deep.equal", ["mode", "stem", "case", "punct"]);
        cy.get(".hsg-search-options input[type='checkbox']:checked").should("not.exist");
    });

    it("opens by itself when an option is on, with the option ticked", () => {
        cy.visit("search?q=salt&within=documents&case=yes");
        cy.get("details.hsg-search-options").should("have.attr", "open");
        cy.get("#match-case").should("be.checked");
        cy.get("#match-stem, #match-punct").should("not.be.checked");
    });

    it("submits a ticked option as name=yes", () => {
        cy.visit("search?q=salt&within=documents");
        cy.get(".hsg-search-options summary").click();
        cy.get("label[for='match-case']").click();
        cy.get("#hsg-search button[type='submit']").click();
        cy.location("search").should("include", "case=yes");
        cy.get("#match-case").should("be.checked");
    });

    it("disables match word forms, so it isn't submitted, while case or punctuation is ticked", () => {
        cy.visit("search?q=negotiation&within=documents&stem=yes");
        cy.get("#match-stem").should("be.checked").and("not.be.disabled");
        cy.get("label[for='match-case']").click();
        cy.get("#match-stem").should("be.disabled").and("be.checked");
        cy.get("#hsg-search button[type='submit']").click();
        cy.location("search").should("include", "case=yes").and("not.include", "stem=");
        cy.get("label[for='match-case']").click();
        cy.get("#match-stem").should("not.be.disabled");
    });

    it("keeps the options that are on when paging", () => {
        cy.visit("search?q=negotiation&within=documents&stem=yes");
        cy.get("a.usa-pagination__next-page").first().click();
        cy.location("search").should("include", "start=11").and("include", "stem=yes");
        cy.get("#match-stem").should("be.checked");
    });
});

(Cypress.env("searchOptions") ? describe : describe.skip)("what the match options find", () => {
    it("match case finds a word only in the case it was typed in", () => {
        // SALT, the arms talks, is far more common in FRUS than salt.
        resultCount("q=salt").then((anyCase) => {
            resultCount("q=salt&case=yes").then((lower) => {
                resultCount("q=SALT&case=yes").then((upper) => {
                    expect(lower).to.be.lessThan(anyCase);
                    expect(upper).to.be.at.most(anyCase);
                    expect(upper).to.be.greaterThan(lower);
                });
            });
        });
        cy.contains(".hsg-results-summary", "matching case");
    });

    it("match punctuation keeps punctuation inside a word, so its parts no longer match", () => {
        // Without the option, S/S (the Executive Secretariat) also matches
        // "SS"; with it, only SS as written does.
        resultCount("q=SS").then((ignoring) => {
            resultCount("q=SS&punct=yes").then((matching) => {
                expect(matching).to.be.lessThan(ignoring);
            });
        });
        cy.contains(".hsg-results-summary", "matching punctuation");
    });

    it("match punctuation still finds a word written with punctuation inside", () => {
        resultCount("q=S%2FS&punct=yes").should("be.greaterThan", 0);
    });

    it("match case and match punctuation combine", () => {
        resultCount("q=SALT&case=yes&punct=yes").should("be.greaterThan", 0);
        cy.contains(".hsg-results-summary", "matching case and matching punctuation");
    });

    it("match word forms finds the other forms of a word", () => {
        resultCount("q=negotiation").then((exact) => {
            resultCount("q=negotiation&stem=yes").then((forms) => {
                expect(forms).to.be.greaterThan(exact);
            });
        });
        cy.contains(".hsg-results-summary", "and its word forms");
    });

    it("match word forms keeps wildcard searches working", () => {
        resultCount("q=negotiat*").then((exact) => {
            resultCount("q=negotiat*&stem=yes").should("be.at.least", exact);
        });
    });

    it("match word forms gives way to match case or punctuation on the server too", () => {
        resultCount("q=negotiation").then((exact) => {
            resultCount("q=negotiation&stem=yes&case=yes").should("be.at.most", exact);
        });
        cy.get(".hsg-results-summary").should("not.contain", "word forms");
    });
});
