import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../company.dart';
import '../models/bill.dart';
import '../util.dart';

class BillingService {
  static final _db = FirebaseFirestore.instance;
  static final _col = _db.collection('bills');

  static Stream<List<Bill>> watch(BillKind kind) => _col
      .where('kind', isEqualTo: kind.name)
      .snapshots()
      .map((q) => q.docs.map(Bill.fromDoc).toList()
        ..sort((a, b) => b.number.compareTo(a.number)));

  /// Next number like QT-2026-001 / INV-2026-001, from a counter per year.
  static Future<String> _nextNumber(BillKind kind, DateTime date) {
    final prefix = kind == BillKind.quote ? 'QT' : 'INV';
    final ref = _db.collection('counters').doc('$prefix-${date.year}');
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final n = ((snap.data()?['n'] ?? 0) as num).toInt() + 1;
      tx.set(ref, {'n': n});
      return '$prefix-${date.year}-${n.toString().padLeft(3, '0')}';
    });
  }

  /// Saves the bill; a new one gets the next number. Returns the bill id.
  static Future<String> save(Bill b) async {
    var number = b.number;
    if (number.isEmpty) number = await _nextNumber(b.kind, b.date);
    final data = {...b.toMap(), 'number': number};
    if (b.id.isEmpty) {
      final ref = await _col.add({...data, 'createdAt': FieldValue.serverTimestamp()});
      return ref.id;
    }
    await _col.doc(b.id).set(data);
    return b.id;
  }

  static Future<void> delete(String id) => _col.doc(id).delete();

  static Future<void> recordPayment(Bill b, double amount) {
    final paid = b.paidAmount + amount;
    return _col.doc(b.id).update({
      'paidAmount': paid,
      'status': paid >= b.total - 0.5 ? 'Paid' : 'Part paid',
    });
  }

  /// Creates an invoice from a quote and marks the quote "Invoiced".
  static Future<String> convertToInvoice(Bill quote) async {
    final inv = Bill(
      id: '',
      kind: BillKind.invoice,
      number: '',
      date: DateTime.now(),
      clientName: quote.clientName,
      clientAddress: quote.clientAddress,
      clientGstin: quote.clientGstin,
      subject: quote.subject,
      items: quote.items,
      gstPct: quote.gstPct,
      status: 'Unpaid',
      paidAmount: 0,
      notes: quote.notes,
      fromQuoteId: quote.id,
    );
    final id = await save(inv);
    await _col.doc(quote.id).update({'status': 'Invoiced'});
    return id;
  }

  // ---------- PDF ----------
  static String _rs(num v) => 'Rs. ${money(v).replaceAll('₹', '').trim()}';

  static Future<void> sharePdf(Bill b) async {
    final doc = pw.Document();
    final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(Company.name,
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text(Company.address),
                pw.Text('${Company.phone}  |  ${Company.web}'),
                if (Company.gstin.isNotEmpty) pw.Text('GSTIN: ${Company.gstin}'),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(b.kindLabel.toUpperCase(),
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Text('No: ${b.number}'),
                pw.Text('Date: ${shortDate.format(b.date)}'),
              ],
            ),
          ],
        ),
        pw.Divider(),
        pw.Text('To', style: bold),
        pw.Text(b.clientName),
        if (b.clientAddress.isNotEmpty) pw.Text(b.clientAddress),
        if (b.clientGstin.isNotEmpty) pw.Text('GSTIN: ${b.clientGstin}'),
        if (b.subject.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text('Subject: ${b.subject}', style: bold),
        ],
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: ['#', 'Description', 'Qty', 'Unit', 'Rate', 'Amount'],
          data: [
            for (var i = 0; i < b.items.length; i++)
              [
                '${i + 1}',
                b.items[i].description,
                b.items[i].qty.toString(),
                b.items[i].unit,
                _rs(b.items[i].rate),
                _rs(b.items[i].amount),
              ],
          ],
          headerStyle: bold,
          cellAlignments: {
            0: pw.Alignment.center,
            2: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
          },
          columnWidths: {
            0: const pw.FixedColumnWidth(24),
            1: const pw.FlexColumnWidth(4),
          },
        ),
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Subtotal: ${_rs(b.subtotal)}'),
              pw.Text('GST ${b.gstPct.toStringAsFixed(0)}%: ${_rs(b.gst)}'),
              pw.Text('Total: ${_rs(b.total)}',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        if (b.notes.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text('Terms / Notes', style: bold),
          pw.Text(b.notes),
        ],
        pw.SizedBox(height: 40),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(children: [
            pw.Text('For ${Company.name}'),
            pw.SizedBox(height: 36),
            pw.Text('Authorised Signatory'),
          ]),
        ),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: '${b.number}.pdf');
  }
}
