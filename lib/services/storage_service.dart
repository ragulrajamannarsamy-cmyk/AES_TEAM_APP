import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

/// Uploads into `<folder>/<phone>/...`. Storage rules allow each person to
/// write only into their own folder; owner and managers can read all.
class StorageService {
  static Future<String> upload(String folder, String phone, File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    final type = switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      _ => 'image/jpeg',
    };
    final ref = FirebaseStorage.instance.ref(
        '$folder/$phone/${DateTime.now().millisecondsSinceEpoch}.$ext');
    await ref.putFile(file, SettableMetadata(contentType: type));
    return ref.getDownloadURL();
  }
}
