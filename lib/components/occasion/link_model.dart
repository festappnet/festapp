import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/forms/views/form_page.dart';

class LinkModel {
  String? formLink;
  String? occasionLink;
  int? unitId;

  LinkModel({this.occasionLink, this.formLink, this.unitId});

  factory LinkModel.extractOccasionLink(String url) {
    String? firstPart;
    String? secondPart;

    // Sophisticated parsing: handles domain, localhost, ports, and schemes automatically
    final uri = Uri.tryParse(url);

    if (uri != null) {
      // 1. Get path segments (removes domain/scheme).
      // e.g., "https://dom.com/occ/123" -> ["occ", "123"]
      var segments = uri.pathSegments.toList();

      // 2. Legacy Fallback: If path is empty, check fragment (hash)
      // e.g., "https://dom.com/#/occ/123" -> fragment is "/occ/123"
      if (segments.isEmpty && uri.fragment.isNotEmpty) {
        final cleanFragment = uri.fragment.startsWith('/')
            ? uri.fragment.substring(1)
            : uri.fragment;
        segments = cleanFragment.split('/').where((s) => s.isNotEmpty).toList();
      }

      if (segments.isNotEmpty) {
        firstPart = segments[0];

        // Only extract second part if the first part matches the Form Route
        if (firstPart == FormPage.ROUTE && segments.length > 1) {
          secondPart = segments[1];
        }

        // Check against root links
        var rootLinks = AppRouter.getRootLinks();
        if (rootLinks.any((rootLink) => firstPart == rootLink)) {
          firstPart = "";
        }
      }
    }

    return LinkModel(
      occasionLink: firstPart,
      formLink: secondPart,
    );
  }
}
