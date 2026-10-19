/// Existing group-seat lettering: A..Z, AA..AZ, BA..; the index is zero based.
String blueprintSeatTitle(String groupTitle, int index) {
  if (index < 0) throw ArgumentError.value(index, 'index');
  var letters = '';
  while (index >= 0) {
    letters = String.fromCharCode(65 + index % 26) + letters;
    index = (index ~/ 26) - 1;
  }
  return '$groupTitle$letters';
}
