# Blueprint distributions

Festapp resolves the published Dart packages `venue_seat_picker` and
`venue_layout_core` through `pubspec.yaml` and `pubspec.lock`. The canonical
source for both packages and the corresponding npm build is
[festappnet/venue_seat_picker](https://github.com/festappnet/venue_seat_picker).

`manifest.json` and `archive-result.json` record the source and archive
verification for the npm release selected by `web_client/pnpm-lock.yaml` and
the paired Dart archives produced by the release gate. Pub.dev uses its own
archive checksums, recorded in `pubspec.lock`.

To import a verified npm archive and its receipt, run
`automation/blueprint_vendor_artifacts.py` with the upstream archive gate
output directory. Update the npm selection and lockfile together.
