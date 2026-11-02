# Divider cursor and drag verification - 2026-11-02

Local isolated browser at 1280x900, DPR 1. On prior artifact, the cursor showed `ew-resize` at x661, 18px left of divider x679, but a 1px drag left the line at x679. On final `main.dart.js` SHA-256 `4e680c76cdb59a872bb2f2c6488b59d807b63a341d60329618b1dbc0fe21a6f6`, that same drag moved the line to x680; a 1px drag from 18px right moved it back to x679. At 22px outside either side, the cursor was not resize and 1px drags left the line unchanged.

A drag beginning 18px left continued outside the target and moved the line from x679 to x768. A bottom-area drag returned it to x679. Pixel positions were read from screenshots; `cursor-drag-final.png` shows restored layout. No database writes. Local browser and services remain running for subsequent verification.
