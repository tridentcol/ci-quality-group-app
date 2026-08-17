import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Campo de foto: botones directos "Tomar foto" / "Galería" + preview.
/// Comprime en origen (`imageQuality`/`maxWidth`) para no subir fotos
/// pesadas a Storage. Devuelve los bytes vía [onChanged] — el
/// formulario decide cuándo subirlos.
///
/// **Por qué no hay un bottom sheet intermedio**: en Flutter Web,
/// `image_picker` abre un `<input type=file>` oculto y le hace
/// `.click()` — los navegadores solo permiten eso dentro del mismo
/// stack síncrono de un gesto de usuario real. Pasar primero por un
/// `showModalBottomSheet` (async) rompe esa cadena: el navegador
/// descarta el `.click()` en silencio (no pasa nada, ni error ni
/// pedido de permiso — exactamente el síntoma reportado en producción).
/// Por eso cada botón llama a [_pick] directo desde su `onPressed`.
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
        // 1280px / calidad 60 sigue siendo perfectamente legible para
        // una foto de evidencia (material, vagón, placa) y pesa bastante
        // menos que el ajuste anterior (1600px/70) — más rápido de subir
        // con datos móviles y menos espacio en Storage.
        imageQuality: 60,
        maxWidth: 1280,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _bytes = bytes);
      widget.onChanged(bytes);
    } catch (e) {
      // Sin este catch, cualquier falla de la cámara/galería (permiso
      // denegado, plugin no disponible, etc.) quedaba completamente
      // invisible — el usuario tocaba el botón y "no pasaba nada".
      // ignore: avoid_print
      print('PhotoPickerField._pick error ($source): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        Container(
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
                            'Sin foto todavía',
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
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                // Llamada directa y síncrona a `_pick` desde el propio
                // tap — ver comentario de la clase. NO envolver esto en
                // un diálogo/bottom sheet previo.
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Tomar foto'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galería'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
