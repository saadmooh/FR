# Feature: Home Screen Widget

## Overview

Android home screen widget displaying upcoming reminders. Allows users to see their reading schedule without opening the app.

## User Experience

### Widget Sizes
- **Small (2x1)**: Next reminder only
- **Medium (4x2)**: Next 3 reminders
- **Large (4x4)**: Next 6 reminders with details

### Widget UI
```
┌─────────────────────────┐
│ Flex Reminder           │
├─────────────────────────┤
│ 🔵 Work Article         │
│    Today, 9:00 AM       │
│                         │
│ 🟠 Tech News            │
│    Tomorrow, 7:00 PM    │
│                         │
│ 🟢 Tutorial             │
│    Mar 21, 2:00 PM      │
└─────────────────────────┘
```

## Implementation Guide

### 1. Create Widget Provider

Create `android/app/src/main/kotlin/.../FlexReminderWidget.kt`:

```kotlin
package com.example.myapp

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class FlexReminderWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val views = RemoteViews(context.packageName, R.layout.widget_reminder)
            
            // Get next reminders from shared prefs
            val nextReminders = widgetData.getString("next_reminders", "[]")
            
            // Update widget UI
            views.setTextViewText(R.id.widget_title, "Flex Reminder")
            views.setTextViewText(R.id.reminder_1, "Next: Reading time!")
            
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
```

### 2. Create Widget Layout

Create `android/app/src/main/res/layout/widget_reminder.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp"
    android:background="@drawable/widget_background">

    <TextView
        android:id="@+id/widget_title"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Flex Reminder"
        android:textSize="16sp"
        android:textStyle="bold"
        android:textColor="@color/accent"/>

    <TextView
        android:id="@+id/reminder_1"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="8dp"
        android:textSize="14sp"/>

    <TextView
        android:id="@+id/reminder_2"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="4dp"
        android:textSize="14sp"/>

    <TextView
        android:id="@+id/reminder_3"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="4dp"
        android:textSize="14sp"/>

</LinearLayout>
```

### 3. Register Widget in AndroidManifest

```xml
<receiver
    android:name=".FlexReminderWidget"
    android:exported="true">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
    </intent-filter>
    <meta-data
        android:name="android.appwidget.provider"
        android:resource="@xml/widget_reminder_info"/>
</receiver>
```

### 4. Create Widget Info

Create `android/app/src/main/res/xml/widget_reminder_info.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="180dp"
    android:minHeight="110dp"
    android:targetCellWidth="3"
    android:targetCellHeight="2"
    android:updatePeriodMillis="1800000"
    android:initialLayout="@layout/widget_reminder"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"/>
```

### 5. Update Widget from Flutter

Create `lib/services/widget_service.dart`:

```dart
import 'package:home_widget/home_widget.dart';
import 'dart:convert';

class WidgetService {
  static const String appGroupId = 'group.com.example.myapp';
  
  Future<void> updateWidget() async {
    // Get next reminders
    final reminders = reminderRepository.getPendingReminders().take(6).toList();
    
    // Convert to JSON
    final remindersJson = reminders.map((r) => {
      'title': r.title,
      'time': r.scheduledAt.toIso8601String(),
      'category': r.categoryEn,
    }).toList();
    
    // Save to widget storage
    await HomeWidget.saveWidgetData<String>(
      'next_reminders',
      jsonEncode(remindersJson),
    );
    
    // Trigger widget update
    await HomeWidget.updateWidget(
      androidName: 'FlexReminderWidget',
    );
  }
  
  Future<void> updateOnReminderChange() async {
    await updateWidget();
  }
}
```

### 6. Integrate with Repository

```dart
// In reminder_repository.dart, add listener
void save(Reminder reminder) {
  _box.put(reminder);
  widgetService.updateWidget();  // Add this
}

void delete(int id) {
  _box.remove(id);
  widgetService.updateWidget();  // Add this
}
```

### 7. Add home_widget Package

```bash
flutter pub add home_widget
```

## Dependencies

```yaml
dependencies:
  home_widget: ^0.4.0
```

## Testing Checklist

- [ ] Widget appears in widget picker
- [ ] Widget displays correctly
- [ ] Widget updates on reminder change
- [ ] Widget handles empty state
- [ ] Widget responds to tap (opens app)
- [ ] Different sizes render correctly
