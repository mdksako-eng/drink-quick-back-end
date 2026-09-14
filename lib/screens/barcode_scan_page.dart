// screens/barcode_scan_page.dart
// A lightweight, reusable full-screen barcode/QR scanner.
// Pops with the raw scanned value (String) on success, or null on cancel.
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/i18n.dart';

class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key});

  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _torchOn = false;
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handling) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue ?? b.displayValue;
      if (raw != null && raw.isNotEmpty) {
        _handling = true;
        Navigator.of(context).pop(raw.trim());
        return;
      }
    }
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (mounted) setState(() => _torchOn = !_torchOn);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(t('scanTitle')),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _cameraError(error),
          ),
          _buildOverlay(primary),
        ],
      ),
    );
  }

  Widget _buildOverlay(Color primary) {
    return Stack(
      children: [
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: primary, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(t('scanHint'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            children: [
              _circleButton(
                  _torchOn ? Icons.flash_off : Icons.flash_on, _toggleTorch),
              const SizedBox(height: 12),
              _circleButton(Icons.cameraswitch, _controller.switchCamera),
            ],
          ),
        ),
      ],
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }

  Widget _cameraError(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.no_photography, size: 60, color: Colors.grey),
          const SizedBox(height: 12),
          Text(t('scanCameraError'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ]),
      ),
    );
  }
}
