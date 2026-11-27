xquery version "3.1";

(:~
 : A shared signal that lets a Roaster middleware end a request.
 :
 : Roaster runs every middleware and then always calls the handler, whose
 : status wins; the only way out, raising an error, is logged at ERROR level
 : whatever the route's error handler then answers (eeditiones/roaster#183).
 : Instead, a middleware puts the answer on the request (mw:answer, mw:fail).
 : mw:guard keeps the following middlewares from running on such a request,
 : and mw:wrap, which api.xql puts around every handler, sends the answer
 : instead of calling the handler. Roaster writes it like any other response.
 :)
module namespace mw="https://history.state.gov/ns/site/hsg/middleware";

import module namespace roaster="http://e-editiones.org/roaster";
import module namespace errors="http://e-editiones.org/roaster/errors";

(:~ The request key holding the answer. :)
declare variable $mw:ANSWER := xs:QName("mw:answer");

(:~ End the request with this response (a roaster response map). :)
declare function mw:answer($request as map(*), $response as map(*)) as map(*) {
    map:put($request, $mw:ANSWER, map { "response": $response })
};

(:~
 : End the request with an error, answered by the route's x-error-handler
 : as if it had been raised, but without Roaster's error path. $error has the
 : shape an error handler receives: "code" and "description".
 :)
declare function mw:fail($request as map(*), $error as map(*)) as map(*) {
    map:put($request, $mw:ANSWER, map { "error": $error })
};

declare function mw:answered($request as map(*)) as xs:boolean {
    map:contains($request, $mw:ANSWER)
};

(:~ A middleware that does not run once an earlier one has answered. :)
declare function mw:guard($middleware as function(*)) as function(*) {
    function($request as map(*), $response as map(*)) as map(*)+ {
        if (mw:answered($request)) then
            ($request, $response)
        else
            $middleware($request, $response)
    }
};

(:~
 : Wraps a handler looked up by api.xql: an answered request gets its answer,
 : anything else goes to the handler. $resolve looks up the route's
 : x-error-handler for mw:fail. Error handlers are looked up through the same
 : function and receive an error map, which is passed through.
 :)
declare function mw:wrap($handler as function(*), $resolve as function(xs:string) as function(*)?) as function(*) {
    function($arg) {
        if ($arg instance of map(*) and mw:answered($arg)) then
            mw:send($arg, $resolve)
        else
            $handler($arg)
    }
};

declare %private function mw:send($request as map(*), $resolve as function(xs:string) as function(*)?) {
    let $answer := $request($mw:ANSWER)
    return
        if (exists($answer?response)) then
            $answer?response
        else
            let $errorHandler := $request?config?x-error-handler ! $resolve(.)
            return
                if (exists($errorHandler)) then
                    $errorHandler($answer?error)
                else
                    roaster:response(errors:get-status-code-from-error($answer?error?code), "application/json", map {
                        "code": local-name-from-QName($answer?error?code),
                        "description": $answer?error?description
                    })
};
