import 'package:fstapp/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DemoOccasion {
  final int id;
  final String link, title, key, description, version;
  final String? image;
  const DemoOccasion(
      {required this.id,
      required this.link,
      required this.title,
      required this.key,
      required this.description,
      required this.version,
      this.image});

  factory DemoOccasion.fromJson(Map<String, dynamic> json) => DemoOccasion(
      id: (json['id'] as num).toInt(),
      link: json['link'] as String,
      title: json['title'] as String,
      key: json['demoKey'] as String,
      description: json['description'] as String,
      version: json['fixtureVersion'] as String,
      image: json['image'] as String?);
}

class DemoCatalog {
  final bool hasOwnWork;
  final List<DemoOccasion> items;
  const DemoCatalog({required this.hasOwnWork, required this.items});

  factory DemoCatalog.fromJson(Map<String, dynamic> json) => DemoCatalog(
      hasOwnWork: json['hasOwnWork'] == true,
      items: (json['items'] as List)
          .map((item) =>
              DemoOccasion.fromJson((item as Map).cast<String, dynamic>()))
          .toList());

  static Future<DemoCatalog> load() async {
    final data = await Supabase.instance.client.rpc('get_demo_occasions',
        params: {'p_organization': AppConfig.organization});
    return DemoCatalog.fromJson((data as Map).cast<String, dynamic>());
  }
}
