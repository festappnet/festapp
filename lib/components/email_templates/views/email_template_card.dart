import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:fstapp/components/email_templates/email_templates_strings.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class EmailTemplateCard extends StatelessWidget {
  final EmailTemplateModel template;
  final VoidCallback onEdit;

  /// Additional field to show the context title (occasion/unit/organization).
  final String contextTitle;

  const EmailTemplateCard({
    super.key,
    required this.template,
    required this.onEdit,
    required this.contextTitle,
  });

  @override
  Widget build(BuildContext context) {
    // Fixed header height for the upper part.
    const double headerHeight = 10;
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, minHeight: 120),
      child: Material(
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Upper fixed-height header with primary color.
            Container(
              height: headerHeight,
              color: theme.primaryColor,
            ),
            // Bottom area that expands to fill the available space.
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 2.0),
                decoration: BoxDecoration(
                  // Use primary color with transparency for a light overlay.
                  color: theme.primaryColor.withOpacityUniversal(context, 0.1),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10.0),
                    bottomRight: Radius.circular(10.0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Meta title in italic with reduced opacity and overflow handling.
                    Text(
                      "${EmailTemplatesStrings.template} - ${contextTitle.isNotEmpty ? contextTitle : CommonStrings.defaultLabel}",
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: ThemeConfig.blackColor(context).withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Template title with overflow handling.
                    Text(
                      template.getUsageDetails()['title'] ?? '',
                      style: TextStyle(
                        color: ThemeConfig.blackColor(context),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Usage description with overflow handling.
                    Text(
                      template.getUsageDetails()['description'] ?? '',
                      style: TextStyle(
                        color: ThemeConfig.blackColor(context),
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Align the edit button to the right.
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: onEdit,
                        icon: Icon(
                          Icons.edit,
                          color: ThemeConfig.blackColor(context),
                        ),
                        label: Text(
                          CommonStrings.edit,
                          style: TextStyle(
                            color: ThemeConfig.blackColor(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
