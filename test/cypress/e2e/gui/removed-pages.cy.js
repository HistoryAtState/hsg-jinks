// Pages deliberately absent from this app (OP#627): /browse.html was a
// USWDS-profile demo with no counterpart in hsg-shell or this app's IA.
// The config.json "skip" entry keeps jinks update from regenerating the
// template; this pins the route staying gone.

it("/browse.html is removed and 404s", () => {
    cy.request({ url: "browse.html", failOnStatusCode: false }).its("status").should("eq", 404);
});
