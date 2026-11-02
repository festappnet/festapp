# Divider cursor browser verification - 2026-11-02

On the original local build `57389512749180927bfde5341a7aa11784ca8eae508255d050635e6c2149b051`, a 1280x900 headless viewport at DPR 1 and visual scale 1 showed the divider at x679; the body resize cursor spanned x656-703. The grid header also has a separate column resize cursor further left.

On the final build `cc9d9e16e59257cdf2b11abfe04617abe0edb1fe246714687bac5ced21120caa`, the divider stayed at x679 while the resize cursor spanned x668-691 at y160, 600 and 880, with normal cursor outside. Dragging the divider right near the top and left near the bottom moved it both ways and restored its original width. See `divider-tight-final.png`. No database writes; isolated browser closed and local services left running.
