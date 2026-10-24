# Branded object-palette crop

Run `python3 automation/landing_capture/layout/encode_brand.py TAKE --output-dir OUTPUT` after capture is explicitly stopped. Current source: external review `layout-brand/layout-build-cs-1792679468`. Source frames are actual Czech app pixels with Futura and the configured brand. Both palette and canvas originate from the same frame; no substitute objects or controls are drawn.

Palette: x0,y410,w232,h510, object grid only. Place at20,157. Canvas: x338,y168,w715,h715 scaled800x800 and placed320,12. Plain composition background#ebf1f6. Desktop1140x824; mobile820x824 proportionally scales/pads the same composition. Search, templates, headers, inspectors and plus controls are excluded in every cue. Actual automatic chair growth remains visible on canvas. Native pointer pixels are retained within the two source crops.

All eight action cues retain their recorded timing, except copy-growth compressed8x and empty-hall limited to its final1s. The final actual scene has18tables and112chairs. For a longer tutorial use the original uncompressed raw take; locale changes require real app recapture. Encoder writes source timestamps/crops/speed in brand-edit.json and does not publish automatically.

Current output30.500s. Encoder dimension/duration checks and full decode passed for both exports. First-table, copied-hall and final frames were visually inspected; four canonical media assets were then copied. Other media and clips.json remain coordinator-owned.
