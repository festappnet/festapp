# Form builder and finished form

Environment parameters: CAPTURE_LOCALE=cs (future en), CAPTURE_OUTPUT,
CAPTURE_BROWSER_WRAPPER, PRODUCT_DEMO_SKILL. Use capture.py and encode.py.
All fields are created through the actual application; only local fixtures change.

Start occasion6 / form7 (`d45ajbtj`) with its contact email, ticket selector and
Večeře field. Before a retake delete just the three demonstration fields below
through the builder and Save. Preserve blueprint3, ticket products and style.
Desktop viewport1440x1000; local app locale is flutter.locale, public web locale
is locale. Both must equal CAPTURE_LOCALE before opening the form.

1. Add field (`Přidat pole`) > Text. Click the new card and replace its title with
   `Poznámka pro pořadatele`. Keep it optional. The filmed new-card center was
   (600,788); recompute from the current screenshot if the form layout changes.
2. Add field > `Jedna možnost`. Name it `Jak jste se o plese dozvěděli?`.
   Add `Od přátel` and `Ze sociálních sítí` through `Zadejte možnost` and its real
   + button. The title textbox can have a composite accessibility label; inspect
   the current tree and use fresh refs. Do not assume Enter alone commits: fill,
   Tab to the plus button, Enter, then verify both rendered choices.
3. Add field > `Více možností`. Name it `Podmínky účasti`. Add one choice
   `Souhlasím s podmínkami`. Click its real `Povinné` checkbox and verify checked.
4. Save and wait for `Uloženo: d45ajbtj`. Open the actual public form on the local
   web client. Verify all3 saved fields,2 radio choices and the required asterisk.
   The current fixture's public form theme is dark; it remains actual saved style.
5. Final-form chapter: type `Těšíme se na společný večer.` in the note, select
   a real radio option and check consent. Hold the result at least1.6s. Do not
   proceed to checkout or claim a completed order. Record this separately at
   430x900 for the real narrow final-form clip, scrolling the note into view.

For English use genuine app translations plus these fixture values: Note for
organizers; How did you hear about the ball?; From friends; Social media;
Participation terms; I agree to the terms; Looking forward to the evening.
Keep timing/crop cues independent of locale; remeasure controls after translation.

Current source mapping (outside Git, capture-czech-admin):
- form-build-cs-1792669322: text/select/checkbox/required gestures, named cues.
- form-select-options-cs-1792669427: actual secondoption addition.
- form-result-light-cs-1792669613: persisted public result (form design remains dark).
- form-public-fill-cs-1792669738: actual final-form input desktop.
- form-public-mobile-cs: separate narrow final-form input; see directory manifest.

`assemble_form.py CAPTURE_OUTPUT` stitches the fixed current cue map into21.7s
short chapters. Update its directory/cue map to a fresh take after rerecording;
no absolute workstation paths are embedded. `encode.py` accepts --start/--end
and --filter for language-specific cut lengths. All frames retain real cadence.
Keep untrimmed raw frames/cues for a later longer tutorial; no longer cut is
created in this task. Desktop authoring crop1200x760, focused mobile authoring
crop720x900. Final public-form mobile is genuine responsive browser capture.
