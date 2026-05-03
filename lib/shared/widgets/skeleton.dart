import 'package:flutter/material.dart';

/// Bloque base con animación de pulse para skeleton screens. Reemplaza
/// el `CircularProgressIndicator` centrado durante cargas iniciales,
/// que se siente más profesional.
class SkeletonBlock extends StatefulWidget {
  const SkeletonBlock({
    super.key,
    this.height = 16,
    this.width,
    this.borderRadius = 8,
  });

  final double height;
  final double? width;
  final double borderRadius;

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final highlight =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(base, highlight, _controller.value),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

/// Skeleton placeholder con la silueta de una Card típica de la app.
/// Útil para listas (sales, workers, users, hours).
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SkeletonBlock(width: 44, height: 44, borderRadius: 12),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBlock(width: 160, height: 14),
                  SizedBox(height: 8),
                  SkeletonBlock(width: 100, height: 12),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const SkeletonBlock(width: 50, height: 16),
          ],
        ),
      ),
    );
  }
}

/// Lista vertical de skeleton cards. Repite el patrón N veces para que la
/// transición a contenido real sea menos jarring que un spinner.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 5, this.padding});

  final int count;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => const SkeletonCard(),
    );
  }
}
