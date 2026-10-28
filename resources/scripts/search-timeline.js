// The search page's timelines (srch:timeline).
//
// Loading: pb-timeline loads its data with an inner iron-ajax, but iron-ajax
// isn't in the pb-components bundle the site loads, so the element never
// sends a request. Each timeline names its data in data-hsg-src instead; this
// script fetches it and hands it to pb-timeline the way its own loader would,
// through the loader's lastResponse and _handleResponse (pb-components
// 3.0.0-next-4.21; a private API, so recheck on upgrade).
//
// Selecting: a date or range picked on a timeline searches again with it as
// the date filter, and resetting the timeline removes the filter. Everything
// else about the search is kept.
(function () {
    async function load(timeline) {
        const src = timeline.dataset.hsgSrc;
        if (!src) {
            return;
        }
        try {
            const response = await fetch(src, { credentials: "same-origin" });
            if (!response.ok) {
                return;
            }
            const data = await response.json();
            await customElements.whenDefined("pb-timeline");
            await timeline.updateComplete;
            const loader = timeline.shadowRoot && timeline.shadowRoot.getElementById("loadData");
            if (loader && typeof timeline._handleResponse === "function") {
                loader.lastResponse = data;
                timeline._handleResponse();
            }
        } catch (e) {
            console.warn("search timeline: could not load", src, e);
        }
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
        document.querySelectorAll("pb-timeline[data-hsg-src]").forEach(load);
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
        // undated ("?") has no date to filter by
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
