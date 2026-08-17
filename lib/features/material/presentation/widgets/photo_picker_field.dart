import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Campo de foto: bottom sheet "Tomar foto" / "Elegir de galería" +
/// preview. Comprime en origen (`imageQuality`/`maxWidth`) para no subir
/// fotos pesadas a Storage. Devuelve los bytes vía [onChanged] — el
/// formulario decide cuándo subirlos.
class PhotoPickerField extends StatefulWidget {
  const PhotoPickerField({
    super.key,
    required this.label,
    required this.onChanged,
    this.required = false,
  });

  final String label;
  final ValueChanged<Uint8List?> onChanged;
  final bool required;

  @override
  State<PhotoPickerField> createState() => _PhotoPickerFieldState();
}

class _PhotoPickerFieldState extends State<PhotoPickerField> {
  Uint8List? _bytes;
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _bytes = bytes);
      widget.onChanged(bytes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSourceSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pick(source);
  }

  void _clear() {
    setState(() => _bytes = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.label, style: theme.textTheme.titleSmall),
            if (widget.required) ...[
              const SizedBox(width: 4),
              Text('*', style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _busy ? null : _openSourceSheet,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 160,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.4),
              ),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : _bytes == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_a_photo_outlined,
                              color: theme.colorScheme.primary,
                              size: 28,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Toca para agregar foto',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(_bytes!, fit: BoxFit.cover),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                onPressed: _clear,
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
        ),
      ],
    );
  }
}
