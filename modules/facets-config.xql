module namespace facets-config="http://teipublisher.com/api/facets-config";

import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";

declare function facets-config:get-name($id as xs:string, $type as xs:string) as xs:string {
    let $entity := collection($config:register-root)/id($id)
    return head((
            switch ($type)
                case 'place' return head(($entity//tei:placeName[@type = "main"], $entity//tei:placeName))
                case 'actor' return head(($entity//(tei:persName | tei:orgName)[@type = "main"], $entity//tei:placeName))
                default return "ERR",
             "Unresolvable entity " || $id || " of type " || $type)
        )
};

(:
 : Display configuration for facets to be shown in the sidebar. The facets themselves
 : are configured in the index configuration, collection.xconf.
 :)
declare variable $facets-config:facets := [
    map {
        "dimension": "frus-volume-id",
        "heading": "facets.volume",
        "max": 5,
        "hierarchical": false()
    }
];