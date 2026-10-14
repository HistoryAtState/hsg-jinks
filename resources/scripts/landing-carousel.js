// Latest News carousel on the landing page (modules/templates/hsg-landing.xqm).
//
// The slides are a horizontally scrolling, scroll-snapping list, so swiping and
// keyboard scrolling work without this script. It adds the arrow buttons (one
// slide per click), the dots (one per slide, the first fully visible slide is
// current) and hides both while every slide fits on screen.
//
// A classic script at the end of <body> (base10's script.custom); the block
// keeps its bindings out of the shared global scope.
"use strict";

{
    for (const carousel of document.querySelectorAll(".hsg-carousel")) {
        const track = carousel.querySelector(".hsg-carousel__slides");
        const slides = [...track.querySelectorAll(".hsg-carousel__slide")];
        const prev = carousel.querySelector(".hsg-carousel__prev");
        const next = carousel.querySelector(".hsg-carousel__next");
        const dots = [...carousel.querySelectorAll(".hsg-carousel__dot")];

        const offsetOf = (slide) => slide.offsetLeft - slides[0].offsetLeft;

        /** Index of the slide closest to the track's left edge. */
        const currentIndex = () => {
            let best = 0;
            slides.forEach((slide, i) => {
                if (Math.abs(offsetOf(slide) - track.scrollLeft) < Math.abs(offsetOf(slides[best]) - track.scrollLeft)) {
                    best = i;
                }
            });
            return best;
        };

        const goTo = (index) => {
            const target = slides[Math.max(0, Math.min(index, slides.length - 1))];
            track.scrollTo({ left: offsetOf(target), behavior: "smooth" });
        };

        const update = () => {
            const scrollable = track.scrollWidth - track.clientWidth > 1;
            carousel.classList.toggle("hsg-carousel--static", !scrollable);
            const atStart = track.scrollLeft <= 1;
            const atEnd = track.scrollLeft >= track.scrollWidth - track.clientWidth - 1;
            prev.disabled = atStart;
            next.disabled = atEnd;
            // At the end of the track the last slides can't reach the left edge;
            // mark the last dot then, so the final dot is reachable.
            const current = atEnd ? slides.length - 1 : currentIndex();
            dots.forEach((dot, i) => {
                if (i === current) {
                    dot.setAttribute("aria-current", "true");
                } else {
                    dot.removeAttribute("aria-current");
                }
            });
        };

        prev.addEventListener("click", () => goTo(currentIndex() - 1));
        next.addEventListener("click", () => goTo(currentIndex() + 1));
        dots.forEach((dot, i) => dot.addEventListener("click", () => goTo(i)));
        track.addEventListener("scroll", update, { passive: true });
        // Slide widths settle after images and web fonts load, without the
        // track itself changing size: watch the slides as well.
        const resizes = new ResizeObserver(update);
        resizes.observe(track);
        slides.forEach((slide) => resizes.observe(slide));
        window.addEventListener("load", update);
        update();
    }
}
