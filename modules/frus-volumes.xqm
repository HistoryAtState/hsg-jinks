xquery version "3.1";

(:~
 : The FRUS volumes, read from their main files.
 :
 : A volume is a child collection of $config:data-default holding a TEI file
 : named after it (frus1981-88v05/frus1981-88v05.xml). Only that file
 : carries the volume-level header data: revisionDesc and its status
 : changes, the tag keywords and the ebook relatedItems. The rest of the
 : collection holds the divisions, about 390,000 files on the full data.
 :
 : Read that header data from these roots, never with
 : collection($config:data-default)//...: the FRUS data has no index on
 : these elements, so such a search reads every file and takes from
 : seconds to minutes per call on the full data.
 :)
module namespace volumes="https://history.state.gov/ns/frus-volumes";

declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";

(:~ The root element of every volume's main file. :)
declare function volumes:roots() as element(tei:TEI)* {
    for $vol-id in xmldb:get-child-collections($config:data-default)
    let $path := $config:data-default || "/" || $vol-id || "/" || $vol-id || ".xml"
    where doc-available($path)
    return doc($path)/tei:TEI
};
