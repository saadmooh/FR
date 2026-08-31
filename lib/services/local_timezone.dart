import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Initializes the timezone database and sets [tz.local] to the device's
/// actual zone.
///
/// `initializeTimeZones()` alone leaves [tz.local] at UTC, so the IANA name
/// must be resolved explicitly. This matters in the WorkManager background
/// isolate, where scheduling with UTC produces wrong absolute times.
Future<void> initLocalTimeZone() async {
  tz_data.initializeTimeZones();
  try {
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    final tzName = tzInfo.identifier;
    if (tzName.isNotEmpty) {
      tz.setLocalLocation(tz.getLocation(tzName));
      return;
    }
  } catch (e) {
    debugPrint('Failed to resolve local timezone ($e), keeping tz.local');
  }
  tz.setLocalLocation(tz.local);
}