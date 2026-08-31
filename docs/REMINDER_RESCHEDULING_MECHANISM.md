# آلية إعادة جدولة التذكيرات - Flex Reminder

## نظرة عامة

نظام Flex Reminder يستخدم آلية إعادة جدولة ذكية ومتعددة الطبقات للتذكيرات التي لم يتم فتحها في وقتها المحدد. يتم إعادة الجدولة عبر **موقعين مختلفين** يعملان بتنسيق لضمان الموثوقية:

1. **OverdueReminderService** - يعمل عند **فتح التطبيق/العودة للواجهة** (Foreground)
2. **WorkManager Background Task** - يعمل **عند إغلاق التطبيق/الخلفية** (Background)

---

## البنية المعمارية

```
┌─────────────────────────────────────────────────────────────────┐
│                      APP FOREGROUND                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  OverdueReminderService.reviewOverdueReminders()         │   │
│  │  • يتم استدعاؤه عند:                                     │   │
│  │    - تشغيل التطبيق (main.dart:268)                       │   │
│  │    - العودة للواجهة (AppLifecycleState.resumed)           │   │
│  │  • يفحص جميع التذكيرات غير المقروءة (getAllUnread)       │   │
│  │  • يعيد جدولة المتأخر منها (scheduledAt < now)           │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      APP BACKGROUND                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  WorkManager callbackDispatcher → _workmanagerCallback  │   │
│  │  • مهمة: reminder_monitoring_task                        │   │
│  │  • يتم جدولة عمل WorkManager لكل تذكير                  │   │
│  │  • يعمل في isolate منفصل (background isolate)           │   │
│  │  • يراقب التذكير بعد وقته بـ 1 دقيقة                    │   │
│  │  • يعيد جدولة التذكير إذا لم يفتح                      │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 1. OverdueReminderService - عند فتح التطبيق

### الملف: `lib/services/overdue_reminder_service.dart`

### متى يتم التفعيل:

| الحدث | الموقع | السطر |
|---------|--------|------|
| تشغيل التطبيق | `main.dart` | 268 |
| العودة للواجهة (resume) | `main.dart` | 415-416, 430-440 |

### الخوارزمية:

```dart
Future<int> reviewOverdueReminders() async {
  // 1. منع المعالجة المتكررة
  if (_isProcessing) return 0;
  if (_lastProcessedTime != null && 
      now.difference(_lastProcessedTime!) < 5.seconds) return 0;

  // 2. جلب جميع التذكيرات غير المقروءة
  final allUnread = _reminderRepository.getAllUnread();
  
  // 3. تصفية المتأخر منها
  final overdueReminders = allUnread
      .where((r) => r.scheduledAt.isBefore(currentTime))
      .toList();

  // 4. إعادة جدولة كل تذكير متأخر
  for (final reminder in overdueReminders) {
    await _rescheduleOverdueReminder(reminder, currentTime);
  }
}
```

### _rescheduleOverdueReminder - التفاصيل:

```dart
Future<bool> _rescheduleOverdueReminder(Reminder reminder, DateTime currentTime) async {
  // 1. فحص الحد الأقصى لمحاولات إعادة الجدولة
  final maxReschedules = _getMaxReschedules(reminder.importance);
  if (reminder.rescheduleAttempts >= maxReschedules) return false;

  // 2. فحص إذا كان التذكير قديم جداً (>30 يوم)
  if (reminder.scheduledAt.isBefore(currentTime.subtract(30.days))) return false;

  // 3. جلب تاريخ المحاولات السابقة
  final previousAttempts = reminderRepo.getReminderHistory(reminder.id)
      .map((r) => {
        'scheduled_at': r.scheduledAt.toIso8601String(),
        'opened': r.isOpened,
        'opened_at': r.openedAt?.toIso8601String(),
      }).toList();

  // 4. جلب أوقات الفراغ الخاصة بالمستخدم
  final freeTimes = freeTimeRepo.getAllAsJson();

  // 5. Race Guard - منع التداخل مع WorkManager
  final lockKey = 'rescheduling_lock_${reminder.id}';
  final lockTimestamp = prefs.getInt(lockKey) ?? 0;
  if (nowMs - lockTimestamp < 60000) return false; // قفل نشط
  await prefs.setInt(lockKey, nowMs); // اكتساب القفل

  // 6. استدعاء AI لإعادة الجدولة
  final result = await _aiService.reschedulePost(
    previousAttemptsJson: jsonEncode(previousAttempts),
    category: reminder.categoryEn ?? 'Other',
    complexity: reminder.complexityEn ?? 'Medium',
    importance: reminder.importance,
    userFreeTimesJson: freeTimes.isNotEmpty ? '{"free_times": $freeTimes}' : null,
    currentTime: currentTime,
  );

  // 7. التحقق من الوقت الجديد
  final newTime = result['newTime'] as DateTime?;
  if (newTime == null || !newTime.isAfter(currentTime)) {
    // Fallback: إضافة ساعة للوقت الحالي
    reminder.scheduledAt = currentTime.add(1.hour);
  } else {
    reminder.scheduledAt = newTime;
  }

  // 8. تحديث حقول التذكير
  reminder.rescheduleAttempts++;
  reminder.aiExplanation = reasonParts[0];
  reminder.aiExplanationAr = reasonParts[1] ?? '';
  reminder.isOpened = false;
  reminder.openedAt = null;

  // 9. الحفظ وتحديث الإشعار
  _reminderRepository.save(reminder);
  await _notificationService.cancelReminder(reminder.id);
  await _notificationService.scheduleReminder(reminder);

  // 10. تحرير القفل
  await prefs.remove(lockKey);
  return true;
}
```

### حدود إعادة الجدولة حسب الأهمية:

```dart
int _getMaxReschedules(String importance) {
  switch (importance) {
    case 'Day':   return 1;  // يوم واحد = محاولة واحدة
    case 'Week':  return 2;  // أسبوع = محاولتان
    case 'Month': return 3;  // شهر = ثلاث محاولات
    default:      return 2;
  }
}
```

---

## 2. WorkManager Background Task - عند إغلاق التطبيق

### الملف: `lib/services/workmanager_service.dart`

### آلية العمل:

```dart
// في NotificationService.scheduleReminder() - السطر 298
Future<void> _scheduleMonitoringWorkManager(Reminder reminder) async {
  // 1. إلغاء أي مهمة سابقة لهذا التذكير
  await Workmanager().cancelByTag('reminder_${reminder.id}');

  // 2. إعداد البيانات للمهمة
  final inputData = <String, String>{
    'reminderId': reminder.id.toString(),
    'provider': _provider,      // 'google' أو 'openrouter'
  };
  if (_storeDirectoryPath != null) inputData['storeDirectory'] = _storeDirectoryPath!;
  if (_apiKey != null && _apiKey!.isNotEmpty) inputData['apiKey'] = _apiKey!;
  if (_model.isNotEmpty) inputData['model'] = _model;

// 3. حساب التأخير: وقت التذكير + دقيقة واحدة
   var monitoringDelay = reminder.scheduledAt.difference(now) + 1.minute;

   // 4. الحد الأدنى 15 دقيقة
   // لماذا 15 دقيقة؟ - الصيغة الأساسية هي scheduledAt + 1 دقيقة،
   // لكن إذا كان التأخير أقل من 15 دقيقة (مثلاً التذكير بعد دقائق)،
   // يتم رفعه إلى 15 دقيقة لضمان استقرار مهمة WorkManager
   // ووقت كافٍ لتنفيذ العمليات في الـ background isolate.
   if (monitoringDelay < 15.minutes) monitoringDelay = 15.minutes;

   // مثال:
   // - التذكير بعد 30 دقيقة → تأخير = 30 + 1 = 31 دقيقة (لا تغيير)
   // - التذكير بعد 5 دقائق → تأخير = 5 + 1 = 6 دقائق → يُرفع إلى 15 دقيقة
   // - التذكير بعد ساعة → تأخير = 60 + 1 = 61 دقيقة (لا تغيير)

   // 5. تسجيل المهمة
  await Workmanager().registerOneOffTask(
    'reminder_monitoring_${reminder.id}',
    _monitoringTaskName,  // 'reminder_monitoring_task'
    initialDelay: monitoringDelay,
    inputData: inputData,
    tag: 'reminder_${reminder.id}',
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
}
```

### شرح التأخير بين إطلاق التذكير والفحص:

| العنصر | القيمة | الوصف |
|---------|--------|-------|
| **الصيغة الأساسية** | `scheduledAt + 1 دقيقة` | الفحص يبدأ بعد دقيقة واحدة من وقت التذكير المجدول |
| **الحد الأدنى** | `15 دقيقة` | إذا كان الناتج أقل من 15 دقيقة، يُرفع تلقائياً إلى 15 دقيقة |
| **لا يوجد حد أقصى** | — | إذا كان التأخير أكبر من 15 دقيقة، يُستخدم القيمة الحقيقية |

**لماذا 15 دقيقة حد أدنى؟**
- لضمان استقرار مهمة WorkManager في الخلفية
- لمنع تشغيل المهمة بسرعة كبيرة قبل أوانها
- لإعطاء وقت كافٍ لتنفيذ العمليات في الـ background isolate

**أمثلة:**

| وقت التذكير | التأخير المحسوب | التأخير الفعلي |
|-------------|----------------|---------------|
| بعد 30 دقيقة | 31 دقيقة | 31 دقيقة ✅ |
| بعد 5 دقائق | 6 دقائق | **15 دقيقة** ⬆️ |
| بعد ساعة | 61 دقيقة | 61 دقيقة ✅ |
| بعد دقيقتين | 3 دقائق | **15 دقيقة** ⬆️ |

---

### ما يحدث في الـ Callback (السطر 286-640):

```dart
@pragma('vm:entry-point')
Future<void> _workmanagerCallback() async {
  Workmanager().executeTask((taskName, inputData) async {
    // 1. استخراج البيانات
    final reminderId = int.tryParse(inputData?['reminderId']);
    final storeDirectoryPath = inputData?['storeDirectory'];
    final apiKey = inputData?['apiKey'];
    final provider = inputData?['provider'] ?? 'google';
    final model = inputData?['model'] ?? '';

    // 2. تهيئة الخدمات في الـ background isolate
    await _initBackgroundServices();  // Firebase + Supabase
    tz_data.initializeTimeZones();
    
    // 3. إنشاء AIService
    final aiService = await _createAIService(apiKey, provider, model);
    
    // 4. تهيئة الإشعارات
    await _initNotificationsInBackground();
    
    // 5. فتح قاعدة البيانات
    final store = await _openStoreInBackground(storeDirectoryPath);
    final reminderRepo = ReminderRepository(store);
    final freeTimeRepo = FreeTimeRepository(store);

    // 6. جلب التذكير
    final reminder = reminderRepo.getById(reminderId);
    if (reminder == null || reminder.isOpened) return true;

    // 7. نفس فحوصات OverdueReminderService
    // - max reschedules
    // - عمر التذكير (>30 يوم)
    // - Race Guard

    // 8. استدعاء AI
    final rawResponse = await aiService.reschedulePostRaw(
      previousAttemptsJson: jsonEncode(previousAttempts),
      category: reminder.categoryEn ?? 'Other',
      complexity: reminder.complexityEn ?? 'Medium',
      importance: reminder.importance,
      userFreeTimesJson: freeTimesJson,
      currentTime: DateTime.now(),
    );

    // 9. تحليل الرد
    final aiResult = _parseAiRescheduleResponse(rawResponse);
    final newTime = aiResult['newTime'] as DateTime?;

    // 10. تحديث التذكير
    reminder.scheduledAt = newTime;
    reminder.rescheduleAttempts++;
    reminder.aiExplanation = reasonParts[0];
    reminder.aiExplanationAr = reasonParts[1] ?? '';
    reminder.isOpened = false;
    reminder.openedAt = null;
    reminderRepo.save(reminder);

    // 11. جدولة إشعار جديد
    await plugin.zonedSchedule(
      id: reminderId,
      title: ' Time to read: ${reminder.title}',
      body: '${reminder.categoryEn} · ${reminder.complexityAr}',
      scheduledDate: tz.TZDateTime.from(reminder.scheduledAt, tz.local),
      // ... إعدادات الإشعار
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: reminderId.toString(),
    );

    // 12. جدولة مهمة مراقبة قادمة
    await Workmanager().registerOneOffTask(
      'reminder_monitoring_$reminderId',
      _monitoringTaskName,
      initialDelay: nextDelay,  // newTime - now + 1 minute
      inputData: nextInputData,
      tag: 'reminder_$reminderId',
    );

    // 13. إشعار للمستخدم "تم إعادة الجدولة"
    await plugin.show(
      id: reminderId + 1000000,
      title: 'Reminder Rescheduled',
      body: '${reminder.title}\nNew time: $formattedTime\n${reminder.aiExplanation}',
    );

    // 14. تحرير القفل
    await prefs.remove('rescheduling_lock_$reminderId');
    return true;
  });
}
```

---

## 3. استدعاء AI لإعادة الجدولة

### الملف: `lib/services/ai_service.dart` - دالتان:

#### `reschedulePost()` - للإستخدام من Foreground (ترجع Map)
#### `reschedulePostRaw()` - للإستخدام من Background (ترجع String خام)

### البرومبت المرسل للـ AI:

```dart
final userPrompt = '''
Reschedule this unread post. Find a better time based on why previous attempts failed.

Category: $category
Complexity: $complexity
Importance window: $importance (Day = within 1 day, Week = within 7 days, Month = within 30 days)
Current time: ${currentTime.toIso8601String()}
Deadline: ${maxTime.toIso8601String()}
Previous scheduled attempts (all missed): $previousAttemptsJson
User free times: ${userFreeTimesJson ?? '[]'}

Rules (apply in this priority order):
1. Time MUST be after ${currentTime.toIso8601String()}
2. Time MUST be before ${maxTime.toIso8601String()}
3. Choose a time that avoids patterns from failed attempts (different hour, different day)
4. Prefer times within user free slots
5. For complex content, prefer morning focus hours

Return only:
{"new_time": "YYYY-MM-DD HH:MM:SS", "reason": "Reason in English | السبب بالعربية"}
''';
```

### ما يتم إرساله للـ AI:

| المعامل | الوصف | مثال |
|-----------|---------|------|
| `previousAttemptsJson` | JSON array للمحاولات السابقة | `[{"scheduled_at":"2024-01-15T10:00:00","opened":false}]` |
| `category` | الفئة بالإنجليزية | "Productivity" |
| `complexity` | مستوى التعقيد | "Medium" |
| `importance` | نافذة الأهمية | "Day" / "Week" / "Month" |
| `userFreeTimesJson` | أوقات فراغ المستخدم | `{"free_times": [{"day":1,"start":"09:00","end":"11:00"}]}` |
| `currentTime` | الوقت الحالي | `2024-01-15T14:30:00.000Z` |

### ما يتوقعه الـ AI كرد:

```json
{
  "new_time": "2024-01-15 16:30:00",
  "reason": "User typically reads productivity content in late afternoon | المستخدم يقرأ محتوى الإنتاجية عادة في فترة ما بعد الظهر"
}
```

### حساب الموعد النهائي (Deadline) حسب الأهمية:

```dart
DateTime maxTime;
switch (importance) {
  case 'Day':   maxTime = currentTime.add(1.day);   break;
  case 'Week':  maxTime = currentTime.add(7.days);  break;
  case 'Month': maxTime = currentTime.add(30.days); break;
  default:      maxTime = currentTime.add(7.days);
}
```

---

## 4. Race Guard - منع التداخل

يتم استخدام `SharedPreferences` كآلية قفل موزعة:

```dart
// مفتاح القفل
final rescheduleLockKey = 'rescheduling_lock_$reminderId';

// التحقق من القفل (ينتهي بعد 60 ثانية)
final lockTimestamp = prefs.getInt(rescheduleLockKey) ?? 0;
final nowMs = DateTime.now().millisecondsSinceEpoch;
if (nowMs - lockTimestamp < 60000) {
  // قفل نشط - تخطي
  return false;
}

// اكتساب القفل
await prefs.setInt(rescheduleLockKey, nowMs);

try {
  // ... عملية إعادة الجدولة
} finally {
  // تحرير القفل دائماً
  await prefs.remove(rescheduling_lock_$reminderId);
}
```

**متى يعمل Race Guard:**
- WorkManager يعمل في الخلفية ويحاول إعادة جدولة
- التطبيق يفتح في نفس الوقت ويحاول OverdueReminderService إعادة جدولة
- أحدهما يكتسب القفل، الآخر يتخطى

---

## 5. تحديث الإشعار بعد إعادة الجدولة

### في Foreground (OverdueReminderService):
```dart
await _notificationService.cancelReminder(reminder.id);
await _notificationService.scheduleReminder(reminder);
```

### في Background (WorkManager):
```dart
// إلغاء الإشعار القديم وجدولة جديد
await plugin.zonedSchedule(
  id: reminderId,
  title: ' Time to read: ${reminder.title}',
  body: '${reminder.categoryEn} · ${reminder.complexityAr}',
  scheduledDate: tz.TZDateTime.from(reminder.scheduledAt, tz.local),
  androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  payload: reminderId.toString(),
);

// إشعار إضافي "تم إعادة الجدولة"
await plugin.show(
  id: reminderId + 1000000,
  title: 'Reminder Rescheduled',
  body: '${reminder.title}\nNew time: $formattedTime\n${reminder.aiExplanation}',
);
```

---

## 6. حقول التذكير ذات الصلة (Reminder Model)

### الملف: `lib/models/reminder.dart`

```dart
@Entity()
class Reminder {
  @Id() int id = 0;
  
  // ... حقول أخرى ...
  
  @Property(type: PropertyType.date)
  DateTime scheduledAt;        // وقت التذكير المجدول
  
  @Property(type: PropertyType.date)
  DateTime createdAt;          // وقت الإنشاء
  
  @Property(type: PropertyType.date)
  DateTime? openedAt;          // وقت الفتح (null إذا لم يفتح)
  
  bool isOpened = false;       // هل تم فتحه؟
  
  int rescheduleAttempts = 0;  // عدد محاولات إعادة الجدولة
  
  String? aiExplanation;       // شرح AI بالإنجليزية
  String? aiExplanationAr;     // شرح AI بالعربية
  String? aiExplanationFr;     // شرح AI بالفرنسية
  
  String importance;           // 'Day' | 'Week' | 'Month'
}
```

---

## 7. تدفق البيانات الكامل

### سيناريو 1: التطبيق مفتوح، وقت التذكير يمر

```
Time: 10:00 AM - Reminder scheduled for 10:00 AM
         │
         ▼
┌────────────────────────────────────────┐
│  المستخدم لا يفتح الإشعار              │
└────────────────────────────────────────┘
         │
         ▼
Time: 10:01 AM - WorkManager task triggers (monitoringDelay = 1 min)
         │
         ▼
┌────────────────────────────────────────┐
│  WorkManager callback                  │
│  • يفحص التذكير                        │
│  • يجد isOpened = false                │
│  • يستدعي AI لإعادة الجدولة           │
│  • يحدث scheduledAt                    │
│  • يحدث الإشعار                        │
│  • يسجل مهمة مراقبة جديدة              │
└────────────────────────────────────────┘
```

### سيناريو 2: التطبيق مغلق، يفتح لاحقاً

```
Time: 10:00 AM - Reminder scheduled, app closed
         │
         ▼
Time: 10:01 AM - WorkManager task triggers
         │
         ▼
┌────────────────────────────────────────┐
│  WorkManager يعيد جدولة التذكير        │
│  • يحدث في الخلفية                     │
│  • يحدث الإشعار                        │
└────────────────────────────────────────┘
         │
         ▼
Time: 2:00 PM - User opens app
         │
         ▼
┌────────────────────────────────────────┐
│  main.dart → reviewOverdueReminders()  │
│  • يفحص جميع التذكيرات غير المقروءة    │
│  • يجد التذكير المجدول حديثاً          │
│  • scheduledAt > now → لا يعيد جدولة   │
│  • Race Guard يمنع التداخل             │
└────────────────────────────────────────┘
```

---

## 8. أكواد مهمة للمراجعة

### جدولة المراقبة الأولية:
```dart
// lib/services/notification_service.dart:547-586
Future<void> _scheduleMonitoringWorkManager(Reminder reminder) async
```

### معالج WorkManager:
```dart
// lib/services/workmanager_service.dart:276-640
@pragma('vm:entry-point')
void callbackDispatcher()

@pragma('vm:entry-point')
Future<void> _workmanagerCallback()
```

### خدمة التذكيرات المتأخرة:
```dart
// lib/services/overdue_reminder_service.dart:35-244
class OverdueReminderService
```

### استدعاء AI:
```dart
// lib/services/ai_service.dart:354-508
Future<Map<String, dynamic>> reschedulePost(...)
Future<String> reschedulePostRaw(...)
```

### تحليل رد AI:
```dart
// lib/services/workmanager_service.dart:150-180
Map<String, dynamic> _parseAiRescheduleResponse(String content)
```

---

## 9. نقاط مهمة للمطورين

### ✅ ما يتم إعداده مع كل طلب إعادة جدولة:

1. **تاريخ المحاولات السابقة** - كامل تاريخ التذكير (scheduledAt, isOpened, openedAt)
2. **أوقات فراغ المستخدم** - من FreeTimeRepository.getAllAsJson()
3. **الوقت الحالي** - DateTime.now() في وقت المعالجة
4. **الموعد النهائي (Deadline)** - محسوب حسب الأهمية (Day/Week/Month)
5. **فئة ومحتوى التذكير** - category, complexity, importance
6. **إعدادات AI** - apiKey, provider, model

### ✅ ما يتم إرساله للـ AI:

```json
{
  "category": "Productivity",
  "complexity": "Medium",
  "importance": "Week",
  "currentTime": "2024-01-15T14:30:00.000Z",
  "deadline": "2024-01-22T14:30:00.000Z",
  "previousAttempts": [
    {"scheduled_at": "2024-01-15T10:00:00.000Z", "opened": false},
    {"scheduled_at": "2024-01-15T12:00:00.000Z", "opened": false}
  ],
  "userFreeTimes": [
    {"day": 1, "start": "09:00", "end": "11:00"},
    {"day": 1, "start": "19:00", "end": "21:00"}
  ]
}
```

### ✅ ما يتم تحديثه في التذكير بعد إعادة الجدولة:

| الحقل | القيمة الجديدة |
|--------|----------------|
| `scheduledAt` | الوقت الجديد من AI |
| `rescheduleAttempts` | ++ (زيادة بواحد) |
| `aiExplanation` | السبب بالإنجليزية (الجزء الأول) |
| `aiExplanationAr` | السبب بالعربية (الجزء الثاني) |
| `isOpened` | false (إعادة تعيين) |
| `openedAt` | null (إعادة تعيين) |

### ⚠️ حالات الفشل والتعامل معها:

1. **AI يفشل أو يرد بشكل غير صالح** → Fallback: إضافة ساعة للوقت الحالي
2. **قاعدة البيانات مقفولة** (التطبيق في المقدمة) → WorkManager يعيد المحاولة (return false)
3. **وصل للحد الأقصى من المحاولات** → يتوقف عن إعادة الجدولة
4. **التذكير قديم جداً (>30 يوم)** → يتجاهل
5. **Race Guard نشط** → يتخطى العملية الحالية

---

## 10. اختبار آلية إعادة الجدولة

### محاكاة تذكير متأخر:

```dart
// في test أو debug
final reminder = Reminder(
  id: 1,
  url: 'https://example.com',
  title: 'Test Article',
  importance: 'Week',
  scheduledAt: DateTime.now().subtract(Duration(hours: 1)), // متأخر ساعة
  createdAt: DateTime.now().subtract(Duration(days: 1)),
  categoryEn: 'Productivity',
  complexityEn: 'Medium',
);
await reminderRepository.save(reminder);
await notificationService.scheduleReminder(reminder);

// استدعاء خدمة المتأخرين
final count = await overdueReminderService.reviewOverdueReminders();
print('Rescheduled: $count');
```

### التحقق من الإشعارات المعلقة:

```dart
final pending = await notificationService.getPendingNotifications();
for (final n in pending) {
  print('ID: ${n.id}, Title: ${n.title}, Time: ${n.scheduledDate}');
}
```

### التحقق من مهام WorkManager:

```dart
// Android: adb shell dumpsys jobscheduler | grep reminder_monitoring
// أو من الكود:
final tasks = await Workmanager().getPendingTasks();
```

---

## 🔴 مشاكل حرجة مُحددة (يجب إصلاحها قبل الإنتاج)

### 1. Race Guard ليس ذرياً (TOCTOU Race Condition)

**المشكلة:** قراءة وكتابة `SharedPreferences` عمليتان منفصلتان — ليسا ذريتين.

```
WorkManager يقرأ القفل → غير موجود ✓
OverdueReminderService يقرأ القفل → غير موجود ✓ (نفس اللحظة)
كلاهما يكتب القفل → كلاهما ينفذ → إشعاران مزدوجان
```

**الحل:** استخدم Transaction ذرية عبر ObjectBox:

```dart
@Entity()
class RescheduleLock {
  @Id() int id = 0;
  @Unique() int reminderId = 0;
  int timestamp = 0;
}

bool acquireRescheduleLock(Store store, int reminderId) {
  return store.runInTx(TxMode.write, () {
    final box = store.box<RescheduleLock>();
    final existing = box.query(RescheduleLock_.reminderId.equals(reminderId))
        .build().findFirst();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (existing != null && nowMs - existing.timestamp < 120000) return false;
    if (existing != null) {
      existing.timestamp = nowMs;
      box.put(existing);
    } else {
      box.put(RescheduleLock(reminderId: reminderId, timestamp: nowMs));
    }
    return true;
  });
}

void releaseRescheduleLock(Store store, int reminderId) {
  store.runInTx(TxMode.write, () {
    final box = store.box<RescheduleLock>();
    box.query(RescheduleLock_.reminderId.equals(reminderId)).build().remove();
  });
}
```

كتابة الـ transactions في ObjectBox حصرية عبر الـ isolates → حل فعلي للتداخل.

---

### 2. عدم إعادة فحص `isOpened` بعد نداء AI

**المشكلة:** نداء AI قد يستغرق 5–30 ثانية. لو فتح المستخدم التذكير أثناء المعالجة:

```dart
// الوضع الحالي: يقرأ isOpened قبل الـ AI، ثم يكتب فوقه بعدها
reminder.isOpened = false;  // ← يمسح فعل المستخدم!
```

**الحل:** أعد الجلب من قاعدة البيانات بعد رد الـ AI وقبل الحفظ:

```dart
final aiResult = await aiService.reschedulePostRaw(...);

final fresh = reminderRepo.getById(reminderId);
if (fresh == null || fresh.isOpened) {
  releaseRescheduleLock(store, reminderId);
  return true; // المستخدم فتحها أثناء المعالجة — توقف
}
```

---

### 3. `tz.local` في الـ Background Isolate غير موثوق

**المشكلة:** `initializeTimeZones()` وحدها **لا تضبط** المنطقة الزمنية المحلية — قد تعود UTC في الـ isolate المنفصل، فتُجدول الإشعارات بوقت خاطئ.

**الحل:**

```dart
tz_data.initializeTimeZones();
final tzName = await FlutterTimezone.getLocalTimezone(); // مطلوب
tz.setLocalLocation(tz.getLocation(tzName));             // إلزامي في الـ callback
```

أضف依赖: `flutter_timezone: ^2.0.0` في `pubspec.yaml`.

---

### 4. عدم فرض الـ Deadline على رد AI

**المشكلة:** الفحص الحالي يتحقق فقط من `newTime.isAfter(currentTime)` — الـ AI قد يرجع وقتاً خارج النافذة (خاصة مع Fallback "+ساعة" لذو أهمية `Day` قرب نهاية اليوم).

**الحل:**

```dart
DateTime newTime = /* من AI أو fallback */;
if (newTime.isAfter(maxTime)) {
  newTime = maxTime.subtract(const Duration(minutes: 30));
  if (!newTime.isAfter(currentTime)) {
    newTime = currentTime.add(const Duration(hours: 1)); // تجاوزنا النافذة كلياً
  }
}
```

---

### 5. مدة القفل (60 ثانية) أقصر من زمن نداء AI

**المشكلة:** لو استغرق الـ AI أكثر من 60 ثانية، عملية أخرى تكتسب القفل **بينما الأولى تعمل**.

**الحل:** ارفع TTL إلى 2–3 دقائق (كما في كود ObjectBox أعلاه).

---

## 🟡 ملاحظات موثوقية وتحسينات

| المشكلة | التفصيل | الحل المقترح |
|---------|---------|-------------|
| **WorkManager مؤجل فعلياً** | النظام (Doze/Battery Saver) قد يؤجل المهمة دقائق عديدة | توثيق أن `OverdueReminderService` هو شبكة الأمان الحقيقية |
| **Grace Period مفقود** | `reviewOverdueReminders` تعيد جدولة تذكير متأخر بـ 30 ثانية فقط | أضف هامشاً: `scheduledAt.isBefore(now - 2.minutes)` |
| **فحص الـ clamp في مهمة المراقبة القادمة** | حد الـ 15 دقيقة يُطبق؟ غير ظاهر | توثيق وتأكيد التطبيق |
| **تاريخ المحاولات** | لا يظهر أين تُضاف المحاولة الجديدة للسجل بعد كل reschedule | إضافة إدخال في التاريخ بعد كل نجاح |
| **ازدواجية الـ parsing** | `reschedulePost` و `_parseAiRescheduleResponse` منطقتان منفصلتان | وحّدهما في `lib/services/ai_reschedule_parser.dart` مشترك |
| **متانة الـ parser** | نماذج AI تلتف الـ JSON بـ ` ```json ` | إزالة code fences قبل `jsonDecode` |

---

## 🟠 أمان ومنصات

1. **API Key في `inputData`**: WorkManager يخزّن الـ inputData في JobScheduler (غير مشفر). الأفضل تمرير flag فقط وقراءة المفتاح من `flutter_secure_storage` داخل الـ callback.

2. **Android 12+ Exact Alarms**: `exactAllowWhileIdle` يتطلب `SCHEDULE_EXACT_ALARM`. أضف معالجة الرفض بالتراجع إلى `inexactAllowWhileIdle`.

3. **iOS غير مغطى**: Workmanager على iOS محدود جداً (BGTaskScheduler لا يدعم One-off بمهلة دقيقة). يحتاج مسار مختلف كلياً.

4. **تصادم IDs الإشعارات**: `reminderId + 1000000` سيتصادم عند وصول IDs لـ 1M. استخدم `reminderId` نفسه لإشعار المعلومات — سيستبدله الإشعار المجدول في موعده.

---

## ✅ خطة الإصلاح المقترحة

### المرحلة 1: أساسيات (حرجة)
- [ ] إضافة Entity `RescheduleLock` مع migration ObjectBox
- [ ] استبدال SharedPreferences Race Guard بـ ObjectBox transactions
- [ ] إضافة إعادة فحص `isOpened` بعد AI response
- [ ] إصلاح timezone في background isolate (`flutter_timezone`)

### المرحلة 2: متانة AI (حرجة)
- [ ] فرض `maxTime` deadline على رد AI + fallback آمن
- [ ] رفع TTL القفل إلى 120-180 ثانية
- [ ] توحيد parser في ملف مشترك

### المرحلة 3: موثوقية (مهمة)
- [ ] إضافة Grace Period (2 دقيقة) في `reviewOverdueReminders`
- [ ] إضافة سقف batch للـ AI (5 لكل دورة)
- [ ] تسجيل المحاولة في التاريخ بعد كل reschedule ناجح

### المرحلة 4: أمان ومنصات
- [ ] نقل API Key لـ `flutter_secure_storage`
- [ ] fallback لـ `inexactAllowWhileIdle`
- [ ] إصلاح تصادم notification IDs
- [ ] مسار iOS منفصل

---

## خلاصة (محدثة)

| المكون | التوقيت | البيئة | الاستخدام | حالة |
|----------|---------|---------|-----------|------|
| **OverdueReminderService** | App Start / Resume | Foreground | تنظيف التذكيرات المتأخرة | ✅ يعمل / يحتاج Grace Period |
| **WorkManager Task** | scheduledAt + 1min | Background | مراقبة وإعادة جدولة | ⚠️ يحتاج timezone fix |
| **Race Guard (Old)** | Always | SharedPreferences | منع التداخل | ❌ **TOCTOU - يستبدل** |
| **Race Guard (New)** | Always | ObjectBox TX | منع التداخل ذرياً | 🔄 **مطلوب تنفيذ** |
| **AI Reschedule** | Both | Cloud API | قرار ذكي للوقت الجديد | ⚠️ يحتاج deadline enforcement |
| **isOpened Re-check** | After AI call | Both | عدم مسح فعل المستخدم | 🔄 **مطلوب تنفيذ** |

---

## 11. اختبار الـ TOCTOU (جديد)

```dart
// محاكاة سباق بين المسارين
test('Race Guard prevents duplicate reschedule', () async {
  final store = await openStore();
  final lockBox = store.box<RescheduleLock>();
  
  // محاكاة عمليتين متزامنتين
  final results = await Future.wait([
    acquireRescheduleLock(store, 1),
    acquireRescheduleLock(store, 1),
  ]);
  
  // واحدة فقط تنجح
  expect(results.where((r) => r).length, equals(1));
  
  // تحرير القفل
  releaseRescheduleLock(store, 1);
  
  // الآن يمكن للثانية أن تنجح
  expect(acquireRescheduleLock(store, 1), isTrue);
});
```

---

## 12. 🔴 عطل: إغلاق الاتصال بعد جدولة الإشعار (Connection Closed After Scheduling)

### المشكلة:

عند حدوث `gemini_success` في الـ Edge Function ثم `Shutdown` مباشرة، تسلسل الأحداث في `workmanager_service.dart` كان:

```
✅ تحديث التذكير في قاعدة البيانات (scheduledAt, rescheduleAttempts, إلخ)
✅ جدولة الإشعار الجديد (zonedScheduleWithExactFallback)  ← ⚠️ الاتصال ينقطع هنا
❌ تسجيل مهمة WorkManager مراقبة جديدة — لم تنفذ
❌ تحرير قفل Race Guard — لم ينفذ (DEADLOCK!)
❌ عرض إشعار "تم إعادة الجدولة" — لم ينفذ
❌ إغلاق الـ Store — لم ينفذ
```

**النتيجة:** التذكير تُحدّث في قاعدة البيانات لكن:
- لا توجد مهمة مراقبة جديدة → التذكير لن يُفحص مرة أخرى
- القفل لم يُتحرر → أي محاولة إعادة جدولة مستقبلية ستُرفض
- المستخدم لا يرى إشعار إعادة الجدولة

**السبب:** جدولة الإشعار (`zonedScheduleWithExactFallback`) تتم عبر `FlutterLocalNotificationsPlugin` وهي العملية الأكثر احتمالاً لفشل الاتصال أو الانتهاء مبكراً. كان يجب أن تتم العمليات الحرجة (تسجيل WorkManager، تحرير القفل) **قبل** جدولة الإشعار.

### الإصلاح:

تم إعادة ترتيب الخطوات في `workmanager_service.dart` بحيث تكون العمليات الحرجة أولاً:

```
✅ تحديث التذكير في قاعدة البيانات
✅ إلغاء مهمة WorkManager القديمة
✅ تسجيل مهمة WorkManager مراقبة جديدة ← حرج
✅ تحرير قفل Race Guard ← حرج (يمنع Deadlock)
✅ جدولة الإشعار الجديد ← أقل أهمية (يمكن إعادة محاولته عند فتح التطبيق)
✅ عرض إشعار "تم إعادة الجدولة"
✅ إغلاق الـ Store
✅ إعادة true
```

**لماذا هذا الترتيب أفضل؟**
- إذا انقطع الاتصال بعد تسجيل WorkManager وتحريم القفل → التذكير مُجدول بشكل صحيح والقفل متاح
- إذا انقطع الاتصال بعد جدولة الإشعار → المشكلة نفسها (لا مهمة مراقبة، قفل محظور)
- جدولة الإشعار أقل أهمية لأن `OverdueReminderService` في Foreground يمكنه إعادة الجدولة عند فتح التطبيق

---

## 13. 🟡 عطل: عدم ظهور SnackBar عند إعادة الجدولة

### المشكلة:

عند تفعيل إعادة الجدولة (سواء عبر WorkManager أو OverdueReminderService)، لم يظهر أي `SnackBar` للمستخدم.

**السبب:**
- `flushPendingUiLogs()` كان يُستدعى مرة واحدة فقط في `addPostFrameCallback` عند تشغيل التطبيق
- عند عودة المستخدم للتطبيق (`AppLifecycleState.resumed`)، كان `_runOverdueCheck()` يستدعي `showUiLog()`
- إذا كان `ScaffoldMessengerState` غير جاهز بعد، كانت الرسالة تُضاف إلى `_pending` في `ui_messenger.dart`
- `flushPendingUiLogs()` لم يُستدعَ مرة أخرى → الرسائل المؤجلة لم تُعرض أبداً

### الإصلاح:

إضافة `flushPendingUiLogs()` في معالج `AppLifecycleState.resumed` في `main.dart` بعد `_showQueuedBgLogs()`:

```dart
case AppLifecycleState.resumed:
    await _reopenMainStoreIfNeeded();
    await _runOverdueCheck();
    final prefs = await SharedPreferences.getInstance();
    await _showQueuedBgLogs(prefs);
    flushPendingUiLogs();  // ← أُضيف لضمان عرض الرسائل المؤجلة
    break;
```

---

### ملخص الإصلاحات الحرجة

| المشكلة | الحالة | الإصلاح |
|---------|--------|---------|
| إغلاق الاتصال بعد جدولة الإشعار | 🔴 حرج | إعادة ترتيب الخطوات: WorkManager + القفل أولاً |
| TOCTOU Race Condition | 🔴 حرج | استبدال SharedPreferences بـ ObjectBox transactions |
| عدم إعادة فحص isOpened بعد AI | 🟡 متوسط | إعادة الجلب من DB بعد AI call |
| tz.local غير موثوق في background | 🟡 متوسط | إضافة flutter_timezone |
| قفل TTL 60 ث < زمن AI | 🟡 متوسط | رفع TTL إلى 120-180 ثانية |
| عدم ظهور SnackBar عند إعادة الجدولة | 🟡 متوسط | إضافة flushPendingUiLogs() عند resume |

النظام بعد الإصلاحات سيكون **متسامحاً مع الأعطال** حقاً — مع ضمان ذري للتداخل، وعدم مسح إجراءات المستخدم، وإشعارات موقوتة بشكل صحيح.