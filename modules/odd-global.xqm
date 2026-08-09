xquery version "3.1";

module namespace config="http://e-editiones.org/tei-publisher/odd-global";

(:
    Determine the application root collection from the current module load path.
:)
declare variable $config:app-root :=
    let $rawPath := system:get-module-load-path()
    let $modulePath :=
    (: strip the xmldb: part :)
    if (starts-with($rawPath, "xmldb:exist://")) then
        if (starts-with($rawPath, "xmldb:exist://embedded-eXist-server")) then
            substring($rawPath, 36)
        else
            substring($rawPath, 15)
    else
        $rawPath
    return
        substring-before($modulePath, "/modules")
;

(:~
 : The root of the collection hierarchy containing data.
 :)
 
    
    declare variable $config:data-root := "/db/apps/frus-data-jinks/data";
    


(:~
 : The root of the collection hierarchy containing registers data.
 :)
declare variable $config:register-root := $config:data-root || "/registers";

(:~
 : The name of the FRUS volumes collection inside the data directory
 : (PR #32 review): compiled ODD transforms import this module under the
 : global: prefix, so models reference it as $global:frus-volumes instead
 : of hardcoding the literal. Keep in sync with generated-config.xql's
 : $config:frus-volumes (this module cannot import it: odd-global must
 : stay dependency-free for the transform pipeline).
 :)
declare variable $config:frus-volumes as xs:string := "frus-v2-data";

(:~
 : The default data collection.
 :)

  declare variable $config:data-default as xs:string :=   $config:data-root || "/" || $config:frus-volumes;


(:~
 : Addressing method used in the app: by id or not
 :)

    declare variable $config:address-by-id as xs:boolean :=  false() ;


declare variable $config:browse-page := "browse.html";