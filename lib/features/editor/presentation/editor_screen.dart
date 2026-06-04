import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/image_processing/document_detector.dart';
import '../../../core/image_processing/image_processing_service.dart';
import '../../../core/providers.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({
    required this.documentId,
    required this.pageId,
    super.key,
  });

  final String documentId;
  final String pageId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  var _filter = ScanFilter.auto;
  var _settings = const ProcessingSettings();
  var _rotation = 0;
  var _processing = false;
  List<CropPoint>? _cropPoints;

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(pagesProvider(widget.documentId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit page'),
        actions: [
          TextButton(
            onPressed: _processing ? null : () => _save(pages.value),
            child: _processing ? const Text('Saving...') : const Text('Apply'),
          ),
        ],
      ),
      body: pages.when(
        data: (items) {
          final page = items.where((item) => item.id == widget.pageId).firstOrNull;
          if (page == null) {
            return const Center(child: Text('Page not found'));
          }
          _cropPoints ??= _parseCrop(page);
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _CropPreview(
                    page: page,
                    points: _cropPoints!,
                    onChanged: (points) => setState(() => _cropPoints = points),
                  ),
                ),
              ),
              _EditorControls(
                filter: _filter,
                settings: _settings,
                onFilter: (filter) => setState(() => _filter = filter),
                onSettings: (settings) => setState(() => _settings = settings),
                onRotate: () => setState(() => _rotation = (_rotation + 90) % 360),
              ),
            ],
          );
        },
        error: (error, _) => Center(child: Text('Could not load page: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Future<void> _save(List<ScanPage>? pages) async {
    final page = pages?.where((item) => item.id == widget.pageId).firstOrNull;
    if (page == null) {
      return;
    }
    setState(() => _processing = true);
    try {
      await ref.read(documentRepositoryProvider).reprocessPage(
            page: page,
            filter: _filter,
            settings: _settings,
            cropPoints: _cropPoints,
            rotation: _rotation,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Page updated')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  List<CropPoint> _parseCrop(ScanPage page) {
    try {
      final list = jsonDecode(page.cropPolygonJson) as List<dynamic>;
      final points = list
          .map((item) => CropPoint.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      if (points.length == 4) {
        return points;
      }
    } catch (_) {
      // Fall back to a full-page crop when older metadata is malformed.
    }
    return const [
      CropPoint(0.05, 0.05),
      CropPoint(0.95, 0.05),
      CropPoint(0.95, 0.95),
      CropPoint(0.05, 0.95),
    ];
  }
}

class _CropPreview extends StatelessWidget {
  const _CropPreview({
    required this.page,
    required this.points,
    required this.onChanged,
  });

  final ScanPage page;
  final List<CropPoint> points;
  final ValueChanged<List<CropPoint>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Image.file(File(page.originalPath), fit: BoxFit.contain),
              ),
              CustomPaint(painter: _CropPainter(points)),
              for (var i = 0; i < points.length; i++)
                Positioned(
                  left: points[i].x * constraints.maxWidth - 18,
                  top: points[i].y * constraints.maxHeight - 18,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      final updated = [...points];
                      final x = ((points[i].x * constraints.maxWidth + details.delta.dx) /
                              constraints.maxWidth)
                          .clamp(0.02, 0.98);
                      final y = ((points[i].y * constraints.maxHeight + details.delta.dy) /
                              constraints.maxHeight)
                          .clamp(0.02, 0.98);
                      updated[i] = CropPoint(x.toDouble(), y.toDouble());
                      onChanged(updated);
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.points);

  final List<CropPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(points[0].x * size.width, points[0].y * size.height);
    for (final point in points.skip(1)) {
      path.lineTo(point.x * size.width, point.y * size.height);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) => oldDelegate.points != points;
}

class _EditorControls extends StatelessWidget {
  const _EditorControls({
    required this.filter,
    required this.settings,
    required this.onFilter,
    required this.onSettings,
    required this.onRotate,
  });

  final ScanFilter filter;
  final ProcessingSettings settings;
  final ValueChanged<ScanFilter> onFilter;
  final ValueChanged<ProcessingSettings> onSettings;
  final VoidCallback onRotate;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ScanFilter.values.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = ScanFilter.values[index];
                    return ChoiceChip(
                      label: Text(item.label),
                      selected: item == filter,
                      onSelected: (_) => onFilter(item),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Rotate 90 degrees',
                    onPressed: onRotate,
                    icon: const Icon(Icons.rotate_right),
                  ),
                  Expanded(
                    child: _SliderSet(settings: settings, onSettings: onSettings),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderSet extends StatelessWidget {
  const _SliderSet({required this.settings, required this.onSettings});

  final ProcessingSettings settings;
  final ValueChanged<ProcessingSettings> onSettings;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ControlSlider(
            label: 'Brightness',
            value: settings.brightness,
            min: 0.6,
            max: 1.6,
            onChanged: (value) => onSettings(_copy(brightness: value)),
          ),
          _ControlSlider(
            label: 'Contrast',
            value: settings.contrast,
            min: 0.5,
            max: 1.8,
            onChanged: (value) => onSettings(_copy(contrast: value)),
          ),
          _ControlSlider(
            label: 'Saturation',
            value: settings.saturation,
            min: 0,
            max: 1.8,
            onChanged: (value) => onSettings(_copy(saturation: value)),
          ),
          _ControlSlider(
            label: 'Exposure',
            value: settings.exposure,
            min: -1,
            max: 1,
            onChanged: (value) => onSettings(_copy(exposure: value)),
          ),
          _ControlSlider(
            label: 'Gamma',
            value: settings.gamma,
            min: 0.5,
            max: 1.8,
            onChanged: (value) => onSettings(_copy(gamma: value)),
          ),
        ],
      ),
    );
  }

  ProcessingSettings _copy({
    double? brightness,
    double? contrast,
    double? saturation,
    double? sharpness,
    double? exposure,
    double? gamma,
  }) {
    return ProcessingSettings(
      brightness: brightness ?? settings.brightness,
      contrast: contrast ?? settings.contrast,
      saturation: saturation ?? settings.saturation,
      sharpness: sharpness ?? settings.sharpness,
      exposure: exposure ?? settings.exposure,
      gamma: gamma ?? settings.gamma,
    );
  }
}

class _ControlSlider extends StatelessWidget {
  const _ControlSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ],
      ),
    );
  }
}
