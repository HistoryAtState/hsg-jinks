// Document view (#1081): overline, number + title heading with its source-note
// marker, dateline, ruler, and the footnote apparatus.
//
// Documents carry no <head> in the body (only a <?frusGen document-heading...?>
// placeholder PI), so the number + title, the overline and the dateline are all
// synthesized from the teiHeader via the "document-view" ODD mode
// (resources/odd/hsg-jinks.odd), selected in
// templates/pages/volume-interior.html for frus-division-type='document'.
//
// Footnotes live in standOff/listAnnotation and point *at* the in-body anchors
// (note/@corresp = '#' || anchor/@xml:id), the reverse of what the base ODD
// expects, so hsg-jinks.odd overrides the anchor and note models.
//
// baseUrl is http://localhost:8080/exist/apps/hsg-jinks (cypress.config.cjs),
// i.e. the port as seen from inside the container. If the host port is remapped,
// run with:
// `cypress run --config baseUrl=http://localhost:<host-port>/exist/apps/hsg-jinks`.

const VOLUME = "historicaldocuments/frus1981-88v05";

const OVERLINE =
    "Foreign Relations of the United States, 1981–1988, Volume V, Soviet Union, March 1985–October 1986";

// Text of an element with the footnote marker stripped, whitespace collapsed.
const textWithoutMarker = ($el) => {
    const clone = $el.clone();
    clone.find("sup.footnote-ref").remove();
    return clone.text().replace(/\s+/g, " ").trim();
};

const DOCS = [
    {
        id: "d1",
        heading:
            "1. Letter From President Reagan to Soviet General Secretary Gorbachev",
        dateline: "Washington, March 11, 1985",
        // note @n, in document order; ids are TEI-derived (decision: #d1fn2,
        // not the legacy #fn:1.7.4.4.8.8.8.5 scheme, which was a node path into
        // the old monolithic volume file and is not derivable from split TEI).
        footnotes: ["d1fn1", "d1fn2"],
    },
    {
        id: "d3",
        heading:
            "3. Memorandum From John Lenczowski of the National Security Council Staff to the President’s Assistant for National Security Affairs (McFarlane)",
        dateline: "Washington, March 12, 1985",
        footnotes: ["d3fn1", "d3fn2", "d3fn3", "d3fn4", "d3fn5"],
    },
];

describe("document view", () => {
    DOCS.forEach(({ id, heading, dateline, footnotes }) => {
        describe(id, () => {
            beforeEach(() => cy.visit(`${VOLUME}/${id}`));

            it("renders the document's number and title as the page's h1", () => {
                cy.get("main h1")
                    .should("be.visible")
                    .then(($h1) => expect(textWithoutMarker($h1)).to.eq(heading));
            });

            it("renders exactly one h1", () => {
                cy.get("main h1").should("have.length", 1);
            });

            it("renders the volume title as an overline", () => {
                cy.get("main .overline")
                    .should("be.visible")
                    .invoke("text")
                    .then((t) => t.replace(/\s+/g, " ").trim())
                    .should("eq", OVERLINE);
            });

            it("renders the place and date as a dateline", () => {
                cy.get("main .dateline")
                    .should("be.visible")
                    .invoke("text")
                    .then((t) => t.replace(/\s+/g, " ").trim())
                    .should("eq", dateline);
            });

            it("marks the heading with a reference to the source note", () => {
                // The source note has no in-body anchor -- it belongs to the
                // heading -- so its marker is rendered by the TEI model, not by
                // the anchor model.
                cy.get("main h1 sup.footnote-ref a")
                    .should("have.attr", "href", `#${footnotes[0]}`)
                    .and("have.attr", "id", `${footnotes[0]}ref`);
            });

            it("renders a ruler and one numbered footnote list", () => {
                cy.get("main hr").should("have.length", 1);
                cy.get("main ol.footnotes").should("have.length", 1);
                cy.get("main ol.footnotes > li").should(
                    "have.length",
                    footnotes.length,
                );
            });

            it("gives every footnote the id its marker points at", () => {
                footnotes.forEach((noteId, i) => {
                    cy.get("main ol.footnotes > li")
                        .eq(i)
                        .should("have.attr", "id", noteId)
                        .and("have.attr", "value", String(i + 1));
                });
            });

            it("links every in-body marker to a footnote that links back", () => {
                cy.get("main .tei-body sup.footnote-ref a").each(($a) => {
                    const href = $a.attr("href");
                    const refId = $a.attr("id");
                    expect(href).to.eq(`#${refId.replace(/ref$/, "")}`);
                    // the note exists and its backlink targets this marker
                    cy.get(`main ol.footnotes > li${href}`)
                        .find("a.footnote-backlink")
                        .should("have.attr", "href", `#${refId}`);
                });
            });
        });
    });

    describe("d96 (document with attachments)", () => {
        // The reference site renders attachments inline inside their parent and
        // 404s /d96-a1; the notes of all three parts share ONE consolidated list,
        // which is why the attachments' @n continue the parent's numbering.
        beforeEach(() => cy.visit(`${VOLUME}/d96`));

        it("inlines both attachments under their encoded labels", () => {
            cy.get("main .attachment").should("have.length", 2);
            cy.get("main .attachment-label").then(($labels) => {
                const labels = [...$labels].map((el) =>
                    el.textContent.replace(/\s+/g, " ").trim(),
                );
                expect(labels).to.deep.eq(["Tab I", "Tab II"]);
            });
        });

        it("gives each attachment its own title and dateline", () => {
            cy.get("main .attachment").each(($att) => {
                cy.wrap($att)
                    .find(".attachment-title")
                    .invoke("text")
                    .then((t) => t.replace(/\s+/g, " ").trim())
                    .should("contain", "Paper Prepared by an Interagency Working Group");
                cy.wrap($att)
                    .find(".dateline")
                    .invoke("text")
                    .then((t) => t.replace(/\s+/g, " ").trim())
                    .should("eq", "Washington, undated");
            });
        });

        it("consolidates parent and attachment footnotes into one list", () => {
            cy.get("main ol.footnotes").should("have.length", 1);
            cy.get("main ol.footnotes > li")
                .should("have.length", 11)
                .then(($lis) => {
                    const ids = [...$lis].map((li) => li.id);
                    expect(ids).to.deep.eq([
                        "d96fn1",
                        "d96fn2",
                        "d96fn3",
                        "d96fn4",
                        "d96fn5",
                        "d96-a1fn6",
                        "d96-a1fn7",
                        "d96-a1fn8",
                        "d96-a2fn9",
                        "d96-a2fn10",
                        "d96-a2fn11",
                    ]);
                    // numbering runs 1..11 across the parent and both attachments
                    const values = [...$lis].map((li) => li.getAttribute("value"));
                    expect(values).to.deep.eq(
                        Array.from({ length: 11 }, (_, i) => String(i + 1)),
                    );
                });
        });
    });

    describe("attachment URLs", () => {
        // Attachments are rendered inline in their parent and have no page of
        // their own, as on the reference site, which 404s these URLs. The data
        // disagrees -- each attachment carries a relatedItem type="canonical"
        // advertising this very URL -- but the reference site is authoritative.
        ["d96-a1", "d96-a2", "d125-a1"].forEach((id) => {
            it(`${id}: is not a page of its own`, () => {
                cy.request({
                    url: `${VOLUME}/${id}`,
                    failOnStatusCode: false,
                }).then((res) => {
                    expect(res.status).to.eq(404);
                    // still the styled error page, not a bare error
                    expect(res.headers["content-type"]).to.contain("text/html");
                });
            });
        });

        it("the parent document is unaffected", () => {
            cy.request(`${VOLUME}/d96`).its("status").should("eq", 200);
        });
    });

    describe("unknown division ids", () => {
        // id() tokenizes its argument on whitespace, so an id with a space in it
        // resolved to several elements (crashing root($doc) with a raw XPTY0004)
        // or to the division itself under a second URL.
        const MISSES = [
            ["comp1", "no such division"],
            ["d9999", "no such document"],
            ["D1", "ids are case-sensitive"],
            ["d1%20d3", "two ids in one segment must not resolve, nor crash"],
            ["d1%20", "a trailing space must not serve d1 under a second URL"],
            ["%20d1", "nor a leading one"],
        ];

        MISSES.forEach(([id, why]) => {
            it(`${id}: 404 (${why})`, () => {
                cy.request({
                    url: `${VOLUME}/${id}`,
                    failOnStatusCode: false,
                }).then((res) => {
                    expect(res.status).to.eq(404);
                    // a miss, not an internal error leaking through as a page
                    expect(res.body).not.to.contain("java:org.exist");
                });
            });
        });

        it("an unknown volume is a 404 too", () => {
            cy.request({
                url: "historicaldocuments/nosuchvolume/d1",
                failOnStatusCode: false,
            })
                .its("status")
                .should("eq", 404);
        });
    });

    describe("documents without footnotes", () => {
        // 8 of 341 documents have no standOff notes at all (7 editorial notes and
        // 1 historical document). They must not emit an empty list or a stray rule.
        ["d34", "d304"].forEach((id) => {
            it(`${id}: renders neither a ruler nor a footnote list`, () => {
                cy.visit(`${VOLUME}/${id}`);
                cy.get("main h1").should("be.visible");
                cy.get("main hr").should("not.exist");
                cy.get("main ol.footnotes").should("not.exist");
                cy.get("main h1 sup.footnote-ref").should("not.exist");
            });
        });

        it("d304: renders no dateline, since its setting is empty", () => {
            cy.visit(`${VOLUME}/d304`);
            cy.get("main .dateline").should("not.exist");
        });
    });

    it("d299: renders a date-only dateline without a leading comma", () => {
        // 4 documents have a date but no placeName.
        cy.visit(`${VOLUME}/d299`);
        cy.get("main .dateline")
            .invoke("text")
            .then((t) => t.replace(/\s+/g, " ").trim())
            .should("eq", "October 9, 1986");
    });
});
