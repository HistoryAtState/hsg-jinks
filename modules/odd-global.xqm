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


(: The app has no browse page (OP#627: /browse.html was a USWDS-profile
   demo, removed); the register facet links the base ODD builds from this
   point at the app's real collection root instead. :)
declare variable $config:browse-page := "historicaldocuments";

(:~
 : Database path of the document a node being rendered belongs to.
 :
 : ODD models must not derive this from base-uri(/) (PR #32 review). "/" is
 : shorthand for the root of the *context* item, so the expression only means
 : what a model intends while a context node happens to be in scope: run the
 : same string anywhere else (eXide, a unit test) and it resolves to every
 : document in the database instead, raising XPTY0004. The view pipeline
 : already carries the node it is rendering in $parameters?root
 : (page:transform sets it, and the base ODD's own pb model reads it the same
 : way), so take it from there.
 :
 : The node is only a fallback, for transforms invoked without that parameter.
 : Both are checked because either may be an in-memory fragment, which has no
 : document URI at all; when neither is a stored document the result is the
 : empty string, so callers can string-test it without a cardinality guard.
 :)
declare function config:source-uri($parameters as map(*)?, $node as node()?) as xs:string {
    head((
        for $candidate in ($parameters?root, $node)
        let $uri := document-uri(root($candidate))
        where exists($uri)
        return string($uri),
        ""
    ))
};

(:~
 : Identifier of a FRUS division: the file stem ("d275") of the document being
 : rendered. Empty when the node is not from a stored document.
 :
 : Footnote ids are qualified with it because a document and the attachments
 : xincluded into it are separate files whose anchor xml:ids collide (both
 : d96-a1.xml and d96-a2.xml carry d96-f1..f3). Deriving it from the page root
 : rather than from each node's own file gives every note on one page the same
 : prefix, distinguished by @n, which continues the parent's sequence across
 : the attachments.
 :)
declare function config:division-id($parameters as map(*)?, $node as node()?) as xs:string {
    replace(config:source-uri($parameters, $node), '^.*/([^/]+)\.xml$', '$1')
};

(:~
 : Identifier of the FRUS volume a node belongs to ("frus1977-80v27"), read
 : from the collection path: the segment right below $config:frus-volumes.
 :
 : Not read from the division's frus-volume-id bibl, because a transform may
 : receive a fragment whose root no longer carries the teiHeader. Empty for
 : anything outside the FRUS collection, so models can use it as their
 : "is this FRUS?" test as well.
 :)
declare function config:volume-id($parameters as map(*)?, $node as node()?) as xs:string {
    substring-before(
        substring-after(config:source-uri($parameters, $node), "/" || $config:frus-volumes || "/"),
        "/"
    )
};

(:~
 : App URL of a FRUS cross-reference (a ref's @target), or the empty sequence
 : when the ref is not one: outside the FRUS collection, or a target that is
 : neither "#…" nor "frus…". Reference parity with hsg-shell's pmf:ref. The
 : volume id is read once per call.
 :
 : Target forms in the v2 data:
 : - "#d5", "#pg747", "#pgVII": a division or page of the same volume
 : - "frus1977-80v26#d271": a division of another volume
 : - "frus1958-60v10p2": another volume's landing page
 : - "frus:frus1906p1/pg_280": a page of another volume
 :
 : Page-break ids carry no underscore ("pg747"); the public page URL does
 : ("pg_747", see hsgapi:view-interior), so page targets are mapped to it.
 :)
declare function config:frus-ref-uri($parameters as map(*)?, $node as element()) as xs:string? {
    let $volume := config:volume-id($parameters, $node)
    let $target := replace(string($node/@target), "^frus:", "")
    let $page := function($id as xs:string) {
        replace($id, "^pg([0-9]+|[IVXLCDMivxlcdm]+)$", "pg_$1")
    }
    let $path :=
        if ($volume = "") then
            ()
        else if (starts-with($target, "#")) then
            $volume || "/" || $page(substring($target, 2))
        else if (starts-with($target, "frus") and contains($target, "#")) then
            substring-before($target, "#") || "/" || $page(substring-after($target, "#"))
        else if (starts-with($target, "frus")) then
            $target
        else
            ()
    return
        $path ! ($parameters?context-path || "/historicaldocuments/" || .)
};

(:~
 : Base URI of the IIIF Image API service serving the FRUS page scans
 : (OP#1335). The same Cantaloupe instance the reference app's OpenSeadragon
 : viewer is hardcoded to (hsg-shell resources/scripts/app.js); kept here so
 : the ODD pb model, the pb-facsimile viewers and the pg_* facsimile page all
 : share one definition. Must end in "/": pb-facsimile concatenates
 : base-uri + facs verbatim.
 :)
declare variable $config:iiif-image-api as xs:string := "https://ci.history.state.gov/iiif/2/";

(:~
 : IIIF Image API identifier of the page scan a pb points to, relative to
 : $config:iiif-image-api ("frus%2Ffrus1981-88v05%2Ftiff%2F0347.tif"). The
 : image store lays FRUS scans out as frus/{volume}/tiff/{facs}.tif and the
 : Cantaloupe endpoint expects the path slashes percent-encoded (reference
 : parity: hsg-shell's app.js builds the identical identifier). Empty when
 : the pb carries no facs or the node is outside the FRUS collection (e.g.
 : an in-memory fragment), so models can predicate on it and fall back to a
 : plain page label.
 :)
declare function config:iiif-facs-id($parameters as map(*)?, $pb as element()) as xs:string? {
    let $volume := config:volume-id($parameters, $pb)
    return
        if ($volume != "" and $pb/@facs) then
            "frus%2F" || $volume || "%2Ftiff%2F" || $pb/@facs || ".tif"
        else
            ()
};

