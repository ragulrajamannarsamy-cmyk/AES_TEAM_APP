import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

final _inr =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String money(num v) => _inr.format(v);

final dayFmt = DateFormat('yyyy-MM-dd');
final shortDate = DateFormat('d MMM yyyy');
final timeFmt = DateFormat('hh:mm a');

String monthKey(DateTime d) => DateFormat('yyyy-MM').format(d);
String monthLabel(String key) =>
    DateFormat('MMM yyyy').format(DateTime.parse('$key-01'));
String currentMonthKey() => monthKey(DateTime.now());
String prevMonthKey() {
  final n = DateTime.now();
  return monthKey(DateTime(n.year, n.month - 1, 1));
}

String nextMonthKey(String key) {
  final d = DateTime.parse('$key-01');
  return monthKey(DateTime(d.year, d.month + 1, 1));
}

/// Current month and the [n]-1 months before it, newest first.
List<String> recentMonths(int n) {
  final now = DateTime.now();
  return [
    for (var i = 0; i < n; i++) monthKey(DateTime(now.year, now.month - i, 1))
  ];
}

double? parseAmount(String s) =>
    double.tryParse(s.replaceAll(',', '').replaceAll('₹', '').trim());

/// Camera only, no gallery.
Future<File?> takePhoto({bool front = false}) async {
  final x = await ImagePicker().pickImage(
    source: ImageSource.camera,
    preferredCameraDevice: front ? CameraDevice.front : CameraDevice.rear,
    imageQuality: 50,
    maxWidth: 1200,
  );
  return x == null ? null : File(x.path);
}

String _csvCell(Object? v) {
  final s = '${v ?? ''}';
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Writes a CSV (opens in Excel) and opens the share sheet
/// (WhatsApp, Gmail, Drive, Save to Files).
Future<void> shareCsv(String fileName, List<List<Object?>> rows) async {
  final csv = rows.map((r) => r.map(_csvCell).join(',')).join('\r\n');
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$fileName');
  await f.writeAsString('﻿$csv'); // BOM so Excel reads ₹ and Tamil names
  await Share.shareXFiles([XFile(f.path)], subject: fileName);
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
  ));
}
