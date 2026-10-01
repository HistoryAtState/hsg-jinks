(function () {
    // The Sort by select belongs to the search form (via its form attribute) but
    // sits in the results heading, so a change should re-run the search rather
    // than wait for a button press.
    document.querySelectorAll("select[data-submit-on-change]").forEach(function (select) {
        select.addEventListener("change", function () {
            if (select.form) {
                select.form.requestSubmit();
            }
        });
    });
})();
