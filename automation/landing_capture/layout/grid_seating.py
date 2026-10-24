"""Real two-table grid seating and shared style, starting from fixture=blank.
Locale cs; translate semantic labels for an en retake. No document injection.
"""
from grid_take import *
start('grid-seating');cue('draw-first');ui('Malovat stůl');path_drag([(470,320),(760,320),(760,470),(640,470)]);end();proof('seating-drawn')
fill('[aria-label="Název"]','Stůl 1')
cue('add-chairs')
for _ in range(12):ui('Přidat židli')
end();proof('seating-chairs')
ui('Zrušit výběr');cue('second-table');drag(570,320,570,640,'Control');end();proof('seating-second')
ui('Zrušit výběr');cue('select-both');path_drag([(400,260),(840,850)]);end();proof('seating-selected')
print(ab('snapshot','-i'))

# Recorded supported shared-style continuation: multiselect has no preset cards.
# Clear selection, select first table, Dřevěný, Kopírovat styl; clear, marquee
# both tables and24chairs, Vložit styl. Inspect both table style.material=wood.
# Rehearsal group/ungroup discovery is omitted from the edit.
# Edge take: first table chosen; native arm619332->619382 then619382->619357.
# Encoder preserves drawing/edge timing, accelerates + clicks2x and selection1.5x.
