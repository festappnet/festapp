import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'imported_images.dart';

// Match Festapp's HtmlView: embedded images use bytes; remote images use the
// stable web byte loader instead of the editor's default network image widget.
class EditorImageComponentBuilder extends ImageComponentBuilder {
  const EditorImageComponentBuilder();

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    if (viewModel is! ImageComponentViewModel) return null;
    return ImageComponent(
      componentKey: context.componentKey,
      imageUrl: viewModel.imageUrl,
      expectedSize: viewModel.expectedSize,
      selection:
          viewModel.selection?.nodeSelection
              as UpstreamDownstreamNodeSelection?,
      selectionColor: viewModel.selectionColor,
      opacity: viewModel.opacity,
      imageBuilder: (_, source) {
        if (source.startsWith('data:image/')) {
          return Image.memory(
            UriData.parse(source).contentAsBytes(),
            fit: BoxFit.contain,
          );
        }
        return CachedNetworkImage(
          imageUrl: localImageSource(source),
          imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) => const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Obrázek se nepodařilo načíst. Zkontroluj dostupnost URL a CORS.',
            ),
          ),
        );
      },
    );
  }
}
