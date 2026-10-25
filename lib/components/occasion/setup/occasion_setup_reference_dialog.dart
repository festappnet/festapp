import 'package:material_ui/material_ui.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'occasion_setup_references.dart';
import 'occasion_setup_strings.dart';

class OccasionSetupReferenceDialog extends StatefulWidget {
  const OccasionSetupReferenceDialog(
      {super.key, required this.data, required this.previous});
  final Map<String, dynamic> data, previous;
  @override
  State<OccasionSetupReferenceDialog> createState() =>
      _OccasionSetupReferenceDialogState();
}

class _OccasionSetupReferenceDialogState
    extends State<OccasionSetupReferenceDialog> {
  final products = <int, int>{}, types = <int, int>{};
  @override
  Widget build(BuildContext context) {
    final refs = OccasionSetupReferences(widget.data);
    final old = OccasionSetupReferences(widget.previous);
    final next = refs.rebind(products: products, productTypes: types);
    final issues = OccasionSetupReferences(next);
    return AppAlertDialog(
      title: Text(OccasionSetupStrings.copy('referencesTitle')),
      content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(OccasionSetupStrings.copy('referencesBody')),
              for (final id in refs.missingProducts)
                Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('seat-product-$id'),
                      initialValue: products[id],
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText: OccasionSetupStrings.copyReference(
                              'seatProduct',
                              old.seatProducts[id]?['title'] as String? ??
                                  '#$id')),
                      items: [
                        for (final product in refs.seatProducts.entries)
                          DropdownMenuItem(
                              value: product.key,
                              child: Text(
                                  '${product.value['title']} · ${product.value['price']} ${product.value['currency_code'] ?? ''}',
                                  overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: (value) => setState(() {
                        if (value != null) products[id] = value;
                      }),
                    )),
              for (final id in refs.missingTypes)
                Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('ticket-type-$id'),
                      initialValue: types[id],
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText: OccasionSetupStrings.copyReference(
                              'ticketType',
                              old.types[id]?['title'] as String? ?? '#$id')),
                      items: [
                        for (final type in refs.types.entries)
                          DropdownMenuItem(
                              value: type.key,
                              child: Text(
                                  type.value['title'] as String? ??
                                      '#${type.key}',
                                  overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: (value) => setState(() {
                        if (value != null) types[id] = value;
                      }),
                    )),
              if (issues.duplicateTypes)
                Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(OccasionSetupStrings.copy('duplicateTypes'))),
            ],
          ))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(CommonStrings.back)),
        ElevatedButton(
            onPressed:
                issues.hasIssues ? null : () => Navigator.pop(context, next),
            child: Text(CommonStrings.save)),
      ],
    );
  }
}
