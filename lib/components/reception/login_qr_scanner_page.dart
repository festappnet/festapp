import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/reception/reception_strings.dart';
import 'package:fstapp/components/reception/login_qr_barcode.dart';
import 'package:fstapp/components/reception/manual_login_code_field.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

enum ReceptionLoginCredentialType { qr, manualCode }

class ReceptionLoginCredential {
  const ReceptionLoginCredential.qr(this.value)
      : type = ReceptionLoginCredentialType.qr;
  const ReceptionLoginCredential.manualCode(this.value)
      : type = ReceptionLoginCredentialType.manualCode;

  final ReceptionLoginCredentialType type;
  final String value;
}

@RoutePage()
class LoginQrScannerPage extends StatefulWidget {
  const LoginQrScannerPage({super.key});
  static const ROUTE = 'login-qr';
  @override
  State<LoginQrScannerPage> createState() => _LoginQrScannerPageState();
}

class _LoginQrScannerPageState extends State<LoginQrScannerPage> {
  final _controller = MobileScannerController(
      formats: [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates);
  bool _handled = false;
  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      LaunchUrlService.openExternalUrl('${AppConfig.webLink}/login-qr',
          inCurrentWindow: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _detect(BarcodeCapture capture) async {
    if (_handled) return;
    final payload = loginQrFromBarcodes(capture.barcodes);
    // Camera backends can emit an empty or partial detection before the QR is
    // decoded. Keep scanning instead of turning that transient frame into a
    // user-visible rejection of the code in front of the camera.
    if (payload == null) return;
    _handled = true;
    await _controller.stop();
    if (mounted) {
      context.router.maybePop(ReceptionLoginCredential.qr(payload.raw));
    }
  }

  Future<void> _useManualCode(String code) async {
    if (_handled) return;
    _handled = true;
    await _controller.stop();
    if (mounted) {
      context.router.maybePop(ReceptionLoginCredential.manualCode(code));
    }
  }

  @override
  Widget build(BuildContext context) => kIsWeb
      ? const SizedBox.shrink()
      : Scaffold(
      appBar: AppBar(title: Text(ReceptionStrings.scan)),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _detect,
              errorBuilder: (context, error) =>
                  Center(child: Text(ReceptionStrings.cameraUnavailable)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: Center(
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ManualLoginCodeEntry(
                      onSubmitted: _useManualCode,
                      title: ReceptionStrings.enterManualCode,
                      fieldLabel: ReceptionStrings.manualCode,
                      submitLabel:
                          MaterialLocalizations.of(context).okButtonLabel,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ));
}
