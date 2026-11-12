import 'package:geolocator/geolocator.dart';

import '../models/site.dart';

class LocationException implements Exception {
  final String message;
  LocationException(this.message);
  @override
  String toString() => message;
}

class SiteMatch {
  final Site site;
  final double distanceM;
  SiteMatch(this.site, this.distanceM);
}

class LocationService {
  /// Gets a fresh, high-accuracy GPS fix. Throws [LocationException]
  /// with a message the worker can act on.
  static Future<Position> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationException('Turn on Location (GPS) and try again.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw LocationException(
          'Location permission is off. Allow it in Settings > Apps > AES Team.');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
    // Android reports positions coming from "fake GPS" apps.
    if (pos.isMocked) {
      throw LocationException(
          'Fake GPS app detected. Uninstall it to mark attendance.');
    }
    if (pos.accuracy > 100) {
      throw LocationException(
          'GPS signal is weak (±${pos.accuracy.round()} m). Move to open sky and retry.');
    }
    return pos;
  }

  /// Nearest site whose geofence contains [pos], or null if outside all.
  static SiteMatch? matchSite(Position pos, List<Site> sites) {
    SiteMatch? best;
    for (final s in sites) {
      final d =
          Geolocator.distanceBetween(pos.latitude, pos.longitude, s.lat, s.lng);
      if (d <= s.radiusM && (best == null || d < best.distanceM)) {
        best = SiteMatch(s, d);
      }
    }
    return best;
  }
}
