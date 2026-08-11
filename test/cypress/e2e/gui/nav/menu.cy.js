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
    // pb-i18n resolves labels client-side; wait for one known label before
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

    it("has the six hsg-shell top-level items in order", () => {
        // Read each primary item's *direct* control label (the submenu <ul> is a
        // sibling of the button, so its text must not be folded in).
        cy.get(".usa-nav__primary > .usa-nav__primary-item > a, .usa-nav__primary > .usa-nav__primary-item > button")
            .then(($controls) => {
                const labels = [...$controls].map((el) => el.textContent.replace(/\s+/g, " ").trim());
                expect(labels[0]).to.eq("Home");
                ["Historical Documents", "Department History", "Guide to Countries", "More Resources", "About Us"]
                    .forEach((l) => expect(labels).to.include(l));
            });
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
        cy.visit("historicaldocuments");
        cy.get(".usa-nav__primary-item > button.usa-current")
            .should("contain.text", "Historical Documents");
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
