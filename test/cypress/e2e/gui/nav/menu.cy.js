// Primary navigation menu (OP#1279). The menu is defined as data in
// config.json `menu.items` and rendered by the USWDS extended header
// (templates/menu.html). It reproduces hsg-shell's `hsg-nav-content` category
// tree exactly -- same link targets, only under the hsg-jinks app root -- and
// is English-only. These are fixed UI chrome (not data-derived counts), so
// exact counts/hrefs are asserted (see CLAUDE.md's data-package caveat).

// App-root path prefix the server renders into every href, derived from the
// Cypress base URL (e.g. "/exist/apps/hsg-jinks").
const PREFIX = new URL(Cypress.config("baseUrl")).pathname.replace(/\/$/, "");

// The exact menu tree, mirroring hsg-shell app/templates/site.xml. `url` is the
// app-root-relative target ("" = the app root / Home).
const TOP_LINKS = [
    { label: "Home", url: "" },
    { label: "About Us", url: "about" },
];

const CATEGORIES = [
    {
        label: "Historical Documents",
        submenu: "submenu-historicaldocuments",
        items: [
            ["Foreign Relations of the United States", "historicaldocuments"],
            ["About the Foreign Relations Series", "historicaldocuments/about-frus"],
            ["Status of the Foreign Relations Series", "historicaldocuments/status-of-the-series"],
            ["History of the Foreign Relations Series", "historicaldocuments/frus-history"],
            ["Ebooks Initiative", "historicaldocuments/ebooks"],
            ["Quarterly Releases", "historicaldocuments/quarterly-releases"],
        ],
    },
    {
        label: "Department History",
        submenu: "submenu-departmenthistory",
        items: [
            ["Overview", "departmenthistory"],
            ["Biographies of the Secretaries of State", "departmenthistory/people/secretaries"],
            ["Principal Officers and Chiefs of Mission", "departmenthistory/people/principals-chiefs"],
            ["Travels of the Secretary of State", "departmenthistory/travels/secretary"],
            ["Travels of the President", "departmenthistory/travels/president"],
            ["Visits by Foreign Heads of State", "departmenthistory/visits"],
            ["World War I and the Department", "departmenthistory/wwi"],
            ["Buildings of the Department of State", "departmenthistory/buildings"],
            ["U.S. Diplomatic Couriers", "departmenthistory/diplomatic-couriers"],
            ["U.S. Marine Corps", "departmenthistory/marine-corps"],
        ],
    },
    {
        label: "Guide to Countries",
        submenu: "submenu-countries",
        items: [
            ["Guide to Country Recognition and Relations", "countries"],
            ["World Wide Diplomatic Archives Index", "countries/archives"],
        ],
    },
    {
        label: "More Resources",
        submenu: "submenu-resources",
        items: [
            ["Browse Resources by Subject Tag", "tags"],
            ["Conferences", "conferences"],
            ["Contact Us", "about/contact-us"],
            ["Developer Resources & APIs", "developer"],
            ["Educational Resources", "education"],
            ["Frequently Asked Questions", "about/faq"],
            ["Key Milestones", "milestones"],
            ["Open Government Initiative", "open"],
            ["A Short History of the Department", "departmenthistory/short-history"],
        ],
    },
];

const href = (url) => (url === "" ? `${PREFIX}/` : `${PREFIX}/${url}`);

describe("primary navigation menu", () => {
    // data-i18n resolves labels client-side; wait for one known label before
    // asserting text so we never read the pre-i18n fallback (the raw item id).
    beforeEach(() => {
        cy.visit("index.html");
        cy.contains(".usa-nav__primary-item", "Historical Documents", { timeout: 15000 });
    });

    it("renders the USWDS extended mega-menu header, English-only", () => {
        cy.get(".usa-header.usa-header--extended.usa-header--megamenu").should("exist");
        cy.get("html").should("have.attr", "lang", "en");
        cy.get("pb-page").should("have.attr", "supported-languages", "en");
    });

    it("has exactly the six hsg-shell top-level items, in order", () => {
        // Read each primary item's *direct* control label (the submenu <ul> is a
        // sibling of the button, so its text must not be folded in). Exact
        // equality: parity with hsg-shell means nothing extra either.
        cy.get(".usa-nav__primary > .usa-nav__primary-item > a, .usa-nav__primary > .usa-nav__primary-item > button")
            .then(($controls) => {
                const labels = [...$controls].map((el) => el.textContent.replace(/\s+/g, " ").trim());
                expect(labels).to.deep.eq([
                    "Home",
                    "Historical Documents",
                    "Department History",
                    "Guide to Countries",
                    "More Resources",
                    "About Us",
                ]);
            });
    });

    it("italicizes Foreign Relations in the Historical Documents menu (OP#1457)", () => {
        cy.get("#submenu-historicaldocuments a").should(($a) => {
            const italic = [...$a].map((a) => [...a.querySelectorAll("em")].map((em) => em.textContent));
            expect(italic).to.deep.eq([
                ["Foreign Relations of the United States"],
                ["Foreign Relations"],
                ["Foreign Relations"],
                ["Foreign Relations"],
                [],
                [],
            ]);
        });
    });

    it("translates every submenu label", () => {
        // The submenu labels use data-i18n, which shows a missing key as is:
        // every menu item needs its menu.{id} entry in en.json.
        cy.get(".usa-nav__submenu a").each(($a) => {
            expect($a.text().trim()).not.to.match(/^menu\./);
        });
    });

    it("keeps the top-level chevrons white", () => {
        // The top-level labels stay pb-i18n: the theme draws the chevron on
        // the label's ::after, and on a span it falls back to USWDS's
        // ButtonText (black).
        cy.get(".usa-nav__primary > .usa-nav__primary-item > button").each(($b) => {
            const label = $b[0].firstElementChild;
            expect(label.tagName).to.eq("PB-I18N");
            expect(getComputedStyle(label, "::after").backgroundColor).to.eq("rgb(255, 255, 255)");
        });
    });

    it("italicizes Foreign Relations in the breadcrumb, too", () => {
        cy.visit("historicaldocuments/about-frus");
        cy.get('nav[aria-label="breadcrumb"] ul:not(:empty) li')
            .last()
            .find("em", { timeout: 15000 })
            .should("have.text", "Foreign Relations");
    });

    it("renders no Admin or Download submenu (absent from hsg-shell's nav)", () => {
        cy.get("#submenu-admin").should("not.exist");
        cy.get("#submenu-download").should("not.exist");
    });

    it("accordion buttons stay inside their item (About Us not painted over)", () => {
        // Regression: layout.css keeps the header chrome at content-box and
        // USWDS's inherit reset spread that into the nav, where the width:100%
        // + padding accordion buttons then painted 2rem past their own list
        // item, hiding the start of the next one ("About Us" showed as
        // "out Us" under the More Resources caret). hsg-theme.css re-anchors
        // border-box on .usa-nav__primary (not .usa-header: the page-box
        // containers must stay content-box, see page-width-alignment.cy.js).
        cy.get(".usa-nav__primary > .usa-nav__primary-item > button").each(($btn) => {
            expect(getComputedStyle($btn[0]).boxSizing, "accordion button box-sizing").to.eq("border-box");
        });
        cy.contains(".usa-nav__primary-item > button", "More Resources").then(($btn) => {
            cy.contains(".usa-nav__primary-item > a", "About Us").then(($a) => {
                const btnRight = $btn[0].getBoundingClientRect().right;
                const aboutLeft = $a[0].getBoundingClientRect().left;
                expect(btnRight, "More Resources button must not overlap About Us").to.be.at.most(aboutLeft + 0.5);
            });
        });
    });

    it("renders no Admin or Download submenu on a content page either", () => {
        // The Admin submenu used to leak into every inline-rendered page, so
        // assert on a content page too, not just the home page. (The Download
        // submenu was only injected on document-context pages; FRUS volume
        // pages currently 404 in the dev containers, so its absence is covered
        // by the /menu fragment test and the template removal itself.)
        cy.visit("milestones/1750-1775");
        cy.contains(".usa-nav__primary-item", "Historical Documents", { timeout: 15000 });
        cy.get("#submenu-admin").should("not.exist");
        cy.get("#submenu-download").should("not.exist");
    });

    TOP_LINKS.forEach(({ label, url }) => {
        it(`"${label}" is a direct link to ${href(url)}`, () => {
            cy.contains(".usa-nav__primary-item > a", label).should("have.attr", "href", href(url));
        });
    });

    CATEGORIES.forEach((cat) => {
        describe(cat.label, () => {
            it("is an accordion button (no landing href of its own)", () => {
                cy.contains(".usa-nav__primary-item > button.usa-accordion__button", cat.label)
                    .should("have.attr", "aria-controls", cat.submenu);
            });

            cat.items.forEach(([label, url]) => {
                it(`links "${label}" to ${href(url)}`, () => {
                    cy.get(`#${cat.submenu}`)
                        .contains(".usa-nav__submenu-item > a", label)
                        .should("have.attr", "href", href(url));
                });
            });
        });
    });

    it("shows English labels, never German", () => {
        cy.get(".usa-nav__primary").invoke("text").then((text) => {
            expect(text).to.contain("Historical Documents");
            expect(text).to.contain("Foreign Relations of the United States");
            ["Sammlungen", "Über die Edition", "Schnellstart", "Zitierung"].forEach((de) =>
                expect(text, `no German: ${de}`).not.to.contain(de)
            );
        });
    });

    it("highlights the active category with usa-current", () => {
        // Use /departmenthistory rather than /historicaldocuments: the latter
        // landing page is currently broken in the dev containers (frus-v2 data
        // layout drift dumps raw template source, so page scripts, including
        // nav-active.js, never load there). The nav behaviour under test is
        // identical on any section page.
        cy.visit("departmenthistory");
        cy.get(".usa-nav__primary-item > button.usa-current")
            .should("contain.text", "Department History");
    });
});

describe("cacheable menu fragments (nginx SSI)", () => {
    it("GET /menu returns the public nav only -- no admin/download/login", () => {
        // Relative URL: Cypress resolves it against baseUrl (which already
        // carries the /exist/apps/hsg-jinks path). An absolute PREFIX path here
        // would double-prefix and fall through to the /{docid} 404 route.
        cy.request("menu").then((res) => {
            expect(res.status).to.eq(200);
            expect(res.headers["content-type"]).to.contain("application/xml");
            // Innards only: the stable usa-header wrapper stays in the page
            // body (templates/menu.html); the fragment starts at the navbar.
            expect(res.body).to.contain("usa-nav__primary");
            expect(res.body).to.contain('id="submenu-historicaldocuments"');
            expect(res.body).to.not.contain("usa-header--megamenu");
            expect(res.body).to.not.contain("submenu-admin");
            expect(res.body).to.not.contain("submenu-download");
            expect(res.body.trimStart()).to.match(/^<div/); // bare fragment, no DOCTYPE
        });
    });

    it("GET /menu-mobile returns the mobile nav fragment", () => {
        cy.request("menu-mobile").then((res) => {
            expect(res.status).to.eq(200);
            // Innards only; the "mobile menubar" wrapper div stays in the
            // page body (templates/menu-mobile.html).
            expect(res.body).to.contain('details class="dropdown"');
            expect(res.body).to.contain("historicaldocuments");
            expect(res.body).to.not.contain("mobile menubar");
        });
    });
});
