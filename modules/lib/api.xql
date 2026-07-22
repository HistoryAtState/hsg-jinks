xquery version "3.1";

declare namespace api="https://tei-publisher.com/xquery/api";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace roaster="http://e-editiones.org/roaster";
import module namespace auth="http://e-editiones.org/roaster/auth";
import module namespace rutil="http://e-editiones.org/roaster/util";
import module namespace dapi="http://teipublisher.com/api/documents" at "api/document.xql";
import module namespace capi="http://teipublisher.com/api/collection" at "api/collection.xql";
import module namespace sapi="http://teipublisher.com/api/search" at "api/search.xql";
import module namespace iapi="http://teipublisher.com/api/info" at "api/info.xql";
import module namespace vapi="http://teipublisher.com/api/view" at "api/view.xql";
import module namespace nlp="http://teipublisher.com/api/nlp" at "api/nlp.xql";
import module namespace rapi="http://teipublisher.com/api/registers" at "../registers.xql";
import module namespace deploy="https://teipublisher.org/api/deploy" at "api/deploy.xql";



import module namespace hsgapi="http://teipublisher.com/api/hsg" at "../hsg-api.xql";

import module namespace countryapi="http://teipublisher.com/api/countries" at "../countries-api.xql";

import module namespace dhapi="http://teipublisher.com/api/departmenthistory" at "../departmenthistory-api.xql";



declare option output:indent "no";

let $lookup := function($name as xs:string) {
    try {
        function-lookup(xs:QName($name), 1)
    } catch * {
        ()
    }
}
let $resp := roaster:route(
    (
        "modules/countries-api.json",
        "modules/departmenthistory-api.json",
        "modules/hsg-api.json",
        "modules/lib/api.json"
    ), $lookup)
return
    $resp