// The search page's timelines (srch:timeline).
//
// Loading: on pb-components 3.0.0-next-4, pb-timeline's `auto` attribute
// does nothing (pb-fetch, which replaced iron-ajax, doesn't implement it), so
// a timeline only loads its url when it receives pb-results-received on the
// channel it subscribes to. Each timeline subscribes to its own channel and
// this script sends it that event once the element is ready.
//
// Selecting: a date or range picked on a timeline searches again with it as
// the date filter, and resetting the timeline removes the filter. Everything
// else about the search is kept.
(function () {
    async function load(timeline) {
        const channel = timeline.getAttribute("subscribe");
        if (!channel) {
            return;
        }
        await customElements.whenDefined("pb-timeline");
        await timeline.updateComplete;
        document.dispatchEvent(new CustomEvent("pb-results-received", { detail: { key: channel } }));
    }

    function search(startDate, endDate) {
        const url = new URL(window.location.href);
        url.searchParams.delete("start");
        for (const name of ["start-date", "end-date", "start-time", "end-time"]) {
            url.searchParams.delete(name);
        }
        if (startDate) {
            url.searchParams.set("start-date", startDate);
        }
        if (endDate) {
            url.searchParams.set("end-date", endDate);
        }
        window.location.assign(url.toString());
    }

    function start() {
        document.querySelectorAll(".hsg-timeline pb-timeline[subscribe]").forEach(load);
    }

    // A range dragged across bins ends at the start of the bin after the
    // last one (1956-01-01 for bins through 1955), and the search's end date
    // is inclusive, so that day goes back by one.
    function inclusiveEnd(startDate, endDate) {
        if (!endDate || endDate <= startDate || !/-01$/.test(endDate)) {
            return endDate;
        }
        const day = new Date(endDate + "T00:00:00Z");
        day.setUTCDate(day.getUTCDate() - 1);
        return day.toISOString().slice(0, 10);
    }

    document.addEventListener("pb-timeline-daterange-changed", (event) => {
        search(event.detail.startDateStr, inclusiveEnd(event.detail.startDateStr, event.detail.endDateStr));
    });
    document.addEventListener("pb-timeline-date-changed", (event) => {
        if (event.detail.startDateStr) {
            search(event.detail.startDateStr, event.detail.endDateStr);
        }
    });
    document.addEventListener("pb-timeline-reset-selection", () => search(null, null));

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", start);
    } else {
        start();
    }
})();
