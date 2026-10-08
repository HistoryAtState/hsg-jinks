// One breadcrumb structure on every page (OP#1437): hsg:breadcrumbs in
// modules/templates/hsg.xqm renders all trails, so each sampled page, one
// per section and per trail builder, must show the same shape: Home first,
// a link on every crumb but the last, aria-current="page" on the last one
// only, and schema.org RDFa throughout.

const PAGES = [
    // historicaldocuments: section root, static page, layout default
    // (volume, chapter, document, front matter), facsimile, frus-history,
    // serial set, quarterly release
    { path: "historicaldocuments", current: "Historical Documents" },
    { path: "historicaldocuments/about-frus" },
    { path: "historicaldocuments/frus1981-88v05" },
    { path: "historicaldocuments/frus1981-88v05/ch1" },
    { path: "historicaldocuments/frus1981-88v05/d57", current: "Document 57" },
    { path: "historicaldocuments/frus1981-88v05/preface", current: "Preface" },
    { path: "historicaldocuments/frus1981-88v05/pg_1", current: "Page 1" },
    { path: "historicaldocuments/frus-history/chapter-4" },
    { path: "historicaldocuments/frus-history/events", current: "Events" },
    { path: "historicaldocuments/pre-1861/serial-set/browse", current: "Browse" },
    { path: "historicaldocuments/pre-1861/serial-set/browse?region=Africa", current: "Africa" },
    { path: "historicaldocuments/quarterly-releases/2017-q1", current: "2017 Quarter 1" },
    { path: "about", current: "About Us" },
    { path: "about/faq/what-is-frus" },
    { path: "conferences/2010-southeast-asia/photos" },
    { path: "countries", current: "Countries" },
    { path: "countries/archives/all", current: "All Archives" },
    { path: "countries/argentina" },
    { path: "departmenthistory/people/madison-james", current: "James Madison" },
    { path: "departmenthistory/short-history/foundations" },
    { path: "departmenthistory/travels/president/belgium", current: "Belgium" },
    { path: "developer/catalog", current: "Ebook Catalog API" },
    { path: "education/modules/documents-intro" },
    { path: "milestones/1914-1920/haiti" },
    { path: "open/frus-latest" },
    { path: "search", current: "Search" },
    { path: "search/tips", current: "Tips" },
    { path: "tags/all", current: "Full Taxonomy" },
];

describe("breadcrumb structure", () => {
    PAGES.forEach(({ path, current }) => {
        it(`/${path}`, () => {
            cy.visit(path);
            // The layout renders the breadcrumb slot twice (desktop and
            // mobile toolbar); both come from the same call, check the first.
            cy.get('nav[aria-label="breadcrumb"] > ul', { timeout: 15000 })
                .first()
                .should("have.attr", "typeof", "BreadcrumbList")
                .and("have.attr", "vocab", "http://schema.org/")
                .find("> li")
                .should("have.length.at.least", 2)
                .each(($li, i, $lis) => {
                    const last = i === $lis.length - 1;
                    expect($li.attr("typeof"), "li typeof").to.eq("ListItem");
                    expect($li.attr("property"), "li property").to.eq("itemListElement");
                    if (last) {
                        expect($li.attr("aria-current"), "last crumb is current").to.eq("page");
                        expect($li.find("a"), "last crumb is not a link").to.have.length(0);
                    } else {
                        expect($li.attr("aria-current"), "only the last crumb is current").to.be.undefined;
                        const $a = $li.children("a");
                        expect($a, "crumb links").to.have.length(1);
                        expect($a.attr("typeof"), "a typeof").to.eq("WebPage");
                        expect($a.attr("property"), "a property").to.eq("item");
                    }
                });
            cy.get('nav[aria-label="breadcrumb"] > ul').first().find("> li")
                .first()
                .should(($li) => expect($li.text().trim()).to.eq("Home"))
                .find("a")
                .should("have.attr", "href")
                .and("match", /\/$/);
            if (current) {
                cy.get('nav[aria-label="breadcrumb"] > ul').first().find("> li")
                    .last()
                    .invoke("text")
                    .then((text) => expect(text.replace(/\s+/g, " ").trim()).to.eq(current));
            }
        });
    });
});
