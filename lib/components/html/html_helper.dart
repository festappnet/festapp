import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/components/images/db_images.dart';
import 'package:fstapp/components/images/image_compression_helper.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:html/dom.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/platform_helper.dart';

class HtmlHelper {
  static const int jpegThreshold = 1200;
  static const int pngThreshold = 1000;
  static int maxImageSize = (0.5 * 1024 * 1024) as int;

  static const String jpegBase64Prefix = 'data:image/jpeg;base64,';
  static const String pngBase64Prefix = 'data:image/png;base64,';

  static List<String> detectImagesToProcess(String htmlText) {
    final document = html_parser.parse(htmlText);
    final images = document.getElementsByTagName('img');
    List<String> imagesToProcess = [];

    for (var image in images) {
      String? src = image.attributes['src'];
      if (src != null &&
          (src.startsWith(jpegBase64Prefix) ||
              src.startsWith(pngBase64Prefix))) {
        String base64Data = src.contains(jpegBase64Prefix)
            ? src.replaceFirst(jpegBase64Prefix, '')
            : src.replaceFirst(pngBase64Prefix, '');

        // Calculate the approximate size of the base64 data in bytes
        int base64Length = base64Data.length;
        int imageSizeInBytes =
            (base64Length * 3) ~/ 4; // ~75% of base64 string length

        if (imageSizeInBytes > maxImageSize) {
          Uint8List imageData = base64.decode(base64Data);

          if (src.startsWith(jpegBase64Prefix)) {
            img.Image? originalImage = img.decodeImage(imageData);
            if (originalImage != null && originalImage.width > 1200) {
              imagesToProcess.add(src);
            }
          } else if (src.startsWith(pngBase64Prefix)) {
            img.Image? originalImage = img.decodeImage(imageData);
            if (originalImage != null && originalImage.width > 1000) {
              imagesToProcess.add(src);
            }
          }
        }
      }
    }
    return imagesToProcess;
  }

  static String applyEmailCompatibleStyleToImages(String htmlText) {
    final document = html_parser.parse(htmlText);
    final images = document.getElementsByTagName('img');

    for (var image in images) {
      image.attributes['style'] = 'width: 100%; height: auto;';
    }

    return document.outerHtml;
  }

  static Future<String> compressImage(String htmlText, String imageSrc,
      void Function() onImageProcessed) async {
    final document = html_parser.parse(htmlText);
    final image = document.querySelector('img[src="$imageSrc"]');

    if (image != null) {
      String base64Data = imageSrc.contains(jpegBase64Prefix)
          ? imageSrc.replaceFirst(jpegBase64Prefix, '')
          : imageSrc.replaceFirst(pngBase64Prefix, '');

      Uint8List imageData = base64.decode(base64Data);

      Uint8List compressedData;

      if (imageSrc.startsWith(jpegBase64Prefix)) {
        compressedData =
            await ImageCompressionHelper.compressJpeg(imageData, jpegThreshold);
        String compressedBase64 = base64.encode(compressedData);
        image.attributes['src'] = '$jpegBase64Prefix$compressedBase64';
      } else if (imageSrc.startsWith(pngBase64Prefix)) {
        img.Image? originalImage = img.decodeImage(imageData);
        if (originalImage != null) {
          compressedData =
              await ImageCompressionHelper.compressPng(imageData, pngThreshold);
          String compressedBase64 = base64.encode(compressedData);
          image.attributes['src'] = '$pngBase64Prefix$compressedBase64';
        }
      }

      // Call the callback to update the processed count in the main widget
      onImageProcessed();
    }

    return document.outerHtml;
  }

  static String removeColor(String htmlText) {
    RegExp regExp = RegExp(r'(background-color|color)\s*:\s*[^;]+;?\s*',
        caseSensitive: false);
    String cleanedHtmlString = htmlText.replaceAll(regExp, '');
    return cleanedHtmlString;
  }

  static String detectAndReplaceLinks(String htmlText) {
    final emailRegex =
        RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b');
    final urlRegex = RegExp(r'\b((http|https)://|www\.)[^\s/$.?#].\S*',
        caseSensitive: false);

    // Updated phoneRegex to ensure there must be spaces or other separators between digit groups
    final phoneRegex = RegExp(
        r'\b(\+?[0-9]{1,4}[-.\s]+)?(\(?\d{2,3}\)?[-.\s]+)?\d{3}[-.\s]+\d{3}[-.\s]+\d{3,4}\b');

    final document = html_parser.parse(htmlText);

    // Function to add anchor tags for matches
    void addAnchorTag(Node node, Match match, String hrefPrefix) {
      final textContent = node.text!;
      final newNodes = <Node>[];
      var lastIndex = 0;

      if (match.start > lastIndex) {
        newNodes.add(Text(textContent.substring(lastIndex, match.start)));
      }

      var matchedText = match.group(0)!;
      var hrefValue = matchedText;

      if (hrefPrefix.isEmpty && matchedText.startsWith('www.')) {
        hrefValue = 'https://$matchedText'; // Add https:// to href only
      }

      final anchor = Element.tag('a')
        ..attributes['href'] = '$hrefPrefix$hrefValue'
        ..text = matchedText; // Keep the original text
      newNodes.add(anchor);

      lastIndex = match.end;

      if (lastIndex < textContent.length) {
        newNodes.add(Text(textContent.substring(lastIndex)));
      }

      // Replace the old text node with new nodes
      node.replaceWith(DocumentFragment()..nodes.addAll(newNodes));
    }

    // Process emails
    for (var element in document.body!.querySelectorAll('*')) {
      if (element.localName == 'a') continue;

      element.nodes.whereType<Text>().toList().forEach((node) {
        final textContent = node.text;
        textContent.replaceAllMapped(emailRegex, (match) {
          addAnchorTag(node, match, 'mailto:');
          return '';
        });
      });
    }

    // Process URLs
    for (var element in document.body!.querySelectorAll('*')) {
      if (element.localName == 'a') continue; // Skip existing <a> tags

      element.nodes.whereType<Text>().toList().forEach((node) {
        final textContent = node.text;
        textContent.replaceAllMapped(urlRegex, (match) {
          addAnchorTag(node, match, '');
          return '';
        });
      });
    }

    // Process phone numbers
    for (var element in document.body!.querySelectorAll('*')) {
      if (element.localName == 'a') continue; // Skip existing <a> tags

      element.nodes.whereType<Text>().toList().forEach((node) {
        final textContent = node.text;
        textContent.replaceAllMapped(phoneRegex, (match) {
          addAnchorTag(node, match, 'tel:');
          return '';
        });
      });
    }

    return document.body!.innerHtml;
  }

  static String stripHtml(String htmlText) {
    return htmlText.replaceAll(
        RegExp(r'<(?!img\b)[^>]*>', caseSensitive: false), '');
  }

  /// Converts an HTML fragment to a single-line, plain-text snippet suitable
  /// for list subtitles: decodes entities, drops every tag (tolerating
  /// truncated or malformed markup such as a dangling "<" left by a naive
  /// substring), and collapses runs of whitespace to single spaces.
  static String htmlToPlainText(String htmlText) {
    final document = html_parser.parse(htmlText);
    final text = document.body?.text ?? '';
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Plain-text snippet for list subtitles: strips markup (via
  /// [htmlToPlainText]) and, when the text is longer than [maxLen], truncates
  /// at a word boundary and appends an ellipsis. Text at or under the limit is
  /// returned unchanged, so short snippets never get a dangling "…".
  static String htmlToSnippet(String? htmlText, {int maxLen = 160}) {
    if (htmlText == null || htmlText.isEmpty) return '';
    final text = htmlToPlainText(htmlText);
    if (text.length <= maxLen) return text;
    var cut = text.substring(0, maxLen);
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace > maxLen ~/ 2) cut = cut.substring(0, lastSpace);
    return '${cut.trimRight()}…';
  }

  static bool isHtmlEmptyOrNull(String? htmlText) {
    if (htmlText == null) {
      return true;
    }

    return htmlText
        .replaceAll(RegExp(r'<(?!img\b)[^>]*>', caseSensitive: false), '')
        .trim()
        .isEmpty;
  }

  /// Returns true if the HTML content is “long” (text length exceeds threshold)
  /// or contains at least one <img> tag, indicating it should be shown in a popup.
  static bool isHtmlLong(String? htmlText, {int lengthThreshold = 500}) {
    if (htmlText == null) {
      return false;
    }
    // Quick check for any <img> tags
    if (RegExp(r'<img\b[^>]*>', caseSensitive: false).hasMatch(htmlText)) {
      return true;
    }

    // Strip tags and count plain text length
    final document = html_parser.parse(htmlText);
    final plainText = document.body?.text.trim() ?? '';
    return plainText.length > lengthThreshold;
  }

  static String htmlTrim(String htmlText) {
    // Remove leading <p> and <br> tags
    String result = htmlText.replaceAll(
      RegExp(r'^(?:\s*(?:<p\b[^>]*>|\s*<br\s*/?>))*', caseSensitive: false),
      '',
    );
    // Remove trailing <p>, </p> and <br> tags
    result = result.replaceAll(
      RegExp(r'(?:<\/?p\b[^>]*>|\s*<br\s*\/?>\s*)*$', caseSensitive: false),
      '',
    );
    return result;
  }

  static Future<String> storeImagesToOccasion(
      String oldHtml, String newHtml, int occasionId) async {
    // Parse the old and new HTML documents.
    final oldDocument = html_parser.parse(oldHtml);
    final newDocument = html_parser.parse(newHtml);

    // Collect image src values from the old HTML.
    oldDocument
        .getElementsByTagName('img')
        .map((img) => img.attributes['src'] ?? '')
        .where((src) =>
            src.isNotEmpty &&
            !(src.startsWith(jpegBase64Prefix) ||
                src.startsWith(pngBase64Prefix)))
        .toList();

    // Process each image in the new HTML.
    List<Element> newImages = newDocument.getElementsByTagName('img');
    for (var image in newImages) {
      String? src = image.attributes['src'];
      if (src == null || src.isEmpty) continue;

      bool isBase64 =
          src.startsWith(jpegBase64Prefix) || src.startsWith(pngBase64Prefix);

      // For non-base64 images, check if it has already been uploaded.
      bool alreadyUploaded = false;
      if (!isBase64) {
        alreadyUploaded = await DbImages.isImageUploaded(src, occasionId);
        if (alreadyUploaded) continue;
      }

      Uint8List imageData;
      if (isBase64) {
        // Decode the base64 image data.
        String base64Data = src.contains(jpegBase64Prefix)
            ? src.replaceFirst(jpegBase64Prefix, '')
            : src.replaceFirst(pngBase64Prefix, '');
        imageData = base64.decode(base64Data);
      } else {
        // For linked images, fetch the image data from the URL.
        var fetched = await fetchImageData(src, occasionId);
        if (fetched == null) {
          continue;
        }
        imageData = fetched;
      }

      // Upload raw image to Worker — Cloudflare Images binding handles
      // the single transform (resize + optimize) server-side.
      final publicUrl =
          await DbImages.uploadImage(imageData, occasionId, null);
      // Update the image tag's src attribute.
      image.attributes['src'] = publicUrl;
    }

    return newDocument.outerHtml;
  }

  static Future<Uint8List?> fetchImageData(String src, int occasionId) async {
    if (PlatformHelper.isWeb) {
      final response = await Supabase.instance.client.functions.invoke(
        "fetch-http-data",
        body: {"targetUrl": src, "occasionId": occasionId},
      );
      if (response.data != null && response.data is Map) {
        final mapData = response.data as Map;
        final base64String = mapData["data"];
        if (base64String is String) {
          return base64.decode(base64String);
        } else {
          AppLogger.error("Error: Data is not a string.");
          return null;
        }
      } else {
        AppLogger.error("Error: No data returned from supabase function.");
        return null;
      }
    }

    final client = http.Client();
    try {
      final response = await client.get(Uri.parse(src));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        AppLogger.error('Error fetching image: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      AppLogger.error('Error fetching image: $e');
      return null;
    } finally {
      client.close();
    }
  }
}
