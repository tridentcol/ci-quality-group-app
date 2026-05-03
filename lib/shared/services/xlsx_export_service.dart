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

  /// Exporta una lista de ventas en formato tabular (una venta por fila).
  static Future<void> exportSales({
    required List<Sale> sales,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final sheet = excel['Ventas'];

    final headers = [
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
    sheet.appendRow(headers.map<CellValue>((h) => TextCellValue(h)).toList());

    final dateFmt = DateFormat('dd/MM/yyyy', 'es_CO');
    final dateTimeFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_CO');

    for (final s in sales) {
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

    // Estiliza encabezados (negrita y fondo verde árbol).
    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1F5128'),
      horizontalAlign: HorizontalAlign.Center,
    );
    for (var col = 0; col < headers.length; col++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
              .cellStyle =
          headerStyle;
    }

    final filenameDate = DateFormat('yyyyMMdd').format(rangeStart);
    final filenameDateEnd = DateFormat('yyyyMMdd').format(rangeEnd);
    final filename = 'CQG_ventas_${filenameDate}_$filenameDateEnd.xlsx';

    final bytes = excel.save(fileName: filename);
    if (bytes == null) throw StateError('No se pudo serializar el archivo Excel.');

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
      subject: 'Ventas CI Quality Group',
      text:
          'Exportación de ventas del ${dateFmt.format(rangeStart)} al ${dateFmt.format(rangeEnd)} '
          '(${sales.length} registros).',
    );
  }

  /// Exporta una lista de registros de horas a `.xlsx`.
  ///
  /// Cada fila representa el cierre de un día de un trabajador, con todas
  /// las horas en horas decimales para facilitar el cálculo en nómina.
  static Future<void> exportHours({
    required List<HoursEntry> entries,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final sheet = excel['Horas'];

    final headers = [
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
    sheet.appendRow(headers.map<CellValue>((h) => TextCellValue(h)).toList());

    final dateFmt = DateFormat('dd/MM/yyyy', 'es_CO');
    final timeFmt = DateFormat('h:mm a', 'es_CO');
    final weekdayFmt = DateFormat('EEEE', 'es_CO');

    final sorted = [...entries]
      ..sort((a, b) {
        final byDate = a.workDate.compareTo(b.workDate);
        if (byDate != 0) return byDate;
        return a.workerName.compareTo(b.workerName);
      });

    for (final e in sorted) {
      sheet.appendRow(<CellValue>[
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
      ]);
    }

    // Fila de totales por trabajador → al final, opcional resumen.
    final byWorker = <String, HoursBreakdown>{};
    for (final e in sorted) {
      byWorker[e.workerName] =
          (byWorker[e.workerName] ?? HoursBreakdown()) + e.breakdown;
    }
    if (byWorker.isNotEmpty) {
      final summary = excel['Resumen por trabajador'];
      summary.appendRow(<CellValue>[
        TextCellValue('Trabajador'),
        TextCellValue('Hora ordinaria'),
        TextCellValue('Hora extra diurna'),
        TextCellValue('Hora extra nocturna'),
        TextCellValue('Hora dominical diurna ord.'),
        TextCellValue('Hora extra dominical diurna'),
        TextCellValue('Hora extra dominical nocturna'),
        TextCellValue('Total horas pagas'),
      ]);
      final names = byWorker.keys.toList()..sort();
      for (final name in names) {
        final b = byWorker[name]!;
        summary.appendRow(<CellValue>[
          TextCellValue(name),
          DoubleCellValue(_hours(b.get(HoursCategory.ordinary))),
          DoubleCellValue(_hours(b.get(HoursCategory.extraDay))),
          DoubleCellValue(_hours(b.get(HoursCategory.extraNight))),
          DoubleCellValue(_hours(b.get(HoursCategory.sundayOrdinary))),
          DoubleCellValue(_hours(b.get(HoursCategory.extraSundayDay))),
          DoubleCellValue(_hours(b.get(HoursCategory.extraSundayNight))),
          DoubleCellValue(_hours(b.totalPaid)),
        ]);
      }
      _stylizeHeader(summary, columns: 8);
    }

    _stylizeHeader(sheet, columns: headers.length);

    final filenameDate = DateFormat('yyyyMMdd').format(rangeStart);
    final filenameDateEnd = DateFormat('yyyyMMdd').format(rangeEnd);
    final filename = 'CQG_horas_${filenameDate}_$filenameDateEnd.xlsx';

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
      subject: 'Horas laboradas CI Quality Group',
      text:
          'Exportación de horas del ${dateFmt.format(rangeStart)} al ${dateFmt.format(rangeEnd)} '
          '(${entries.length} registros).',
    );
  }

  static double _hours(Duration d) =>
      double.parse((d.inMinutes / 60).toStringAsFixed(2));

  static void _stylizeHeader(Sheet sheet, {required int columns}) {
    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1F5128'),
      horizontalAlign: HorizontalAlign.Center,
    );
    for (var col = 0; col < columns; col++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
          .cellStyle = headerStyle;
    }
  }
}
