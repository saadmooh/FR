# Feature: Push Notification Channels

## Overview

Organizes notifications by category into separate Android notification channels. Users can customize notification preferences per category.

## User Experience

### Channel Groups
| Channel | Description | Default |
|---------|-------------|---------|
| High Priority | Urgent reminders | Sound + Vibration |
| Daily Reading | Normal reminders | Sound |
| Weekly Digest | Summary notifications | Silent |
| System | App updates, tips | Silent |

### Notification Example
```
┌─────────────────────────────────────────┐
│ 📚 Work        Flex Reminder            │
│ Article: How to improve...              │
│ Today, 9:00 AM                    [📖] │
└─────────────────────────────────────────┘
```

## Implementation Guide

### 1. Update NotificationService

Update `lib/services/notification_service.dart`:

```dart
class NotificationService {
  // Channel IDs
  static const String channelHighPriority = 'high_priority';
  static const String channelDailyReading = 'daily_reading';
  static const String channelWeeklyDigest = 'weekly_digest';
  static const String channelSystem = 'system';
  
  Future<void> initialize(...) async {
    // ... existing initialization ...
    
    // Create notification channels
    await _createNotificationChannels();
  }
  
  Future<void> _createNotificationChannels() async {
    final android = _getAndroidPlugin();
    
    await android
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            channelHighPriority,
            'High Priority',
            description: 'Urgent and important reminders',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );
    
    await android
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            channelDailyReading,
            'Daily Reading',
            description: 'Regular reading reminders',
            importance: Importance.defaultImportance,
            playSound: true,
            enableVibration: false,
          ),
        );
    
    await android
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            channelWeeklyDigest,
            'Weekly Digest',
            description: 'Weekly summary notifications',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
          ),
        );
  }
  
  String _getChannelId(Reminder reminder) {
    // Route to appropriate channel based on category/complexity
    if (reminder.importance == 'day' && 
        (reminder.complexityEn == 'High' || reminder.complexityEn == 'Medium')) {
      return channelHighPriority;
    }
    return channelDailyReading;
  }
  
  Future<void> scheduleReminder(Reminder reminder) async {
    final channelId = _getChannelId(reminder);
    
    await flutterLocalNotificationsPlugin.zonedSchedule(
      reminder.id,
      reminder.title,
      reminder.description ?? 'Time to read!',
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _getChannelName(channelId),
          channelDescription: _getChannelDescription(channelId),
          importance: _getChannelImportance(channelId),
          priority: _getChannelPriority(channelId),
          category: AndroidNotificationCategory.reminder,
          icon: '@mipmap/ic_notification',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
  
  String _getChannelName(String channelId) {
    switch (channelId) {
      case channelHighPriority:
        return 'High Priority';
      case channelDailyReading:
        return 'Daily Reading';
      case channelWeeklyDigest:
        return 'Weekly Digest';
      case channelSystem:
        return 'System';
      default:
        return 'Reminders';
    }
  }
  
  Importance _getChannelImportance(String channelId) {
    switch (channelId) {
      case channelHighPriority:
        return Importance.high;
      case channelDailyReading:
        return Importance.defaultImportance;
      default:
        return Importance.low;
    }
  }
  
  Priority _getChannelPriority(String channelId) {
    switch (channelId) {
      case channelHighPriority:
        return Priority.high;
      case channelDailyReading:
        return Priority.defaultPriority;
      default:
        return Priority.low;
    }
  }
}
```

### 2. Create Notification Settings Screen

Create `lib/screens/notification_settings_screen.dart`:

```dart
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  Map<String, bool> _channelEnabled = {};
  Map<String, String> _channelSound = {};

  @override
  void initState() {
    super.initState();
    _loadChannelSettings();
  }

  void _loadChannelSettings() {
    // Load from shared preferences
    _channelEnabled = {
      NotificationService.channelHighPriority: true,
      NotificationService.channelDailyReading: true,
      NotificationService.channelWeeklyDigest: false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.notificationSettings),
      ),
      body: ListView(
        children: [
          _buildChannelTile(
            NotificationService.channelHighPriority,
            'High Priority',
            'Urgent reminders with sound and vibration',
            Icons.notifications_active,
          ),
          _buildChannelTile(
            NotificationService.channelDailyReading,
            'Daily Reading',
            'Regular reminders',
            Icons.notifications,
          ),
          _buildChannelTile(
            NotificationService.channelWeeklyDigest,
            'Weekly Digest',
            'Weekly summary (silent)',
            Icons.summarize,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.open_in_app),
            title: Text(t.openSystemSettings),
            subtitle: Text(t.customizePerChannel),
            onTap: _openSystemSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildChannelTile(
    String channelId,
    String title,
    String subtitle,
    IconData icon,
  ) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: _channelEnabled[channelId] ?? true,
      onChanged: (value) async {
        setState(() {
          _channelEnabled[channelId] = value;
        });
        await _saveChannelSetting(channelId, value);
      },
    );
  }

  Future<void> _saveChannelSetting(String channelId, bool enabled) async {
    await settingsRepository.setChannelEnabled(channelId, enabled);
  }

  void _openSystemSettings() {
    // Open Android notification settings
    // notificationService.openSystemSettings();
  }
}
```

### 3. Add Translations

```dart
String get notificationSettings => 'Notification Settings';
String get openSystemSettings => 'Open System Settings';
String get customizePerChannel => 'Customize each channel in system settings';
```

## Testing Checklist

- [ ] Channels created on app start
- [ ] Reminders route to correct channel
- [ ] Channel settings persist
- [ ] System settings accessible
- [ ] Sound/vibration per channel
