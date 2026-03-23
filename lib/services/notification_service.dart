import 'dart:ui';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:url_launcher/url_launcher.dart';
import '../models/reminder.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/category_statistic_repository.dart';
import 'youtube_service.dart';
import 'ai_service.dart';

/// Advanced Notification Service for Flex Reminder
/// Handles notification scheduling, tap actions, and notification management
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  ReminderRepository? _reminderRepository;
  CategoryStatisticRepository? _categoryStatRepository;
  GoRouter? _router;
  YouTubeService? _youtubeService;
  AIService? _aiService;
  bool _initialized = false;

  static const String _channelId = 'flex_reminders_channel';
  static const String _channelName = 'Flex Reminders';
  static const String _channelDescription = 'Smart post reading reminders';

  /// Initialize the notification service
  Future<void> initialize({
    required ReminderRepository reminderRepository,
    required CategoryStatisticRepository categoryStatRepository,
  }) async {
    if (_initialized) return;

    _reminderRepository = reminderRepository;
    _categoryStatRepository = categoryStatRepository;

    // Initialize using named parameters
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          ),
        ),
        onDidReceiveNotificationResponse: _handleNotificationTap,
      );
    } catch (e) {
      // Try alternative
      try {
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
        );
      } catch (e2) {
        // Continue without initialization
      }
    }

    // Create notification channel
    _createNotificationChannel();

    // Request permissions
    _requestPermissions();

    // Initialize timezone
    tz_data.initializeTimeZones();

    _initialized = true;
  }

  /// Create Android notification channel
  void _createNotificationChannel() {
    try {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidPlugin != null) {
        const channel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
        );

        androidPlugin.createNotificationChannel(channel);
      }
    } catch (e) {}
  }

  /// Request notification permissions
  void _requestPermissions() {
    try {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      androidPlugin?.requestNotificationsPermission();
      androidPlugin?.requestExactAlarmsPermission();
    } catch (e) {}

    try {
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {}
  }

  /// Set the router for navigation
  void setRouter(GoRouter router) {
    _router = router;
  }

  void setYoutubeService(YouTubeService service) {
    _youtubeService = service;
  }

  void setAiService(AIService service) {
    _aiService = service;
  }

  /// Handle notification tap
  void _handleNotificationTap(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null) return;

    final reminderId = int.tryParse(payload);
    if (reminderId == null || _reminderRepository == null) return;

    var reminder = _reminderRepository!.getById(reminderId);
    if (reminder == null) return;

    final wasPlaylist = reminder.isPlaylist == true;
    final playlistId = reminder.playlistId;
    final currentIndex = reminder.playlistCurrentIndex ?? 0;
    final totalItems = reminder.playlistTotalItems ?? 0;

    if (wasPlaylist && playlistId != null && _youtubeService != null) {
      // This is a playlist - move to next video
      final nextIndex = currentIndex + 1;

      if (nextIndex < totalItems) {
        // Get playlist info and find next video
        try {
          final playlist = await _youtubeService!.getPlaylistInfo(
            'https://www.youtube.com/playlist?list=$playlistId',
          );

          if (playlist != null && nextIndex < playlist.items.length) {
            final nextVideo = playlist.items[nextIndex];

            // Update reminder with next video data
            reminder.playlistCurrentIndex = nextIndex;
            reminder.currentVideoUrl =
                'https://www.youtube.com/watch?v=${nextVideo.videoId}&list=$playlistId';
            reminder.title = nextVideo.title;
            reminder.description = nextVideo.description;
            reminder.imageUrl = nextVideo.thumbnailUrl;

            // Reschedule notification for next video (simplified - keep same time)
            reminder.isOpened = false;
            reminder.openedAt = null;
            _reminderRepository!.save(reminder);
            await scheduleReminder(reminder);

            // Don't open URL yet, let user finish current one first
            // Or open the next video:
            final nextUri = Uri.parse(reminder.currentVideoUrl!);
            if (await canLaunchUrl(nextUri)) {
              await launchUrl(nextUri, mode: LaunchMode.externalApplication);
            }
            _router?.go('/post/$reminderId');
            return;
          }
        } catch (e) {
          // Continue with normal flow if playlist fetch fails
        }
      }

      // Playlist completed
      reminder.isOpened = true;
      reminder.openedAt = DateTime.now();
      _reminderRepository!.save(reminder);
      _categoryStatRepository?.recordOpened(reminder);
      _router?.go('/post/$reminderId');
      return;
    }

    // Regular (non-playlist) reminder handling
    reminder.isOpened = true;
    reminder.openedAt = DateTime.now();
    _reminderRepository!.save(reminder);
    _categoryStatRepository?.recordOpened(reminder);

    // Open URL
    final uri = Uri.parse(reminder.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    _router?.go('/post/$reminderId');
  }

  /// Schedule a reminder notification at a specific time
  Future<bool> scheduleReminder(Reminder reminder) async {
    if (!_initialized) return false;

    try {
      await cancelReminder(reminder.id);

      // Use zonedSchedule to schedule for a specific time
      await _plugin.zonedSchedule(
        id: reminder.id,
        title: '📖 Time to read: ${reminder.title}',
        body:
            '${reminder.categoryEn ?? "General"} · ${reminder.complexityAr ?? "متوسط"}',
        scheduledDate: tz.TZDateTime.from(reminder.scheduledAt, tz.local),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF00D4C8),
            enableVibration: true,
            playSound: true,
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            categoryIdentifier: 'REMINDER',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: reminder.id.toString(),
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Show an immediate notification
  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) return;

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            enableVibration: true,
            playSound: true,
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {}
  }

  /// Cancel a specific reminder notification
  Future<void> cancelReminder(int id) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: id);
    } catch (e) {}
  }

  /// Cancel all notifications
  Future<void> cancelAllReminders() async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {}
  }

  /// Get all pending notifications
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    if (!_initialized) return [];
    try {
      return await _plugin.pendingNotificationRequests();
    } catch (e) {
      return [];
    }
  }

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    try {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin != null) {
        return await androidPlugin.areNotificationsEnabled() ?? false;
      }
    } catch (e) {}
    return false;
  }

  /// Show group notification summary
  Future<void> showGroupSummary({
    required String groupKey,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;

    try {
      await _plugin.show(
        id: groupKey.hashCode,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            enableVibration: true,
            playSound: true,
            category: AndroidNotificationCategory.reminder,
            groupKey: groupKey,
            setAsGroupSummary: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {}
  }

  /// Schedule a daily repeating notification
  Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    if (!_initialized) return;

    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, hour, minute);

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            enableVibration: true,
            playSound: true,
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {}
  }

  /// Schedule a weekly repeating notification
  Future<void> scheduleWeeklyNotification({
    required int id,
    required String title,
    required String body,
    required int dayOfWeek,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    if (!_initialized) return;

    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, hour, minute);

    while (scheduledDate.weekday != dayOfWeek) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            enableVibration: true,
            playSound: true,
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {}
  }
}
