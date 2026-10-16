xquery version "3.1";

(:~
 : Handler for the generated API routes this app does not serve, see
 : disabled-api.json.
 :)
module namespace disabledapi = "https://history.state.gov/api/disabled";

import module namespace errors = "http://e-editiones.org/roaster/errors";

(:~
 : Answer like an unknown path: the route's x-error-handler renders the 404 page.
 :)
declare function disabledapi:not-found($request as map(*)) {
    error($errors:NOT_FOUND, "Not found: " || $request?path)
};
