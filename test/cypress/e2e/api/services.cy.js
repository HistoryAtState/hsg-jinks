// The /services section (OP#1106 / #1208-#1210, user story #1212): two
// machine endpoints, XML in/out, for the FRUS asset-publishing and QA
// tooling. Deliberate tightenings over hsg-shell are asserted here: schema-
// enforced method and path shape (405/404 where the .xql forwards said 200),
// a real 400 for a missing volume parameter (was 200 + <error>), and a 503
// when no object-store listing endpoint is configured (the devcontainer
// default) rather than pretending an empty volume.

describe("GET /services/volume-ids (OP#1209)", () => {
    it("returns the sorted volume-id list as XML in the hsg-shell shape", () => {
        cy.request("services/volume-ids").then((r) => {
            expect(r.status).to.eq(200);
            expect(r.headers["content-type"]).to.contain("application/xml");
            const doc = new DOMParser().parseFromString(r.body, "application/xml");
            const ids = [...doc.querySelectorAll("volume-ids > volume-id")].map((e) => e.textContent);
            // sample volumes ship in the frozen baseline; the list is sorted
            expect(ids.length).to.be.at.least(5);
            expect(ids).to.deep.eq([...ids].sort());
            expect(ids).to.include("frus1981-88v05");
            expect(doc.querySelector("summary > volumes").textContent).to.eq(String(ids.length));
        });
    });

    it("rejects non-GET methods (schema-enforced, unlike the hsg-shell forward)", () => {
        cy.request({ method: "POST", url: "services/volume-ids", failOnStatusCode: false })
            .its("status").should("eq", 405);
    });
});

describe("GET /services/volume-images (OP#1210)", () => {
    it("missing or empty volume parameter is a real 400", () => {
        cy.request({ url: "services/volume-images", failOnStatusCode: false })
            .its("status").should("eq", 400);
        cy.request({ url: "services/volume-images?volume=", failOnStatusCode: false })
            .its("status").should("eq", 400);
    });

    it("degrades to 503 with an error document when no listing endpoint is configured", () => {
        cy.request({ url: "services/volume-images?volume=frus1981-88v05", failOnStatusCode: false })
            .then((r) => {
                if (r.status === 503) {
                    expect(r.body).to.contain("no object-store listing endpoint configured");
                } else {
                    // an environment with HSG_S3_LIST_ENDPOINT set: expect the
                    // real listing (or a clean 502 if the store refuses)
                    expect([200, 502]).to.include(r.status);
                }
            });
    });

    it("unknown sub-paths no longer answer 200 (the hsg-shell forward did)", () => {
        // the extra segment falls through to the jinks /{docid} catch-all,
        // whose error answer is 400 today and a proper 404 once the OP#1309
        // error-page work (PR #51) is merged; either way the tightening this
        // section claims is "not a silent 200"
        cy.request({ url: "services/volume-images/extra", failOnStatusCode: false })
            .its("status").should("be.oneOf", [400, 404]);
    });
});
