import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/providers.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  final _captures = <File>[];
  var _loading = true;
  var _capturing = false;
  var _autoCapture = false;
  var _grid = true;
  var _flash = FlashMode.off;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: _grid ? 'Hide grid' : 'Show grid',
            onPressed: () => setState(() => _grid = !_grid),
            icon: Icon(_grid ? Icons.grid_off : Icons.grid_on),
          ),
          IconButton(
            tooltip: 'Flash',
            onPressed: _cycleFlash,
            icon: Icon(_flashIcon),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : controller == null || !controller.value.isInitialized
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Camera is unavailable. Check camera permission and device hardware.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Center(child: CameraPreview(controller)),
                    if (_grid) const _GridOverlay(),
                    const _EdgeOverlay(),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 112,
                      child: _CaptureStrip(captures: _captures),
                    ),
                  ],
                ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FilterChip(
                label: const Text('Auto'),
                selected: _autoCapture,
                onSelected: (value) => _setAutoCapture(value),
              ),
              FilledButton.tonalIcon(
                onPressed: _captures.isEmpty ? null : _finish,
                icon: const Icon(Icons.check),
                label: Text('Finish ${_captures.length}'),
              ),
              FilledButton(
                onPressed: _capturing ? null : _capture,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  minimumSize: const Size(72, 72),
                ),
                child: _capturing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt, size: 30),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initialize() async {
    final permission = await Permission.camera.request();
    if (!permission.isGranted) {
      setState(() => _loading = false);
      return;
    }
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final camera = _cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );
    final controller = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await controller.initialize();
    await controller.setFlashMode(_flash);
    setState(() {
      _controller = controller;
      _loading = false;
    });
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing || !controller.value.isInitialized) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      _captures.add(File(file.path));
    } finally {
      if (mounted) {
        setState(() => _capturing = false);
      }
    }
  }

  Future<void> _finish() async {
    if (_captures.isEmpty) {
      return;
    }
    final id = await ref.read(documentRepositoryProvider).createDocumentFromFiles(_captures);
    if (mounted) {
      context.go('/documents/$id');
    }
  }

  void _setAutoCapture(bool value) {
    setState(() => _autoCapture = value);
    _autoTimer?.cancel();
    if (!value) {
      return;
    }
    _autoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_capturing) {
        _capture();
      }
    });
  }

  Future<void> _cycleFlash() async {
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      FlashMode.always => FlashMode.torch,
      FlashMode.torch => FlashMode.off,
    };
    await _controller?.setFlashMode(next);
    setState(() => _flash = next);
  }

  IconData get _flashIcon {
    return switch (_flash) {
      FlashMode.off => Icons.flash_off,
      FlashMode.auto => Icons.flash_auto,
      FlashMode.always => Icons.flash_on,
      FlashMode.torch => Icons.highlight,
    };
  }
}

class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GridPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _EdgeOverlay extends StatelessWidget {
  const _EdgeOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.82,
          heightFactor: 0.68,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CaptureStrip extends StatelessWidget {
  const _CaptureStrip({required this.captures});

  final List<File> captures;

  @override
  Widget build(BuildContext context) {
    if (captures.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: captures.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(captures[index], width: 58, height: 74, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
