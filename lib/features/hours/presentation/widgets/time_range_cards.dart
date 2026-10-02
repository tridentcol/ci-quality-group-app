import 'package:flutter/material.dart';

import '../../../../core/utils/dates.dart';
import '../../../../core/utils/time_picker.dart';
import '../../domain/work_schedule.dart';

/// Pide inicio y fin con dos time pickers seguidos. Devuelve `null` si el
/// usuario cancela cualquiera de los dos.
Future<TimeRange?> pickTimeRange(
  BuildContext context,
  TimeRange current, {
  required String title,
}) async {
  final start = await showAppTimePicker(
    context: context,
    initialTime:
        TimeOfDay(hour: current.startHour, minute: current.startMinute),
    helpText: '$title · inicio',
  );
  if (start == null || !context.mounted) return null;
  final end = await showAppTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: current.endHour, minute: current.endMinute),
    helpText: '$title · fin',
  );
  if (end == null) return null;
  return TimeRange(start.hour, start.minute, end.hour, end.minute);
}

/// Rango en formato 12h, ej. `6:00 AM – 1:00 PM`.
String formatTimeRange(TimeRange r) =>
    '${formatTimeOfDay(TimeOfDay(hour: r.startHour, minute: r.startMinute))}'
    ' – '
    '${formatTimeOfDay(TimeOfDay(hour: r.endHour, minute: r.endMinute))}';

class OrdinaryRangeCard extends StatelessWidget {
  const OrdinaryRangeCard({
    super.key,
    required this.label,
    required this.range,
    required this.onEdit,
    this.helper,
  });

  final String label;
  final TimeRange range;
  final VoidCallback onEdit;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label, style: theme.textTheme.titleMedium),
                  ),
                  Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TimeChip(label: 'Entrada', minutes: range.startMinutes),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  TimeChip(label: 'Salida', minutes: range.endMinutes),
                ],
              ),
              if (helper != null) ...[
                const SizedBox(height: 8),
                Text(
                  helper!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LunchRangeCard extends StatelessWidget {
  const LunchRangeCard({
    super.key,
    required this.label,
    required this.range,
    required this.onToggle,
    required this.onEdit,
  });

  final String label;
  final TimeRange? range;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = range != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label, style: theme.textTheme.titleMedium),
                ),
                Switch.adaptive(value: on, onChanged: onToggle),
              ],
            ),
            if (on) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: [
                      TimeChip(label: 'Inicio', minutes: range!.startMinutes),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 8),
                      TimeChip(label: 'Fin', minutes: range!.endMinutes),
                      const Spacer(),
                      Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Sin descuento de almuerzo este día.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class TimeChip extends StatelessWidget {
  const TimeChip({super.key, required this.label, required this.minutes});
  final String label;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    final tod = TimeOfDay(hour: hour, minute: minute);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          Text(
            formatTimeOfDay(tod),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
