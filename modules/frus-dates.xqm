xquery version "3.1";

(:~
 : Date-string normalizer for FRUS document-date filtering (OP#1102).
 :
 : Accepts the shapes hsg-shell's date filters have always accepted: a full
 : xs:dateTime, an xs:date, "yyyy-mm-ddThh:mm" (no seconds), "yyyy-mm", or a
 : bare "yyyy" — expanding partial dates to the start (normalize-low) or end
 : (normalize-high) of the period they denote. Malformed input returns the
 : empty sequence rather than raising (each call site decides whether that
 : should 400 or fall back).
 :
 : Ported near-verbatim from hsg-shell's modules/frus-dates.xqm; the standalone
 : microsite's fd:wrap-html was not ported (dead in this app — search renders
 : through the normal template pipeline).
 :)
module namespace fd = "http://history.state.gov/ns/site/hsg/frus-dates";

(:~
 : Last day-of-month for a "yyyy-mm" string, without a functx dependency:
 : the day before the first of the following month.
 :)
declare %private function fd:last-day-of-month($yearMonth as xs:string) as xs:integer {
    day-from-date(
        (xs:date($yearMonth || "-01") + xs:yearMonthDuration("P1M")) - xs:dayTimeDuration("P1D")
    )
};

declare function fd:normalize-low($date as xs:string, $timezone as xs:dayTimeDuration) as xs:dateTime? {
    try {
        let $dateTime :=
            if ($date castable as xs:dateTime) then
                adjust-dateTime-to-timezone(xs:dateTime($date), $timezone)
            else if ($date castable as xs:date) then
                let $adjusted-date := adjust-date-to-timezone(xs:date($date), $timezone)
                return
                    substring($adjusted-date, 1, 10) || 'T00:00:00' || substring($adjusted-date, 11)
            else if (matches($date, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$')) then
                adjust-dateTime-to-timezone(xs:dateTime($date || ':00'), $timezone)
            else if (matches($date, '^\d{4}-\d{2}$')) then
                adjust-dateTime-to-timezone(xs:dateTime($date || '-01T00:00:00'), $timezone)
            else (: if (matches($date, '^\d{4}$')) then :)
                adjust-dateTime-to-timezone(xs:dateTime($date || '-01-01T00:00:00'), $timezone)
        return
            $dateTime cast as xs:dateTime
    } catch * {
        ()
    }
};

declare function fd:normalize-high($date as xs:string, $timezone as xs:dayTimeDuration) as xs:dateTime? {
    try {
        let $dateTime :=
            if ($date castable as xs:dateTime) then
                adjust-dateTime-to-timezone(xs:dateTime($date), $timezone)
            else if ($date castable as xs:date) then
                let $adjusted-date := adjust-date-to-timezone(xs:date($date), $timezone)
                return
                    substring($adjusted-date, 1, 10) || 'T23:59:59' || substring($adjusted-date, 11)
            else if (matches($date, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$')) then
                adjust-dateTime-to-timezone(xs:dateTime($date || ':59'), $timezone)
            else if (matches($date, '^\d{4}-\d{2}$')) then
                adjust-dateTime-to-timezone(xs:dateTime($date || '-' || fd:last-day-of-month($date) || 'T23:59:59'), $timezone)
            else (: if (matches($date, '^\d{4}$')) then :)
                adjust-dateTime-to-timezone(xs:dateTime($date || '-12-31T23:59:59'), $timezone)
        return
            $dateTime cast as xs:dateTime
    } catch * {
        ()
    }
};
