(function () {
    function combine(prefix) {
        var month = document.getElementById(prefix + "-month").value.trim();
        var day = document.getElementById(prefix + "-day").value.trim();
        var year = document.getElementById(prefix + "-year").value.trim();
        var hidden = document.getElementById(prefix);
        hidden.value = (year && month && day) ? (year + "-" + month.padStart(2, "0") + "-" + day.padStart(2, "0")) : "";
    }

    var form = document.querySelector("form.usa-form");
    if (form) {
        form.addEventListener("submit", function () {
            combine("start-date");
            combine("end-date");
        });
    }
})();
