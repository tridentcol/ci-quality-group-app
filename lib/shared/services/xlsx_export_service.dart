import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/hours/domain/hours_categories.dart';
import '../../features/hours/domain/hours_entry.dart';
import '../../features/sales/domain/sale.dart';

/// Exporta colecciones de datos a `.xlsx` y abre el share sheet del sistema
/// para que el admin lo envíe por correo, WhatsApp o lo guarde en Drive.
class XlsxExportService {
  XlsxExportService._();

  static const _headerHexBg = '#1F5128';
  static const _headerHexFg = '#FFFFFF';
  static const _summaryHexBg = '#E8F0E9';

  // -------------------- VENTAS --------------------

  /// Exporta una lista de ventas en formato tabular (una venta por fila).
  /// Filtra por rango antes de generar; si la lista llega vacía, lanza error
  /// para que el caller muestre snackbar.
  static Future<void> exportSales({
    required List<Sale> sales,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    if (sales.isEmpty) {
      throw StateError('No hay ventas en el rango seleccionado.');
    }

    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final sheet = excel['Ventas'];

    final headers = <String>[
      'Consecutivo',
      'Fecha',
      'Tipo documento',
      'Número documento',
      'Cliente',
      'Material',
      'Tipo lámina',
      'Unidad',
      'Cantidad',
      'Valor unitario',
      'Valor total',
      'Método de pago',
      'Quién recibe',
      'Registrada por',
      'Registrada el',
    ];

    // Anchos pensados para los datos típicos: consecutivos cortos,
    // nombres y materiales más anchos, valores monetarios con espacio.
    final widths = <double>[
      14, // Consecutivo
      12, // Fecha
      14, // Tipo doc
      18, // Núm doc
      28, // Cliente
      18, // Material
      18, // Tipo lámina
      12, // Unidad
      12, // Cantidad
      16, // Valor unit
      18, // Valor total
      16, // Método pago
      24, // Quién recibe
      22, // Registrada por
      22, // Registrada el
    ];

    sheet.appendRow(headers.map<CellValue>((h) => TextCellValue(h)).toList());

    final dateFmt = DateFormat('dd/MM/yyyy', 'es_CO');
    final dateTimeFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_CO');

    final sorted = [...sales]..sort((a, b) => a.date.compareTo(b.date));
    for (final s in sorted) {
      sheet.appendRow(<CellValue>[
        TextCellValue(s.consecutive),
        TextCellValue(dateFmt.format(s.date)),
        TextCellValue(s.documentType),
        TextCellValue(s.documentNumber),
        TextCellValue(s.providerName),
        TextCellValue(s.material),
        TextCellValue(s.materialVariant ?? ''),
        TextCellValue(s.unit),
        DoubleCellValue(s.quantity.toDouble()),
        DoubleCellValue(s.unitPrice.toDouble()),
        DoubleCellValue(s.totalValue.toDouble()),
        TextCellValue(s.paymentMethod),
        TextCellValue(s.payerName),
        TextCellValue(s.createdByName),
        TextCellValue(dateTimeFmt.format(s.createdAt)),
      ]);
    }

    _stylizeHeader(sheet, columns: headers.length);
    _applyColumnWidths(sheet, widths);

    final filename = 'CQG_ventas_'
        '${DateFormat('yyyyMMdd').format(rangeStart)}_'
        '${DateFormat('yyyyMMdd').format(rangeEnd)}.xlsx';

    await _saveAndShare(
      excel: excel,
      filename: filename,
      subject: 'Ventas CI Quality Group',
      message:
          'Exportación de ventas del ${dateFmt.format(rangeStart)} al ${dateFmt.format(rangeEnd)} '
          '(${sales.length} registros).',
    );
  }

  // -------------------- HORAS --------------------

  /// Exporta los registros de horas. Genera UN libro por mes cubierto por
  /// el rango. Cada libro contiene una hoja por semana (Lun–Dom) con
  /// registros y una hoja de "Resumen del mes" agregada por trabajador.
  /// Las semanas vacías no se generan.
  static Future<void> exportHours({
    required List<HoursEntry> entries,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    if (entries.isEmpty) {
      throw StateError('No hay registros de horas en el rango seleccionado.');
    }

    // Agrupa por mes (YYYY-MM) usando workDate.
    final byMonth = <String, List<HoursEntry>>{};
    for (final e in entries) {
      final key = DateFormat('yyyy-MM').format(e.workDate);
      byMonth.putIfAbsent(key, () => []).add(e);
    }

    final months = byMonth.keys.toList()..sort();
    final dir = await getTemporaryDirectory();
    final files = <XFile>[];
    final monthFmt = DateFormat('MMMM yyyy', 'es_CO');
    final dateRangeFmt = DateFormat('dd/MM/yyyy', 'es_CO');

    for (final monthKey in months) {
      final monthEntries = byMonth[monthKey]!;
      final monthDate = DateFormat('yyyy-MM').parse(monthKey);
      final monthLabel = monthFmt.format(monthDate);
      final excel = _buildMonthlyHoursWorkbook(
        monthEntries: monthEntries,
        monthDate: monthDate,
      );

      final filename =
          'CQG_horas_${DateFormat('yyyy_MM').format(monthDate)}.xlsx';
      final bytes = excel.save(fileName: filename);
      if (bytes == null) {
        throw StateError('No se pudo serializar el Excel de $monthLabel.');
      }
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      files.add(XFile(
        file.path,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ));
    }

    final shareText = months.length == 1
        ? 'Horas del mes de '
            '${monthFmt.format(DateFormat('yyyy-MM').parse(months.first))} '
            '(${entries.length} registros).'
        : 'Horas del ${dateRangeFmt.format(rangeStart)} al ${dateRangeFmt.format(rangeEnd)}: '
            '${months.length} libros adjuntos (${entries.length} registros en total).';

    await Share.shareXFiles(
      files,
      subject: 'Horas laboradas CI Quality Group',
      text: shareText,
    );
  }

  /// Construye el workbook de UN mes: hojas semanales (por día-de-mes) +
  /// resumen por trabajador del mes.
  ///
  /// Convención de semanas: en lugar de Lun–Dom (que cruza meses), las
  /// semanas se cortan por bloques de 7 días dentro del mes:
  ///   Semana 1 = días 1-7, Semana 2 = 8-14, Semana 3 = 15-21,
  ///   Semana 4 = 22-28, Semana 5 = 29 hasta el último día del mes.
  /// Así el cierre mensual cubre exactamente el mes natural y la semana
  /// final ajusta su tamaño según el mes (28-31 días).
  static Excel _buildMonthlyHoursWorkbook({
    required List<HoursEntry> monthEntries,
    required DateTime monthDate,
  }) {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    // El último día del mes se obtiene pidiendo "día 0 del mes siguiente",
    // truco clásico que respeta los meses de 28/29/30/31 días.
    final daysInMonth = DateTime(monthDate.year, monthDate.month + 1, 0).day;

    // Construye los bloques de semana 1..N por día-de-mes. La última
    // semana se trunca al último día real del mes.
    final weeks = <_WeekRange>[];
    var weekFirstDay = 1;
    while (weekFirstDay <= daysInMonth) {
      final weekLastDay = (weekFirstDay + 6).clamp(1, daysInMonth);
      weeks.add(_WeekRange(
        start: DateTime(monthDate.year, monthDate.month, weekFirstDay),
        end: DateTime(monthDate.year, monthDate.month, weekLastDay),
      ));
      weekFirstDay += 7;
    }

    // Asigna cada entrada a su semana según el día-de-mes de workDate.
    final entriesByWeekIndex = <int, List<HoursEntry>>{};
    for (final e in monthEntries) {
      // Solo entradas dentro del mes; las que cayeran fuera por algún
      // motivo (no debería pasar dado el agrupamiento previo) se ignoran.
      if (e.workDate.year != monthDate.year ||
          e.workDate.month != monthDate.month) {
        continue;
      }
      final weekIdx = ((e.workDate.day - 1) ~/ 7).clamp(0, weeks.length - 1);
      entriesByWeekIndex.putIfAbsent(weekIdx, () => []).add(e);
    }

    int weekNum = 0;
    for (var i = 0; i < weeks.length; i++) {
      final wkEntries = entriesByWeekIndex[i] ?? const [];
      if (wkEntries.isEmpty) continue; // skip semanas sin registros
      weekNum++;
      _appendWeekSheet(
        excel: excel,
        weekNumber: weekNum,
        week: weeks[i],
        entries: wkEntries,
      );
    }

    _appendMonthSummarySheet(
      excel: excel,
      monthDate: monthDate,
      entries: monthEntries,
    );

    return excel;
  }

  static void _appendWeekSheet({
    required Excel excel,
    required int weekNumber,
    required _WeekRange week,
    required List<HoursEntry> entries,
  }) {
    final dayLabel = DateFormat('d MMM', 'es_CO');
    final sheetName = 'Semana $weekNumber '
        '(${dayLabel.format(week.start)}-${dayLabel.format(week.end)})';
    // Excel limita nombres de hoja a 31 chars y ciertos caracteres.
    final safeName = _sanitizeSheetName(sheetName);
    final sheet = excel[safeName];

    final headers = _hoursHeaders;
    sheet.appendRow(headers.map<CellValue>((h) => TextCellValue(h)).toList());

    final sorted = [...entries]..sort((a, b) {
        final byDate = a.workDate.compareTo(b.workDate);
        if (byDate != 0) return byDate;
        return a.workerName.compareTo(b.workerName);
      });

    for (final e in sorted) {
      sheet.appendRow(_hoursDataRow(e));
    }

    // Fila de totales semanales.
    final weekTotals = entries
        .map((e) => e.breakdown)
        .fold<HoursBreakdown>(HoursBreakdown(), (a, b) => a + b);
    sheet.appendRow(_hoursTotalRow('TOTAL SEMANA', weekTotals));
    _stylizeTotalRow(sheet,
        rowIndex: sorted.length + 1, columns: headers.length);

    _stylizeHeader(sheet, columns: headers.length);
    _applyColumnWidths(sheet, _hoursColumnWidths);
  }

  static void _appendMonthSummarySheet({
    required Excel excel,
    required DateTime monthDate,
    required List<HoursEntry> entries,
  }) {
    final monthLabel = DateFormat('MMMM yyyy', 'es_CO').format(monthDate);
    final sheet = excel[_sanitizeSheetName('Resumen $monthLabel')];

    final headers = <String>[
      'Trabajador',
      'Hora ordinaria',
      'Hora extra diurna',
      'Hora extra nocturna',
      'Hora dominical diurna ord.',
      'Hora extra dominical diurna',
      'Hora extra dominical nocturna',
      'Total horas pagas',
      'Días registrados',
    ];
    final widths = <double>[28, 16, 18, 18, 24, 24, 26, 18, 16];

    sheet.appendRow(headers.map<CellValue>((h) => TextCellValue(h)).toList());

    final byWorker = <String, HoursBreakdown>{};
    final daysByWorker = <String, int>{};
    for (final e in entries) {
      byWorker[e.workerName] =
          (byWorker[e.workerName] ?? HoursBreakdown()) + e.breakdown;
      daysByWorker[e.workerName] = (daysByWorker[e.workerName] ?? 0) + 1;
    }

    final names = byWorker.keys.toList()..sort();
    for (final name in names) {
      final b = byWorker[name]!;
      sheet.appendRow(<CellValue>[
        TextCellValue(name),
        DoubleCellValue(_hours(b.get(HoursCategory.ordinary))),
        DoubleCellValue(_hours(b.get(HoursCategory.extraDay))),
        DoubleCellValue(_hours(b.get(HoursCategory.extraNight))),
        DoubleCellValue(_hours(b.get(HoursCategory.sundayOrdinary))),
        DoubleCellValue(_hours(b.get(HoursCategory.extraSundayDay))),
        DoubleCellValue(_hours(b.get(HoursCategory.extraSundayNight))),
        DoubleCellValue(_hours(b.totalPaid)),
        IntCellValue(daysByWorker[name] ?? 0),
      ]);
    }

    // Totales generales del mes (última fila destacada).
    final monthTotals = entries
        .map((e) => e.breakdown)
        .fold<HoursBreakdown>(HoursBreakdown(), (a, b) => a + b);
    sheet.appendRow(<CellValue>[
      TextCellValue('TOTAL MES'),
      DoubleCellValue(_hours(monthTotals.get(HoursCategory.ordinary))),
      DoubleCellValue(_hours(monthTotals.get(HoursCategory.extraDay))),
      DoubleCellValue(_hours(monthTotals.get(HoursCategory.extraNight))),
      DoubleCellValue(_hours(monthTotals.get(HoursCategory.sundayOrdinary))),
      DoubleCellValue(_hours(monthTotals.get(HoursCategory.extraSundayDay))),
      DoubleCellValue(_hours(monthTotals.get(HoursCategory.extraSundayNight))),
      DoubleCellValue(_hours(monthTotals.totalPaid)),
      IntCellValue(entries.length),
    ]);

    _stylizeHeader(sheet, columns: headers.length);
    _stylizeTotalRow(sheet,
        rowIndex: names.length + 1, columns: headers.length);
    _applyColumnWidths(sheet, widths);
  }

  // -------------------- helpers compartidos --------------------

  static const _hoursHeaders = <String>[
    'Trabajador',
    'Fecha',
    'Día',
    'Entrada',
    'Salida',
    'Estado',
    'Hora ordinaria',
    'Hora extra diurna',
    'Hora extra nocturna',
    'Hora dominical diurna ord.',
    'Hora extra dominical diurna',
    'Hora extra dominical nocturna',
    'Total horas pagas',
    'Almuerzo descontado',
  ];

  static const _hoursColumnWidths = <double>[
    24, // Trabajador
    12, // Fecha
    12, // Día
    11, // Entrada
    11, // Salida
    10, // Estado
    16, // Ordinaria
    18, // Extra diurna
    18, // Extra nocturna
    24, // Dominical diurna ord.
    24, // Extra dominical diurna
    26, // Extra dominical nocturna
    18, // Total
    18, // Almuerzo
  ];

  static List<CellValue> _hoursDataRow(HoursEntry e) {
    final dateFmt = DateFormat('dd/MM/yyyy', 'es_CO');
    final timeFmt = DateFormat('h:mm a', 'es_CO');
    final weekdayFmt = DateFormat('EEEE', 'es_CO');
    return <CellValue>[
      TextCellValue(e.workerName),
      TextCellValue(dateFmt.format(e.workDate)),
      TextCellValue(weekdayFmt.format(e.workDate)),
      TextCellValue(timeFmt.format(e.checkIn)),
      TextCellValue(e.checkOut == null ? '' : timeFmt.format(e.checkOut!)),
      TextCellValue(e.isOpen ? 'Abierto' : 'Cerrado'),
      DoubleCellValue(_hours(e.breakdown.get(HoursCategory.ordinary))),
      DoubleCellValue(_hours(e.breakdown.get(HoursCategory.extraDay))),
      DoubleCellValue(_hours(e.breakdown.get(HoursCategory.extraNight))),
      DoubleCellValue(_hours(e.breakdown.get(HoursCategory.sundayOrdinary))),
      DoubleCellValue(_hours(e.breakdown.get(HoursCategory.extraSundayDay))),
      DoubleCellValue(_hours(e.breakdown.get(HoursCategory.extraSundayNight))),
      DoubleCellValue(_hours(e.breakdown.totalPaid)),
      DoubleCellValue(_hours(e.breakdown.get(HoursCategory.lunch))),
    ];
  }

  static List<CellValue> _hoursTotalRow(String label, HoursBreakdown b) =>
      <CellValue>[
        TextCellValue(label),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        DoubleCellValue(_hours(b.get(HoursCategory.ordinary))),
        DoubleCellValue(_hours(b.get(HoursCategory.extraDay))),
        DoubleCellValue(_hours(b.get(HoursCategory.extraNight))),
        DoubleCellValue(_hours(b.get(HoursCategory.sundayOrdinary))),
        DoubleCellValue(_hours(b.get(HoursCategory.extraSundayDay))),
        DoubleCellValue(_hours(b.get(HoursCategory.extraSundayNight))),
        DoubleCellValue(_hours(b.totalPaid)),
        DoubleCellValue(_hours(b.get(HoursCategory.lunch))),
      ];

  static double _hours(Duration d) =>
      double.parse((d.inMinutes / 60).toStringAsFixed(2));

  static void _stylizeHeader(Sheet sheet, {required int columns}) {
    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString(_headerHexFg),
      backgroundColorHex: ExcelColor.fromHexString(_headerHexBg),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    for (var col = 0; col < columns; col++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
          .cellStyle = headerStyle;
    }
    // Altura del header un poco mayor para que se vea bien con dos líneas.
    sheet.setRowHeight(0, 22);
  }

  static void _stylizeTotalRow(
    Sheet sheet, {
    required int rowIndex,
    required int columns,
  }) {
    final style = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString(_summaryHexBg),
    );
    for (var col = 0; col < columns; col++) {
      sheet
          .cell(
              CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex))
          .cellStyle = style;
    }
  }

  static void _applyColumnWidths(Sheet sheet, List<double> widths) {
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }
  }

  /// Excel limita el nombre de hoja a 31 caracteres y excluye `:\/?*[]`.
  static String _sanitizeSheetName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\\/\?\*\[\]:]'), '-');
    return cleaned.length <= 31 ? cleaned : cleaned.substring(0, 31);
  }

  static Future<void> _saveAndShare({
    required Excel excel,
    required String filename,
    required String subject,
    required String message,
  }) async {
    final bytes = excel.save(fileName: filename);
    if (bytes == null) throw StateError('No se pudo serializar el Excel.');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
      subject: subject,
      text: message,
    );
  }
}

class _WeekRange {
  const _WeekRange({required this.start, required this.end});
  final DateTime start;
  final DateTime end;
}
