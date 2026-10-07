// The Sort by select belongs to the search form (via its form attribute) but
// sits in the results heading, so a change should re-run the search rather
// than wait for a button press. A classic script at the end of <body>; the
// block keeps its bindings out of the shared global scope.
"use strict";

{
    document.addEventListener("change", ({ target }) => {
        if (target.matches("select[data-submit-on-change]")) {
            target.form?.requestSubmit();
        }
    });
}
