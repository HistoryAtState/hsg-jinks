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

// The footer carries real content in the navy design (#1086): link columns
// in the nav, then the USWDS big footer's secondary section with the
// wordmark and agency on the left, social accounts and contact on the right. Nothing of the USWDS example survives -- no
// placeholder text, no dead javascript:void(0) links, no sign-up form.
describe("footer content", () => {
    beforeEach(() => cy.visit(`${VOLUME}/ch1`));

    it("has the two link columns of the design", () => {
        cy.get("footer.usa-footer .usa-footer__primary-link").then(($h) =>
            expect([...$h].map((el) => el.textContent.trim())).to.deep.equal([
                "Learn more",
                "Topics",
            ])
        );
    });

    it("keeps contact in the secondary section, as the USWDS big footer does", () => {
        cy.get("footer.usa-footer .usa-footer__nav .usa-footer__contact-links").should(
            "not.exist"
        );
        cy.get(
            "footer.usa-footer .usa-footer__secondary-section .usa-footer__contact-heading"
        ).should("have.text", "Contact");
    });

    it("carries the policy links in the bottom required-links row", () => {
        cy.get("footer.usa-footer .usa-footer__required-links a").then(($a) =>
            expect([...$a].map((el) => el.textContent.trim())).to.deep.equal([
                "Accessibility Statement",
                "Privacy Policy",
                "External Link Policy",
                "Copyright Information",
                "Content Warning",
            ])
        );
    });

    it("carries the hsg-shell 'Learn more' links, including Contact Us", () => {
        cy.get("footer.usa-footer .usa-footer__primary-content")
            .first()
            .find("a")
            .then(($a) =>
                expect(
                    [...$a].map((el) => [el.textContent.trim(), el.getAttribute("href")])
                ).to.deep.equal([
                    ["Home", "/exist/apps/hsg-jinks/"],
                    ["Search", "/exist/apps/hsg-jinks/search"],
                    ["About Us", "/exist/apps/hsg-jinks/about"],
                    ["Contact Us", "/exist/apps/hsg-jinks/about/contact-us"],
                    ["FAQ", "/exist/apps/hsg-jinks/about/faq"],
                ])
            );
    });

    it("sets the policy links off in the headings' colour, under a rule of it", () => {
        cy.get("footer.usa-footer .usa-footer__primary-link")
            .first()
            .then(($h) => {
                const heading = $h.css("color");
                cy.get("footer.usa-footer .usa-footer__required-links")
                    .should("have.css", "border-top-color", heading)
                    .and("have.css", "border-top-style", "solid");
                cy.get("footer.usa-footer .usa-footer__required-links a").each(($a) =>
                    expect($a.css("color")).to.equal(heading)
                );
            });
    });

    it("links every topic within this app, department policies to state.gov", () => {
        ["Historical Documents", "Department History", "Countries"].forEach((label) => {
            cy.get("footer.usa-footer a")
                .contains(label)
                .should("have.attr", "href")
                .and("match", /^\/exist\/apps\/hsg-jinks\//);
        });
        cy.get("footer.usa-footer a")
            .contains("Privacy Policy")
            .should("have.attr", "href", "https://www.state.gov/privacy-policy/");
    });

    it("reaches the office by phone and mail", () => {
        cy.get("footer.usa-footer .usa-footer__address a").then(($a) =>
            expect([...$a].map((el) => el.getAttribute("href"))).to.deep.equal([
                "tel:2029550200",
                "mailto:history@state.gov",
            ])
        );
    });

    it("links the office's own social accounts", () => {
        cy.get("footer.usa-footer .usa-social-link").then(($a) =>
            expect([...$a].map((el) => el.getAttribute("href"))).to.deep.equal([
                "https://x.com/HistoryAtState",
                "https://github.com/HistoryAtState",
            ])
        );
    });

    it("closes with the wordmark and the parent bureau", () => {
        cy.get("footer.usa-footer .usa-footer__logo-img")
            .should("have.attr", "alt")
            .and("contain", "Office of the Historian");
        cy.get("footer.usa-footer .usa-footer__agency-parent").should(
            "contain.text",
            "United States Department of State"
        );
    });

    it("sits on the navy ground of the design", () => {
        // The design's #173a57, snapped to the palette's primary-darkest (OP#1426).
        cy.get("footer.usa-footer").should(
            "have.css",
            "background-color",
            "rgb(17, 47, 78)"
        );
    });

    it("has no leftover USWDS example scaffold", () => {
        cy.get("footer.usa-footer").within(() => {
            cy.get('a[href="javascript:void(0);"]').should("not.exist");
            cy.get(".usa-sign-up").should("not.exist");
        });
        cy.get("footer.usa-footer")
            .invoke("text")
            .should("not.match", /<Secondary link|<Topic>|<Name of Agency>/);
    });
});

// Below mobile-lg (480px) USWDS runs the footer nav edge to edge and leaves
// the inset to its components (OP#1465). The document is wider than the
// viewport there in stock USWDS too (the gapped row's overhang, clipped by
// body overflow-x: hidden), so these check what a reader sees instead.
describe("footer on a phone", () => {
    beforeEach(() => {
        cy.viewport(390, 844);
        cy.visit(`${VOLUME}/ch1`);
    });

    it("keeps every text and icon at least 16px from the screen edges", () => {
        cy.get(
            "footer.usa-footer :is(a, p, button, img, .usa-footer__primary-link)"
        ).each(($el) => {
            const el = $el[0];
            if (!el.getClientRects().length) return; // collapsed list
            const range = el.ownerDocument.createRange();
            range.selectNodeContents(el);
            const box = el.tagName === "IMG" ? el.getBoundingClientRect() : range.getBoundingClientRect();
            if (!box.width) return;
            expect(box.left, el.textContent.trim() || el.alt).to.be.at.least(16);
            expect(box.right, el.textContent.trim() || el.alt).to.be.at.most(390 - 16);
        });
    });

    it("renders every column heading as a left-aligned bar on the footer ground", () => {
        cy.get("footer.usa-footer .usa-footer__primary-link").each(($h) => {
            expect($h).to.have.class("usa-footer__primary-link--button");
            expect($h.css("background-color")).to.equal("rgba(0, 0, 0, 0)");
            expect($h.css("justify-content")).to.equal("flex-start");
            expect($h.css("margin-bottom")).to.equal("0px");
        });
    });

    it("shows the wordmark unfiltered", () => {
        cy.get("footer.usa-footer .usa-footer__logo-img").should("have.css", "filter", "none");
    });
});
