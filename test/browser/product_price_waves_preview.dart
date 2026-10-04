// Isolated visual fixture of the real widgets. No backend or production writes.
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/services/web_bootstrap_bridge.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/eshop/models/product_edit_bundle.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/product_price_change.dart';
import 'package:fstapp/components/eshop/models/product_price_wave.dart';
import 'package:fstapp/components/eshop/views/product_price_waves_dialog.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized().ensureSemantics();
  await EasyLocalization.ensureInitialized();
  final first=DateTime(2026,10,15,18).toUtc();final second=DateTime(2026,11,1,12).toUtc();
  final products=[
    ProductModel(id:1,title:'Vstupenka Standard',price:450,currencyCode:'CZK',priceChanges:[
      ProductPriceChange(id:1,revision:1,price:550,time:first),ProductPriceChange(id:2,revision:1,price:650,time:second)]),
    ProductModel(id:2,title:'Vstupenka VIP',price:900,currencyCode:'CZK',priceChanges:[
      ProductPriceChange(id:3,revision:1,price:1100,time:first)]),
    ProductModel(id:3,title:'Early bird',price:350,currencyCode:'CZK',visibilityChanges:[
      ProductVisibilityChange(id:4,revision:1,time:first,hidden:true)])];
  final bundle=ProductsEditBundle(products:products,productTypes:[],inventoryPools:[],inventoryContexts:[],forms:[],
    priceWaves:[ProductPriceWave(id:1,time:first),ProductPriceWave(id:2,time:second)]);
  runApp(EasyLocalization(supportedLocales:const [Locale('cs')],startLocale:const Locale('cs'),path:'assets/translations',
    child:Builder(builder:(context)=>MaterialApp(theme:ThemeConfig.theme(),locale:context.locale,
      supportedLocales:context.supportedLocales,localizationsDelegates:context.localizationDelegates,
      home:ProductPriceWavesDialog(occasionLink:'preview',initialBundle:bundle,canEdit:true,loader:() async=>bundle)))));
  WidgetsBinding.instance.addPostFrameCallback((_)=>WebBootstrapBridge.markAppReady());
}
