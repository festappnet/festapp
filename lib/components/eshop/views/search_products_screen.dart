import 'dart:async';
import 'package:flutter/material.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class SearchProductsScreen extends StatefulWidget {
  final int ticketId;
  final List<ProductModel> alreadySelected;
  const SearchProductsScreen({
    super.key,
    required this.ticketId,
    required this.alreadySelected,
  });

  @override
  _SearchProductsScreenState createState() => _SearchProductsScreenState();
}

class _SearchProductsScreenState extends State<SearchProductsScreen> {
  List<ProductModel> _all = [], _filt = [];
  Set<int> _sel = {};
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _sel = widget.alreadySelected.map((p) => p.id!).toSet();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list =
        await DbEshop.getProductsForTicketAllAvailable(widget.ticketId) ?? [];
    _all = list;
    _filt = list;
    setState(() => _loading = false);
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final normalizedQuery = Utilities.removeDiacritics(q.toLowerCase());
      setState(() {
        _filt = _all.where((p) {
          final normalizedTitle =
              Utilities.removeDiacritics(p.title?.toLowerCase() ?? "");
          final normalizedType = Utilities.removeDiacritics(
              p.productTypeTitleString?.toLowerCase() ?? "");
          final inPrice = p.price?.toString().contains(normalizedQuery) ??
              false; // Price conversion is tricky for diacritics, keeping original logic here.

          return normalizedTitle.contains(normalizedQuery) ||
              normalizedType.contains(normalizedQuery) ||
              inPrice;
        }).toList();
      });
    });
  }

  void _toggle(int id) {
    setState(() {
      if (_sel.contains(id)) {
        _sel.remove(id);
      } else {
        _sel.add(id);
      }
    });
  }

  void _confirm() {
    final picked = _all.where((p) => _sel.contains(p.id)).toList();
    final newOnes = picked
        .where((p) => !widget.alreadySelected.any((o) => o.id == p.id))
        .toList();
    Navigator.of(context).pop(newOnes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(CommonStrings.products),
        actions: [
          TextButton(
            onPressed: _confirm,
            child: Text(CommonStrings.confirm,
                style: const TextStyle(color: Colors.white)),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                labelText: CommonStrings.search,
                hintText: OrdersStrings.searchProductsHint,
                prefixIcon: const Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filt.isEmpty
                    ? Center(child: Text(OrdersStrings.noProductsFound))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _filt.length,
                        separatorBuilder: (_, __) => const Divider(height: 0),
                        itemBuilder: (_, i) {
                          final p = _filt[i];
                          return CheckboxListTile(
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _sel.contains(p.id),
                            onChanged: (_) => _toggle(p.id!),
                            title: Text(p.title ?? ""),
                            subtitle: Text(p.productTypeTitleString ?? ""),
                            secondary: Text(
                              Utilities.formatPrice(context, p.price ?? 0,
                                  decimalDigits: 2),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
