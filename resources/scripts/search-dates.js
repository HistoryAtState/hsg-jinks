// Date filter of the search landing page and the results sidebar (OP#1432).
//
// modules/templates/search.xqm renders the filter as separate month/day/year
// and hour/minute/am-pm parts (reference parity with hsg-shell), without
// names, plus hidden start-date/end-date/start-time/end-time fields that carry
// the actual query parameters. This script
//
// - shows the filter only while "Historical Documents" is the only ticked
//   section, and disables it otherwise so none of it is submitted;
// - on submit, combines the parts into the hidden fields: a year alone gives
//   "1941", a month and year "1941-12", a full date "1941-12-07"; an hour
//   (with optional minute) gives a 24-hour "HH:MM".
(function () {
    function value(scope, part) {
        var el = scope.querySelector('[data-part="' + part + '"]');
        return el ? el.value.trim() : "";
    }

    function pad(number, width) {
        return String(number).padStart(width, "0");
    }

    function digits(text) {
        return /^\d+$/.test(text) ? parseInt(text, 10) : NaN;
    }

    function combineDate(scope) {
        var year = digits(value(scope, "year"));
        if (isNaN(year)) {
            return "";
        }
        var date = pad(year, 4);
        var month = digits(value(scope, "month"));
        if (month >= 1 && month <= 12) {
            date += "-" + pad(month, 2);
            var day = digits(value(scope, "day"));
            if (day >= 1 && day <= 31) {
                date += "-" + pad(day, 2);
            }
        }
        return date;
    }

    function combineTime(scope) {
        var hour = digits(value(scope, "hour"));
        if (!(hour >= 1 && hour <= 12)) {
            return "";
        }
        var minute = digits(value(scope, "minute"));
        if (!(minute >= 0 && minute <= 59)) {
            minute = 0;
        }
        // 12 am is midnight (00), 12 pm is noon (12)
        var pm = value(scope, "period") === "pm";
        var hour24 = (hour % 12) + (pm ? 12 : 0);
        return pad(hour24, 2) + ":" + pad(minute, 2);
    }

    function combine() {
        document.querySelectorAll("[data-date-prefix]").forEach(function (scope) {
            var prefix = scope.getAttribute("data-date-prefix");
            var date = document.getElementById(prefix + "-date");
            var time = document.getElementById(prefix + "-time");
            if (date) {
                date.value = combineDate(scope);
            }
            if (time) {
                // a time only narrows a full date (YYYY-MM-DD); with a year or
                // a month alone it has no meaning
                time.value = date && /^\d{4}-\d{2}-\d{2}$/.test(date.value) ? combineTime(scope) : "";
            }
            // leave empty fields out of the URL; recomputed on every submit
            [date, time].forEach(function (field) {
                if (field) {
                    field.disabled = !field.value;
                }
            });
        });
    }

    function sectionBoxes() {
        return Array.prototype.slice.call(document.querySelectorAll('input[type="checkbox"][name="within"]'));
    }

    function toggle() {
        var checked = sectionBoxes().filter(function (box) { return box.checked; });
        var active = checked.length === 1 && checked[0].value === "documents";
        document.querySelectorAll("[data-hsg-date-filter]").forEach(function (filter) {
            filter.hidden = !active;
            filter.disabled = !active;
        });
    }

    sectionBoxes().forEach(function (box) {
        box.addEventListener("change", toggle);
    });
    // capture phase: runs before the submit is serialized, for whichever form
    // the filter belongs to (the results sidebar joins its form by @form)
    document.addEventListener("submit", combine, true);
})();
