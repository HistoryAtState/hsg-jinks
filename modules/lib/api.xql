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

 

import module namespace aboutapi="http://teipublisher.com/api/about" at "../about-api.xql";

 

import module namespace tagapi="http://teipublisher.com/api/tags" at "../tags-api.xql";

 

import module namespace milapi="http://teipublisher.com/api/milestones" at "../milestones-api.xql";

 

import module namespace searchapi="https://history.state.gov/api/search" at "../search-api.xql";

 

import module namespace devapi="http://teipublisher.com/api/developer" at "../developer-api.xql";

 

import module namespace eduapi="http://teipublisher.com/api/education" at "../education-api.xql";

 

import module namespace confapi="http://teipublisher.com/api/conferences" at "../conferences-api.xql";

 

import module namespace ogapi="http://teipublisher.com/api/open" at "../opengov-api.xql";

 

import module namespace hsg-errors="https://history.state.gov/ns/site/hsg/errors" at "../hsg-errors.xqm";

 

import module namespace servicesapi="https://history.state.gov/api/services" at "../services-api.xql";

 

import module namespace menuapi="https://history.state.gov/api/menu" at "../menu-api.xql";

 

import module namespace opdsapi="http://teipublisher.com/api/opds" at "../opds-catalog-api.xql";



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
        
        
        "modules/opds-catalog-api.json",
        
         
        
        "modules/menu-api.json",
        
         
        
        "modules/services-api.json",
        
         
        
         
        
        "modules/opengov-api.json",
        
         
        
        "modules/conferences-api.json",
        
         
        
        "modules/education-api.json",
        
         
        
        "modules/developer-api.json",
        
         
        
        "modules/search-api.json",
        
         
        
        "modules/milestones-api.json",
        
         
        
        "modules/tags-api.json",
        
         
        
        "modules/about-api.json",
        
         
        
        "modules/departmenthistory-api.json",
        
         
        
        "modules/countries-api.json",
        
         
        
        "modules/hsg-api.json",
        
        
        "modules/lib/api.json"
    ), $lookup)
return
    $resp