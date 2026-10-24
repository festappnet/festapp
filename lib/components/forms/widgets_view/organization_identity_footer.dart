import 'package:flutter/material.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/verified_organization_identity.dart';
import '../../unit/verification/verification_strings.dart';

class OrganizationIdentityFooter extends StatefulWidget {
  final VerifiedOrganizationIdentity? identity;
  const OrganizationIdentityFooter({super.key, required this.identity});
  @override
  State<OrganizationIdentityFooter> createState() =>
      _OrganizationIdentityFooterState();
}

class _OrganizationIdentityFooterState
    extends State<OrganizationIdentityFooter> {
  DialogRoute<void>? _dialog;
  NavigatorState? _navigator;
  void _closeOwnedDialog() {
    final route = _dialog;
    final navigator = _navigator;
    _dialog = null;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) navigator.removeRoute(route);
      });
    }
  }

  @override
  void didUpdateWidget(OrganizationIdentityFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) _closeOwnedDialog();
  }

  @override
  void dispose() {
    _closeOwnedDialog();
    super.dispose();
  }

  Future<void> _open(VerifiedOrganizationIdentity value) async {
    if (_dialog != null) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
        context: context,
        builder: (_) =>
            _organizationDetailsDialog(value.details, verified: true));
    _navigator = navigator;
    _dialog = route;
    await navigator.push(route);
    if (_dialog == route) _dialog = null;
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.identity;
    if (value == null) return const SizedBox.shrink();
    final words = value.legalName.split(' ');
    final last = words.removeLast();
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 24),
      child: Center(
          child: Semantics(
        label:
            '${VerificationStrings.text('organizer')}: ${value.legalName}, ${VerificationStrings.text('verified')}, ${VerificationStrings.text('showDetails')}',
        button: true,
        onTap: () => _open(value),
        child: ExcludeSemantics(
            child: TextButton(
          style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: Theme.of(context).colorScheme.onSurface),
          onPressed: () => _open(value),
          child: LayoutBuilder(
              builder: (context, constraints) => Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text:
                            "${VerificationStrings.text('organizer')}: ${words.isEmpty ? '' : '${words.join(' ')} '}"),
                    WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: constraints.maxWidth),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Flexible(
                                  child: Text(last,
                                      style: const TextStyle(fontSize: 14))),
                              const SizedBox(width: 6),
                              const Icon(Icons.verified, size: 16)
                            ])))
                  ]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14))),
        )),
      )),
    );
  }
}

Future<void> showOrganizationDetails(
        BuildContext context, Map<String, dynamic> details,
        {bool verified = false}) =>
    showDialog<void>(
      context: context,
      builder: (context) =>
          _organizationDetailsDialog(details, verified: verified),
    );

Widget _organizationDetailsDialog(Map<String, dynamic> details,
        {required bool verified}) =>
    AppDialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppDialogHeader(
                      title: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: verified
                            ? (details['legalName'] ?? '')
                            : VerificationStrings.text('preview')),
                    if (verified)
                      const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(Icons.verified, size: 16)))
                  ]))),
                  if (!verified) Text(details['legalName'] ?? ''),
                  OrganizationIdentityDetails(details: details),
                  if (verified) ...[
                    const SizedBox(height: 16),
                    Text(VerificationStrings.text('explanation'))
                  ],
                ]),
          )),
        ));

class OrganizationIdentityDetails extends StatelessWidget {
  final Map<String, dynamic> details;
  const OrganizationIdentityDetails({super.key, required this.details});
  @override
  Widget build(BuildContext context) {
    final address = details['address'] as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final key in [
        'registrationNumber',
        'vatId',
        'address',
        'contactEmail',
        'phone',
        'website'
      ])
        if (key == 'address' || (details[key] as String? ?? '').isNotEmpty)
          _line(
              context,
              key,
              key == 'address'
                  ? [
                      address['street'],
                      address['postalCode'],
                      address['city'],
                      details['countryCode']
                    ].whereType<String>().where((v) => v.isNotEmpty).join(', ')
                  : details[key] as String),
    ]);
  }

  Widget _line(BuildContext context, String key, String value) {
    Uri? uri;
    if (key == 'website') {
      final candidate = Uri.tryParse(value);
      if (candidate?.scheme == 'https' &&
          candidate!.host.isNotEmpty &&
          candidate.userInfo.isEmpty) uri = candidate;
    }
    if (key == 'contactEmail' &&
        RegExp(r'^[^\s@?&#]+@[^\s@?&#]+$').hasMatch(value))
      uri = Uri(scheme: 'mailto', path: value);
    if (key == 'phone' && RegExp(r'^\+?[\d ()-]+$').hasMatch(value))
      uri = Uri(scheme: 'tel', path: value.replaceAll(RegExp(r'[ ()-]'), ''));
    final link = uri;
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(VerificationStrings.text(key),
              style: Theme.of(context).textTheme.labelLarge),
          if (link == null)
            SelectableText(value)
          else
            TextButton(onPressed: () => launchUrl(link), child: Text(value)),
        ]));
  }
}
