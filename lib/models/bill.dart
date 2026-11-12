import 'package:cloud_firestore/cloud_firestore.dart';

import 'requests.dart';

enum BillKind { quote, invoice }

const billStatuses = {
  BillKind.quote: ['Draft', 'Sent', 'Accepted', 'Rejected', 'Invoiced'],
  BillKind.invoice: ['Unpaid', 'Part paid', 'Paid', 'Cancelled'],
};

class LineItem {
  final String description;
  final double qty;
  final String unit;
  final double rate;

  const LineItem({
    required this.description,
    required this.qty,
    required this.unit,
    required this.rate,
  });

  double get amount => qty * rate;

  factory LineItem.fromMap(Map<String, dynamic> m) => LineItem(
        description: (m['description'] ?? '') as String,
        qty: numVal(m['qty']),
        unit: (m['unit'] ?? 'Nos') as String,
        rate: numVal(m['rate']),
      );

  Map<String, dynamic> toMap() =>
      {'description': description, 'qty': qty, 'unit': unit, 'rate': rate};
}

/// A quote or a tax invoice.
class Bill {
  final String id;
  final BillKind kind;
  final String number;
  final DateTime date;
  final String clientName;
  final String clientAddress;
  final String clientGstin;
  final String subject;
  final List<LineItem> items;
  final double gstPct;
  final String status;
  final double paidAmount;
  final String notes;
  final String? fromQuoteId;

  const Bill({
    required this.id,
    required this.kind,
    required this.number,
    required this.date,
    required this.clientName,
    required this.clientAddress,
    required this.clientGstin,
    required this.subject,
    required this.items,
    required this.gstPct,
    required this.status,
    required this.paidAmount,
    required this.notes,
    this.fromQuoteId,
  });

  double get subtotal => items.fold(0, (s, i) => s + i.amount);
  double get gst => subtotal * gstPct / 100;
  double get total => subtotal + gst;
  double get balance => total - paidAmount;
  String get kindLabel => kind == BillKind.quote ? 'Quotation' : 'Tax Invoice';

  factory Bill.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Bill(
      id: d.id,
      kind: m['kind'] == 'invoice' ? BillKind.invoice : BillKind.quote,
      number: (m['number'] ?? '') as String,
      date: tsDate(m['date']) ?? DateTime.now(),
      clientName: (m['clientName'] ?? '') as String,
      clientAddress: (m['clientAddress'] ?? '') as String,
      clientGstin: (m['clientGstin'] ?? '') as String,
      subject: (m['subject'] ?? '') as String,
      items: ((m['items'] ?? const []) as List)
          .map((e) => LineItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      gstPct: m['gstPct'] == null ? 18 : numVal(m['gstPct']),
      status: (m['status'] ?? '') as String,
      paidAmount: numVal(m['paidAmount']),
      notes: (m['notes'] ?? '') as String,
      fromQuoteId: m['fromQuoteId'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'number': number,
        'date': Timestamp.fromDate(date),
        'clientName': clientName,
        'clientAddress': clientAddress,
        'clientGstin': clientGstin,
        'subject': subject,
        'items': items.map((i) => i.toMap()).toList(),
        'gstPct': gstPct,
        'status': status,
        'paidAmount': paidAmount,
        'notes': notes,
        'fromQuoteId': fromQuoteId,
        'total': total,
      };
}
