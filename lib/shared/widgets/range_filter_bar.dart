import 'package:flutter/material.dart';

import '../../core/utils/clock.dart';
import '../../core/utils/dates.dart';

/// Barra de filtros visible para fechas: chips de presets + botón "rango
/// personalizado". Reemplaza el icono de calendario que estaba escondido
/// en el AppBar y que no era evidente para el usuario.
class RangeFilterBar extends StatelessWidget {
  const RangeFilterBar({
    super.key,
    required this.start,
    required this.end,
    required this.onChanged,
  });

  final DateTime start;
  final DateTime end;
  final ValueChanged<DateTimeRange> onChanged;

  Future<void> _pickCustom(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: AppClock.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: start, end: end),
    );
    if (picked != null) {
      onChanged(DateTimeRange(
        start: startOfDay(picked.start),
        end: endOfDay(picked.end),
      ),);
    }
  }

  void _applyPreset(_RangePreset p) {
    final now = AppClock.now();
    DateTime newStart;
    DateTime newEnd;
    switch (p) {
      case _RangePreset.today:
        newStart = startOfDay(now);
        newEnd = endOfDay(now);
        break;
      case _RangePreset.week:
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        newStart = startOfDay(weekStart);
        newEnd = endOfDay(now);
        break;
      case _RangePreset.month:
        // "Este mes" cubre SIEMPRE el mes natural completo: del día 1 al
        // último día calendario, sin importar si hoy es la primera semana.
        // Esto garantiza que los exports semanales incluyan todas las
        // parciales de inicio y fin de mes (los meses no caben en 4
        // semanas exactas).
        newStart = startOfMonth(now);
        newEnd = endOfMonth(now);
        break;
      case _RangePreset.last30:
        newStart = startOfDay(now.subtract(const Duration(days: 29)));
        newEnd = endOfDay(now);
        break;
    }
    onChanged(DateTimeRange(start: newStart, end: newEnd));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activePreset = _matchedPreset();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${formatDate(start)} – ${formatDate(end)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _pickCustom(context),
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('Rango'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _Chip(
                  label: 'Hoy',
                  selected: activePreset == _RangePreset.today,
                  onTap: () => _applyPreset(_RangePreset.today),
                ),
                const SizedBox(width: 6),
                _Chip(
                  label: 'Esta semana',
                  selected: activePreset == _RangePreset.week,
                  onTap: () => _applyPreset(_RangePreset.week),
                ),
                const SizedBox(width: 6),
                _Chip(
                  label: 'Este mes',
                  selected: activePreset == _RangePreset.month,
                  onTap: () => _applyPreset(_RangePreset.month),
                ),
                const SizedBox(width: 6),
                _Chip(
                  label: 'Últimos 30 días',
                  selected: activePreset == _RangePreset.last30,
                  onTap: () => _applyPreset(_RangePreset.last30),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Detecta cuál preset coincide con el rango actual para resaltar el chip.
  _RangePreset? _matchedPreset() {
    final now = AppClock.now();
    final today = startOfDay(now);
    if (_sameDay(start, today) && _sameDay(end, endOfDay(now))) {
      return _RangePreset.today;
    }
    final weekStart = startOfDay(now.subtract(Duration(days: now.weekday - 1)));
    if (_sameDay(start, weekStart) && _sameDay(end, endOfDay(now))) {
      return _RangePreset.week;
    }
    if (_sameDay(start, startOfMonth(now)) && _sameDay(end, endOfMonth(now))) {
      return _RangePreset.month;
    }
    final last30 = startOfDay(now.subtract(const Duration(days: 29)));
    if (_sameDay(start, last30) && _sameDay(end, endOfDay(now))) {
      return _RangePreset.last30;
    }
    return null;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

enum _RangePreset { today, week, month, last30 }

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.primary.withValues(alpha: 0.12);
    final fg =
        selected ? theme.colorScheme.onPrimary : theme.colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style:
              TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
