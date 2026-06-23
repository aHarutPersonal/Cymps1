import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Service for scheduling local notifications (daily reminders).
class NotificationService {
  static const _channelId = 'cmpys_daily_reminder';
  static const _channelName = 'Daily Reminder';
  static const _prefsKeyEnabled = 'notifications_enabled';
  static const _prefsKeyHour = 'notifications_hour';
  static const _prefsKeyMinute = 'notifications_minute';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize the notification plugin and timezone data. Call once at app startup.
  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// Request notification permissions. Returns true if granted.
  Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final result = await _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return result ?? false;
    }
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final result = await androidPlugin?.requestNotificationsPermission();
      return result ?? false;
    }
    return false;
  }

  /// Schedule a daily recurring notification at [hour]:[minute].
  /// Defaults to 9:00 AM if not specified.
  Future<void> scheduleDailyReminder({
    int hour = 9,
    int minute = 0,
    String? title,
    String? body,
  }) async {
    await initialize();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final scheduled = _nextInstanceOfTime(hour, minute);

    await _plugin.zonedSchedule(
      0,
      title ?? 'Your daily focus awaits',
      body ?? 'Open CMPYS to check today\'s task and keep your streak going.',
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, true);
    await prefs.setInt(_prefsKeyHour, hour);
    await prefs.setInt(_prefsKeyMinute, minute);
  }

  /// Cancel the daily reminder.
  Future<void> cancelDailyReminder() async {
    await _plugin.cancel(0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, false);
  }

  /// Get current notification settings.
  Future<NotificationSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationSettings(
      enabled: prefs.getBool(_prefsKeyEnabled) ?? false,
      hour: prefs.getInt(_prefsKeyHour) ?? 9,
      minute: prefs.getInt(_prefsKeyMinute) ?? 0,
    );
  }

  /// Check if notifications are enabled.
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyEnabled) ?? false;
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}

/// Stored notification settings.
class NotificationSettings {
  const NotificationSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  final bool enabled;
  final int hour;
  final int minute;

  String get timeString {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}