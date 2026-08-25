// Breadcrumbs carry schema.org RDFa (OP#1334; reference parity with
// hsg-shell): ul[typeof=BreadcrumbList][vocab], li[typeof=ListItem]
// [property=itemListElement], a[typeof=WebPage][property=item]. Mirrors the
// parked legacy contract in ui-components/breadcrumb.cy.js (OP#1318), which
// can un-skip once this ships; asserted here across one page per breadcrumb
// implementation (layout default, section modules, literal template blocks).

[
    "historicaldocuments/frus-history/chapter-4",
    "historicaldocuments/frus1981-88v05/d57",
    "about/contact-us",
    "departmenthistory/short-history/foundations",
    "countries/argentina",
    "milestones/1961-1968",
].forEach((path) => {
    it(`/${path} breadcrumb carries schema.org RDFa`, () => {
        cy.visit(path);
        cy.get('nav[aria-label="breadcrumb"] ul', { timeout: 15000 })
            .first()
            .should("have.attr", "typeof", "BreadcrumbList")
            .and("have.attr", "vocab", "http://schema.org/");
        cy.get('nav[aria-label="breadcrumb"] ul')
            .first()
            .find("> li")
            .each(($li) => {
                expect($li.attr("typeof"), "li typeof").to.eq("ListItem");
                expect($li.attr("property"), "li property").to.eq("itemListElement");
            });
        cy.get('nav[aria-label="breadcrumb"] ul')
            .first()
            .find("> li > a")
            .each(($a) => {
                expect($a.attr("typeof"), "a typeof").to.eq("WebPage");
                expect($a.attr("property"), "a property").to.eq("item");
            });
    });
});
