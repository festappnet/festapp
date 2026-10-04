import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/views/products_tab.dart';

@RoutePage()
class ProductsSectionPage extends StatelessWidget {
  const ProductsSectionPage({super.key});
  @override
  Widget build(BuildContext context) => ProductsTab();
}
