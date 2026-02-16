import 'package:intl/intl.dart';

/// Timezone helper utilities for the BMS Pro Pink mobile app
/// 
/// This helper provides functions to:
/// - Convert UTC times to branch local times
/// - Convert branch local times to UTC
/// - Format dates and times in the correct timezone
/// - Handle timezone-aware booking operations
/// 
/// Note: This is a simplified implementation that uses UTC offset calculations.
/// For full IANA timezone support, add the 'timezone' package and run flutter pub get.
class TimezoneHelper {
  static bool _initialized = false;

  /// Initialize timezone data
  /// Call this once at app startup (e.g., in main.dart)
  static void initialize() {
    _initialized = true;
  }

  /// Australian timezones with their UTC offsets (standard time)
  /// Note: This doesn't account for daylight saving - for accurate DST handling,
  /// use the full timezone package
  static const Map<String, String> australianTimezones = {
    'Australia/Sydney': 'Sydney (NSW) - AEST/AEDT',
    'Australia/Melbourne': 'Melbourne (VIC) - AEST/AEDT',
    'Australia/Brisbane': 'Brisbane (QLD) - AEST',
    'Australia/Perth': 'Perth (WA) - AWST',
    'Australia/Adelaide': 'Adelaide (SA) - ACST/ACDT',
    'Australia/Darwin': 'Darwin (NT) - ACST',
    'Australia/Hobart': 'Hobart (TAS) - AEST/AEDT',
    'Australia/Canberra': 'Canberra (ACT) - AEST/AEDT',
    'Australia/Lord_Howe': 'Lord Howe Island - LHST/LHDT',
    'Australia/Broken_Hill': 'Broken Hill (NSW) - ACST/ACDT',
  };

  /// Other international timezones
  static const Map<String, String> otherTimezones = {
    'Pacific/Auckland': 'Auckland (New Zealand)',
    'Asia/Singapore': 'Singapore',
    'Asia/Hong_Kong': 'Hong Kong',
    'Asia/Tokyo': 'Tokyo (Japan)',
    'Asia/Colombo': 'Colombo (Sri Lanka)',
    'Asia/Dubai': 'Dubai (UAE)',
    'Europe/London': 'London (UK)',
    'America/New_York': 'New York (US Eastern)',
    'America/Los_Angeles': 'Los Angeles (US Pacific)',
  };

  /// All timezones - Australian first, then others
  static Map<String, String> get commonTimezones => {
    ...australianTimezones,
    ...otherTimezones,
  };

  /// Get UTC offset in hours for a timezone (approximate, doesn't handle DST precisely)
  static int _getUtcOffsetHours(String timezone) {
    switch (timezone) {
      // Australia
      case 'Australia/Sydney':
      case 'Australia/Melbourne':
      case 'Australia/Hobart':
      case 'Australia/Canberra':
        return 11; // AEDT (summer) - use 10 for AEST (winter)
      case 'Australia/Brisbane':
        return 10; // AEST (no DST)
      case 'Australia/Perth':
        return 8; // AWST
      case 'Australia/Adelaide':
      case 'Australia/Broken_Hill':
        return 10; // ACDT (summer) - use 9.5 for ACST (winter), rounded
      case 'Australia/Darwin':
        return 9; // ACST (no DST), rounded from 9.5
      case 'Australia/Lord_Howe':
        return 11; // LHDT (summer)
      // Other
      case 'Pacific/Auckland':
        return 13; // NZDT (summer)
      case 'Asia/Singapore':
        return 8;
      case 'Asia/Hong_Kong':
        return 8;
      case 'Asia/Tokyo':
        return 9;
      case 'Asia/Colombo':
        return 5; // 5.5 rounded
      case 'Asia/Dubai':
        return 4;
      case 'Europe/London':
        return 0; // GMT (or 1 for BST)
      case 'America/New_York':
        return -5; // EST (or -4 for EDT)
      case 'America/Los_Angeles':
        return -8; // PST (or -7 for PDT)
      default:
        return 10; // Default to AEST
    }
  }

  /// Convert a UTC DateTime to a specific timezone
  /// 
  /// Example:
  /// ```dart
  /// DateTime utcTime = DateTime.parse('2024-12-18T10:00:00.000Z');
  /// DateTime localTime = TimezoneHelper.utcToLocal(utcTime, 'Australia/Sydney');
  /// ```
  static DateTime utcToLocal(DateTime utcDateTime, String timezone) {
    final offsetHours = _getUtcOffsetHours(timezone);
    return utcDateTime.toUtc().add(Duration(hours: offsetHours));
  }

  /// Convert a local DateTime in a specific timezone to UTC
  /// 
  /// Example:
  /// ```dart
  /// DateTime localTime = DateTime(2024, 12, 18, 15, 30); // 3:30 PM local
  /// DateTime utcTime = TimezoneHelper.localToUtc(localTime, 'Australia/Sydney');
  /// ```
  static DateTime localToUtc(DateTime localDateTime, String timezone) {
    final offsetHours = _getUtcOffsetHours(timezone);
    return DateTime.utc(
      localDateTime.year,
      localDateTime.month,
      localDateTime.day,
      localDateTime.hour,
      localDateTime.minute,
      localDateTime.second,
    ).subtract(Duration(hours: offsetHours));
  }

  /// Get current time in a specific timezone
  static DateTime nowInTimezone(String timezone) {
    return utcToLocal(DateTime.now().toUtc(), timezone);
  }

  /// Format a DateTime in a specific timezone
  /// 
  /// Example:
  /// ```dart
  /// String formatted = TimezoneHelper.formatInTimezone(
  ///   DateTime.now().toUtc(),
  ///   'Australia/Sydney',
  ///   'dd MMM yyyy HH:mm'
  /// );
  /// ```
  static String formatInTimezone(DateTime dateTime, String timezone, String format) {
    final localTime = dateTime.isUtc ? utcToLocal(dateTime, timezone) : dateTime;
    return DateFormat(format).format(localTime);
  }

  /// Convert a Firestore Timestamp to local DateTime in a specific timezone
  /// 
  /// Example:
  /// ```dart
  /// DateTime localTime = TimezoneHelper.firestoreTimestampToLocal(
  ///   booking['createdAt'],
  ///   'Australia/Sydney'
  /// );
  /// ```
  static DateTime firestoreTimestampToLocal(dynamic timestamp, String timezone) {
    DateTime utcDateTime;
    
    if (timestamp == null) {
      return DateTime.now();
    }
    
    // Handle Firestore Timestamp
    if (timestamp.runtimeType.toString().contains('Timestamp')) {
      utcDateTime = (timestamp as dynamic).toDate().toUtc();
    }
    // Handle DateTime
    else if (timestamp is DateTime) {
      utcDateTime = timestamp.toUtc();
    }
    // Handle ISO string
    else if (timestamp is String) {
      utcDateTime = DateTime.parse(timestamp).toUtc();
    }
    // Handle milliseconds since epoch
    else if (timestamp is int) {
      utcDateTime = DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true);
    }
    else {
      return DateTime.now();
    }
    
    return utcToLocal(utcDateTime, timezone);
  }

  /// Format time for display (12-hour format with AM/PM)
  static String formatTime12Hour(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }

  /// Format time for display (24-hour format)
  static String formatTime24Hour(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime);
  }

  /// Format date for display
  static String formatDate(DateTime dateTime, {String format = 'dd MMM yyyy'}) {
    return DateFormat(format).format(dateTime);
  }

  /// Format date and time for display
  static String formatDateTime(DateTime dateTime, {String format = 'dd MMM yyyy h:mm a'}) {
    return DateFormat(format).format(dateTime);
  }

  /// Check if a timezone is within business hours
  /// 
  /// Example:
  /// ```dart
  /// bool isOpen = TimezoneHelper.isWithinBusinessHours(
  ///   'Australia/Sydney',
  ///   openHour: 9,
  ///   closeHour: 17
  /// );
  /// ```
  static bool isWithinBusinessHours(
    String timezone, {
    int openHour = 9,
    int closeHour = 17,
  }) {
    final now = nowInTimezone(timezone);
    return now.hour >= openHour && now.hour < closeHour;
  }

  /// Get friendly timezone label
  static String getTimezoneLabel(String timezone) {
    return commonTimezones[timezone] ?? timezone;
  }

  /// Validate if a timezone string is supported
  static bool isValidTimezone(String timezone) {
    return commonTimezones.containsKey(timezone);
  }
}

/// Extension on DateTime for easy timezone conversion
extension DateTimeTimezoneExtension on DateTime {
  /// Convert this DateTime to a specific timezone
  DateTime toTimezone(String timezone) {
    return TimezoneHelper.utcToLocal(toUtc(), timezone);
  }

  /// Format this DateTime in a specific timezone
  String formatIn(String timezone, String format) {
    return TimezoneHelper.formatInTimezone(this, timezone, format);
  }
}
