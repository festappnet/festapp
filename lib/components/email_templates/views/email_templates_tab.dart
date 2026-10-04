import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:fstapp/components/email_templates/db_email_templates.dart';
import 'package:fstapp/components/email_templates/views/email_template_card.dart';

import '../../../theme_config.dart';
import '../email_templates_strings.dart';
import 'email_templates_settings_page.dart';
import 'email_banner_settings_card.dart';

class EmailTemplatesTab extends StatefulWidget {
  final int? unitId;
  const EmailTemplatesTab({super.key, this.unitId});

  @override
  _EmailTemplatesTabState createState() => _EmailTemplatesTabState();
}

class _EmailTemplatesTabState extends State<EmailTemplatesTab> {
  EmailTemplatesResponse? emailTemplatesResponse;
  List<EmailTemplateModel> _templates = [];
  String? occasionLink;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.unitId == null &&
        occasionLink == null &&
        context.routeData.inheritedPathParams.isNotEmpty) {
      occasionLink = context.routeData.inheritedPathParams
          .get(AppRouter.linkFormatted, null);
    }
    loadData();
  }

  Future<void> loadData() async {
    if (widget.unitId != null) {
      emailTemplatesResponse = await DbEmailTemplates.getEntityEmailTemplates(
          unitId: widget.unitId!);
    } else if (occasionLink != null) {
      emailTemplatesResponse =
          await DbEmailTemplates.getAllEmailTemplatesViaOccasionLink(
              occasionLink!);
    }

    if (emailTemplatesResponse != null) {
      _templates = emailTemplatesResponse!.templates;
    }
    setState(() {});
  }

  Future<void> _handleEdit(EmailTemplateModel template) async {
    await showDialog(
      context: context,
      builder: (context) => EmailTemplateSettingsPage(
        template: template,
        emailTemplatesResponse: emailTemplatesResponse!,
      ),
    );
    await loadData();
  }

  /// Determines the meta title based on the individual template's values.
  String _getMetaTitle(EmailTemplateModel template) {
    if (template.occasion != null && emailTemplatesResponse?.occasion != null) {
      return emailTemplatesResponse!.occasion!.title ?? '';
    } else if (template.unit != null) {
      return emailTemplatesResponse!.unit.title ?? '';
    } else if (template.organization != null) {
      return emailTemplatesResponse!.organization.title ?? '';
    } else {
      return CommonStrings.defaultLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth >= 900;

          if (isDesktop) {
            // Desktop Layout (Sidebar)
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildMainContent(isMobile: false),
                ),
                if (emailTemplatesResponse != null)
                  Container(
                    width: 350,
                    decoration: BoxDecoration(
                      border: Border(
                          left:
                              BorderSide(color: ThemeConfig.grey300(context))),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(16.0),
                      children: [
                        EmailBannerSettingsCard(
                            response: emailTemplatesResponse!),
                      ],
                    ),
                  ),
              ],
            );
          } else {
            // Mobile Layout (Single Column)
            return _buildMainContent(isMobile: true);
          }
        },
      ),
    );
  }

  Widget _buildMainContent({required bool isMobile}) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    EmailTemplatesStrings.title,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  if (isMobile && emailTemplatesResponse != null) ...[
                    const SizedBox(height: 16),
                    EmailBannerSettingsCard(response: emailTemplatesResponse!),
                  ]
                ],
              ),
            ),
          ),
          SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 250,
              mainAxisExtent: 150,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 250 / 150,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final template = _templates[index];
                final metaTitle = _getMetaTitle(template);
                return EmailTemplateCard(
                  template: template,
                  onEdit: () => _handleEdit(template),
                  contextTitle: metaTitle,
                );
              },
              childCount: _templates.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 64)),
        ],
      ),
    );
  }
}
