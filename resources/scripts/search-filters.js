// The "Filter by" sidebar of the search landing and results pages
// (OP#1432, OP#1436, OP#1440).
//
// Sections: "Entire Office of the Historian Website" is exclusive with the
// sections. Ticking it clears them, ticking a section clears it, and clearing
// the last section ticks it again. It has no name: searching the whole site
// is the absence of a within parameter.
//
// Date: modules/templates/search.xqm renders the filter as separate
// month/day/year and hour/minute/am-pm parts (reference parity with
// hsg-shell), without names, plus hidden start-date/end-date/start-time/
// end-time fields that carry the actual query parameters. This script
//
// - enables the filter, and the volumes filter of the results sidebar, only
//   while "Historical Documents" is the only ticked section, and disables
//   them otherwise so none of it is submitted. Groups marked
//   data-hsg-documents-only="hide" are also hidden then; the sidebar
//   ("disable") keeps them visible (OP#1440);
// - on submit, combines the parts into the hidden fields: a year alone gives
//   "1941", a month and year "1941-12", a full date "1941-12-07"; an hour
//   (with optional minute) gives a 24-hour "HH:MM".
//
// Loaded as a classic script at the end of <body> (base10's script.custom),
// so the block keeps its bindings out of the global scope shared by all
// classic scripts.
"use strict";

{
    const FULL_DATE = /^\d{4}-\d{2}-\d{2}$/;

    /** The trimmed value of one date/time part, "" if absent. */
    const part = (scope, name) => scope.querySelector(`[data-part="${name}"]`)?.value.trim() ?? "";

    /** A whole number, or NaN for anything but digits. */
    const digits = (text) => (/^\d+$/.test(text) ? Number(text) : Number.NaN);

    const pad = (number, width) => String(number).padStart(width, "0");

    const inRange = (number, min, max) => number >= min && number <= max;

    const combineDate = (scope) => {
        const year = digits(part(scope, "year"));
        if (Number.isNaN(year)) {
            return "";
        }
        const month = digits(part(scope, "month"));
        if (!inRange(month, 1, 12)) {
            return pad(year, 4);
        }
        const day = digits(part(scope, "day"));
        return inRange(day, 1, 31)
            ? `${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}`
            : `${pad(year, 4)}-${pad(month, 2)}`;
    };

    const combineTime = (scope) => {
        const hour = digits(part(scope, "hour"));
        if (!inRange(hour, 1, 12)) {
            return "";
        }
        const minute = digits(part(scope, "minute"));
        // 12 am is midnight (00), 12 pm is noon (12)
        const hour24 = (hour % 12) + (part(scope, "period") === "pm" ? 12 : 0);
        return `${pad(hour24, 2)}:${pad(inRange(minute, 0, 59) ? minute : 0, 2)}`;
    };

    const combine = () => {
        for (const scope of document.querySelectorAll("[data-date-prefix]")) {
            const { datePrefix: prefix } = scope.dataset;
            const date = document.getElementById(`${prefix}-date`);
            const time = document.getElementById(`${prefix}-time`);
            if (date) {
                date.value = combineDate(scope);
            }
            if (time) {
                // a time only narrows a full date (YYYY-MM-DD); with a year or
                // a month alone it has no meaning
                time.value = FULL_DATE.test(date?.value ?? "") ? combineTime(scope) : "";
            }
            // leave empty fields out of the URL; recomputed on every submit
            for (const field of [date, time]) {
                if (field) {
                    field.disabled = !field.value;
                }
            }
        }
    };

    const sectionBoxes = () => [...document.querySelectorAll('input[type="checkbox"][name="within"]')];

    const entireSiteBox = () => document.querySelector("input[data-hsg-entire-site]");

    /** Keep "Entire Office" and the sections mutually exclusive. */
    const keepExclusive = (changed) => {
        const entire = entireSiteBox();
        if (!entire) {
            return;
        }
        const sections = sectionBoxes();
        const anySection = sections.some((box) => box.checked);
        if (changed !== entire) {
            entire.checked = !anySection;
        } else if (entire.checked) {
            sections.forEach((box) => {
                box.checked = false;
            });
        } else if (!anySection) {
            // nothing would be searched; the whole site is the only default
            entire.checked = true;
        }
    };

    const toggleDocumentsOnly = () => {
        const checked = sectionBoxes().filter((box) => box.checked);
        const active = checked.length === 1 && checked[0].value === "documents";
        for (const group of document.querySelectorAll("[data-hsg-documents-only]")) {
            group.disabled = !active;
            group.hidden = !active && group.dataset.hsgDocumentsOnly === "hide";
        }
    };

    document.addEventListener("change", ({ target }) => {
        if (target.matches('input[type="checkbox"][name="within"], input[data-hsg-entire-site]')) {
            keepExclusive(target);
            toggleDocumentsOnly();
        }
    });
    // capture phase: runs before the submit is serialized, for whichever form
    // the filter belongs to (the sidebar joins its form by @form)
    document.addEventListener("submit", combine, true);
}
