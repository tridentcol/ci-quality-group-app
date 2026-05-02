import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
      'Proveedor',
      'Material',
      'Tipo lámina',
      'Unidad',
      'Cantidad',
      'Valor unitario',
      'Valor total',
      'Método de pago',
      'Quién paga',
      'Registrada por',
      'Registrada el',
    ];
    sheet.appendRow(headers.map<CellValue>((h) => TextCellValue(h)).toList());

    final dateFmt = DateFormat('dd/MM/yyyy', 'es_CO');
    final dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm', 'es_CO');

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
}
