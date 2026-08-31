# تشخيص مشكلة OverdueReminderService - إجابات مبنية على الكود الفعلي

---

## القسم الأول: تشخيص المشكلة الحالية

### 1. طبقة البيانات (`ReminderRepository.getAllUnread`)

**ما هو الاستعلام الدقيق المستخدم؟**
```dart
// reminder_repository.dart:94-101
List<Reminder> getAllUnread() {
  final query = _box.query(Reminder_.isOpened.equals(false)).build();
  final results = query.find();
  query.close();
  results.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  return results;
}
```
- **الشرط الوحيد**: `isOpened == false` (سطر 95)
- **لا توجد شروط إضافية**: لا يوجد تصفية بـ `isDeleted` أو `isArchived` لأن الموديل لا يحتوي على هذه الحقول (راجع `reminder.dart`)
- **لا يوجد `limit`**: تُرجع جميع التذكيرات غير المفتوحة (سطر 96)
- **فرز داخلي**: مرتبة حسب `scheduledAt` تصاعديًا (سطر 99)
- **لا توجد شروط على `scheduledAt` داخل الاستعلام**: الفلترة تتم **بعد** جلب النتائج في `OverdueReminderService` (سطر 65-67)

---

### 2. التوقيت والـ Timezone

**كيف يُخزَّن `scheduledAt` في ObjectBox؟**
```dart
// reminder.dart:36-37
@Property(type: PropertyType.date)
DateTime scheduledAt;
```
- نوع التخزين: `PropertyType.date` → يخزن كـ **epoch milliseconds** (int64)
- ObjectBox يخزن `DateTime` كـ UTC millis منذ Unix epoch

**المقارنة في الكود:**
```dart
// overdue_reminder_service.dart:57, 65-67
final currentTime = DateTime.now();  // LOCAL time
final overdueReminders = allUnread.where((r) => r.scheduledAt.isBefore(currentTime)).toList();
```
- `DateTime.now()` → يعيد **Local time** (مع timezone الجهاز)
- `scheduledAt` عند قراءته من ObjectBox → يعاد كـ **Local time** تلقائيًا (ObjectBox يحول من UTC المخزن إلى Local عند القراءة)
- **النتيجة**: كلا الطرفين `Local` → المقارنة صحيحة **إذا** كان timezone الجهاز ثابتًا

**فحص `isUtc`:**
```dart
// في Reminder model لا يوجد تعيين صريح لـ isUtc
// DateTime.fromMillisecondsSinceEpoch(ms, isUtc: false) هو الافتراضي عند القراءة من ObjectBox
```
- `reminder.scheduledAt.isUtc` → **false** (local)
- `DateTime.now().isUtc` → **false** (local)
- **متطابقان** → لا مشكلة في النوع

**تحذير مهم**: إذا تغير timezone الجهاز بين حفظ التذكير وقراءته، ستتغير قيمة `scheduledAt` المحلية المقابلة لنفس اللحظة UTC. لكن المقارنة `isBefore` تظل صحيحة لأن الطرفين يتأثران بنفس التغيير.

---

### 3. نقطة الاستدعاء (Lifecycle)

**مساران للتنفيذ:**

**أ) Cold Start (فتح التطبيق من الصفر):**
```dart
// main.dart:266-275
try {
  final rescheduledCount = await overdueReminderService.reviewOverdueReminders();
  if (rescheduledCount > 0) {
    debugPrint('[main] Rescheduled $rescheduledCount overdue reminders on app start');
  }
} catch (e, stackTrace) {
  debugPrint('[main] Failed to review overdue reminders on start: $e');
  debugPrint('Stack trace: $stackTrace');
}
```
- يُستدعى **مرة واحدة** في `_initApp()` قبل `runApp()`
- أي استثناء يُبتلع ويُطبع فقط (لا يوقف التطبيق)

**ب) App Resume (العودة من الخلفية):**
```dart
// main.dart:399-441
class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    ...
    } else if (state == AppLifecycleState.resumed) {
      if (!_storeInitialized) {
        _reopenStore().catchError(...);
      } else {
        // Store is already initialized, run overdue check
        _runOverdueCheck();  // ← هنا
      }
    }
  }

  void _runOverdueCheck() {
    Future.microtask(() async {  // ← microtask
      try {
        final rescheduledCount = await overdueReminderService.reviewOverdueReminders();
        ...
      } catch (e, stackTrace) { ... }
    });
  }
}
```
- **عند `resumed`**: إذا كان `_storeInitialized == true` → يُستدعى `_runOverdueCheck()` داخل `Future.microtask`
- **المشكلة المحتملة**: `Future.microtask` يُنفذ **بعد** انتهاء الـ event loop الحالي، لكن **قبل** الـ microtasks اللاحقة. إذا كان هناك استثناء في `_reopenStore()` (عند `_storeInitialized == false`)، فلن يصل الكود لـ `_runOverdueCheck()`

**حارس التكرار (5 ثوانٍ):**
```dart
// overdue_reminder_service.dart:46-51
final now = DateTime.now();
if (_lastProcessedTime != null &&
    now.difference(_lastProcessedTime!) < const Duration(seconds: 5)) {
  debugPrint('[OverdueReminderService] Called too recently, skipping');
  return 0;
}
```
- إذا فُتح التطبيق، ثم قفل الشاشة، ثم فُتح مرة أخرى **خلال 5 ثوانٍ** → سيتم تجاهل الاستدعاء الثاني
- هذا **مقصود** لمنع التنفيذ المزدوج السريع

---

### 4. حارس التكرار ومنع التنفيذ المزدوج

**`_isProcessing` و `finally`:**
```dart
// overdue_reminder_service.dart:40-105
if (_isProcessing) { return 0; }
...
_isProcessing = true;
_lastProcessedTime = now;
try {
  // ... كل منطق المعالجة
} finally {
  _isProcessing = false;  // ← مضمون التنفيذ
}
```
- **كل نقاط الخروج** تمر عبر `finally` (بما في ذلك `return 0` المبكر في سطر 72)
- **لا يمكن أن يعلق** على `true` إلا إذا حدث `StackOverflow` أو `OutOfMemory` (نادرة جدًا)

**التداخل بين `_initApp` و `didChangeAppLifecycleState`:**
- Cold start: `_initApp()` يُستدعي `reviewOverdueReminders()` → يضبط `_lastProcessedTime`
- إذا انتقل المستخدم فورًا للخلفية ثم للواجهة (`resumed`) خلال < 5 ثوانٍ → الحارس في سطر 47-51 سيمنع التنفيذ
- **هذا سلوك صحيح** وليس bug

---

### 5. حد المحاولات القصوى (`rescheduleAttempts`)

**المنطق:**
```dart
// overdue_reminder_service.dart:110-115
final maxReschedules = _getMaxReschedules(reminder.importance);
if (reminder.rescheduleAttempts >= maxReschedules) {
  debugPrint('[OverdueReminderService] Reminder ${reminder.id} reached max reschedules ($maxReschedules), skipping');
  return false;
}
```
```dart
// overdue_reminder_service.dart:213-224
int _getMaxReschedules(String importance) {
  switch (importance) {
    case 'Day': return 1;
    case 'Week': return 2;
    case 'Month': return 3;
    default: return 2;
  }
}
```
- **Day**: 1 محاولة فقط
- **Week**: محاولتان
- **Month**: 3 محاولات
- إذا وصل التذكير للحد → **يتجاهل بصمت** (يُطبع log فقط، لا إشعار للمستخدم)

**مشكلة محتملة**: إذا اختبرت نفس التذكير عدة مرات (مثلاً غيّرت الوقت يدويًا ثم اختبرت)، فقد يصل للحد بسرعة. `rescheduleAttempts` **لا يُصفّر تلقائيًا** إلا عند فتح التذكير (`isOpened = true`).

---

### 6. قفل الـ Race Guard المشترك مع WorkManager

**نفس المفتاح يُستخدم في الخدمتين:**
```dart
// overdue_reminder_service.dart:143-150
final rescheduleLockKey = 'rescheduling_lock_${reminder.id}';
final lockTimestamp = prefs.getInt(rescheduleLockKey) ?? 0;
final nowMs = DateTime.now().millisecondsSinceEpoch;
if (nowMs - lockTimestamp < 60000) {  // 60 ثانية
  debugPrint('[OverdueReminderService] ⚠️ [RaceGuard] Another reschedule in progress...');
  return false;
}
await prefs.setInt(rescheduleLockKey, nowMs);
```

```dart
// workmanager_service.dart:403-416
final rescheduleLockKey = 'rescheduling_lock_$reminderId';
final prefs = await SharedPreferences.getInstance();
final lockTimestamp = prefs.getInt(rescheduleLockKey) ?? 0;
final nowMs = DateTime.now().millisecondsSinceEpoch;
if (nowMs - lockTimestamp < 60000) {
  await _log('⚠️ [RaceGuard] Another reschedule in progress for reminder $reminderId, skipping');
  store.close();
  return true;
}
await prefs.setInt(rescheduleLockKey, nowMs);
```

**سيناريو القفل العالق (Stale Lock):**
1. WorkManager يبدأ التنفيذ → يكتسب القفل (سطر 415)
2. يحدث **خطأ قبل** سطر 568 (`prefs.remove`) → مثل: `another store is still open`، أو استثناء في AI
3. في مسار الخطأ (سطر 582-586) **يُحاول** تحرير القفل، لكن إذا فشل `SharedPreferences.getInstance()` أو حدث استثناء آخر → القفل **يبقى**
4. OverdueReminderService يأتي لاحقًا → يجد القفل صالحًا (أقل من 60 ثانية) → **يتجاهل التذكير بصمت**

**الحل في الكود**: القفل ينتهي تلقائيًا بعد 60 ثانية (سطر 147, 409). لكن خلال هذه الدقيقة، التذكير **لن يُعاد جدولته** من أي طرف.

---

### 7. استدعاء AI والحفظ

**مسار الاستدعاء:**
```dart
// overdue_reminder_service.dart:158-165
final result = await _aiService.reschedulePost(
  previousAttemptsJson: jsonEncode(previousAttempts),
  category: reminder.categoryEn ?? 'Other',
  complexity: reminder.complexityEn ?? 'Medium',
  importance: reminder.importance,
  userFreeTimesJson: freeTimes.isNotEmpty ? '{"free_times": $freeTimes}' : null,
  currentTime: currentTime,
);
```
- يستخدم `reschedulePost` (وليس `reschedulePostRaw` المستخدم في WorkManager)
- كلاهما لهما **نفس البرومبت** تقريبًا (راجع `ai_service.dart:354-448` و `450-508`)

**معالجة الاستجابة:**
```dart
// overdue_reminder_service.dart:167-185
final newTime = result['newTime'] as DateTime?;
if (newTime == null) { ... return false; }
if (!newTime.isAfter(currentTime)) {
  // Fallback: +1 ساعة
  final fallbackTime = currentTime.add(const Duration(hours: 1));
  reminder.scheduledAt = fallbackTime;
} else {
  reminder.scheduledAt = newTime;
}
```
- **تحقق حرج**: يرفض أوقات الماضي (سطر 177)
- **Fallback تلقائي**: يضيف ساعة واحدة للوقت الحالي

**الحفظ:**
```dart
// overdue_reminder_service.dart:197
_reminderRepository.save(reminder);
```
- `ReminderRepository.save()` → `_box.put(reminder)` (سطر 9-11)
- **لا يوجد تحقق من نجاح الحفظ** (لا يعيد قيمة، لا يرمي استثناء عادة)
- **موصى به**: قراءة التذكير بعد الحفظ للتأكد: `_reminderRepository.getById(reminder.id)`

---

### 8. فحص عبر السجلات الفعلية

**ما يجب أن يظهر في `adb logcat -s flutter:V *:S` عند Cold Start:**

```
[OverdueReminderService] Current device time: 2026-08-28T21:30:00.000  ← سطر 58
[OverdueReminderService] Total unread reminders: 3                    ← سطر 62
[OverdueReminderService] Found 2 overdue reminders                    ← سطر 69
[OverdueReminderService] Overdue: id=5, title="Article", scheduledAt=2026-08-28T20:00:00.000, importance=Week, rescheduleAttempts=0  ← سطر 77
[OverdueReminderService] Calling AI for reschedule: id=5, category=Productivity, complexity=Medium, importance=Week  ← سطر 156
[OverdueReminderService] 🔒 [RaceGuard] Acquired reschedule lock for reminder 5  ← سطر 153
[OverdueReminderService] Reminder 5 saved with new scheduledAt: 2026-08-29T09:00:00.000  ← سطر 198
[OverdueReminderService] 🔓 [RaceGuard] Released reschedule lock for reminder 5  ← سطر 207
[OverdueReminderService] Successfully rescheduled 2 of 2 overdue reminders  ← سطر 101
[main] Rescheduled 2 overdue reminders on app start                     ← main.dart:270
```

**إذا لم تظهر "Current device time:"** → `reviewOverdueReminders()` **لم يُستدعَ أصلاً** (استثناء في `_initApp` قبل السطر 268)

**إذا ظهرت "Total unread reminders: 3" لكن "Found 0 overdue reminders"** → المشكلة في **المقارنة الزمنية** (القسم 2)

**إذا ظهرت "Found 2 overdue reminders" لكن لا تظهر "Calling AI for reschedule"** → التذكيرات **مُقفلة بـ Race Guard** أو **وصلت للحد الأقصى للمحاولات**

---

## القسم الثاني: أسئلة حول هيكلة الكود (Architecture)

### 9. تكرار المنطق بين الخدمتين

**نعم، يوجد تكرار شبه كامل:**
| الجزء | `OverdueReminderService._rescheduleOverdueReminder` | `workmanager_service.dart._workmanagerCallback` |
|------|-----------------------------------------------------|--------------------------------------------------|
| فحص `maxReschedules` | سطر 111-115 | سطر 365-370 |
| فحص "أقدم من 30 يوم" | سطر 118-121 | سطر 372-377 |
| جلب التاريخ (`getReminderHistory`) | سطر 124-133 | سطر 380-389 |
| جلب أوقات الفراغ | سطر 136 | سطر 397 |
| Race Guard (نفس المفتاح والمنطق) | سطر 143-153 | سطر 403-416 |
| استدعاء AI | `reschedulePost` (سطر 158) | `reschedulePostRaw` (سطر 420) |
| التحقق من `newTime` | سطر 177-185 | سطر 454-459 |
| تحديث الحقول | سطر 187-194 | سطر 462-471 |
| الحفظ | سطر 197 | سطر 472 |
| تحرير القفل | سطر 206-207 | سطر 568-569 |

**الاختلافات الجوهرية:**
1. **AI Method**: `reschedulePost` (يُرجع `Map`) vs `reschedulePostRaw` (يُرجع `String` خام)
2. **البيئة**: Main Isolate (مع Store مفتوح) vs Background Isolate (يفتح Store جديد)
3. **الإشعارات**: `_notificationService.scheduleReminder()` vs `FlutterLocalNotificationsPlugin.zonedSchedule()` المباشر
4. **WorkManager**: لا يُعاد جدولته في OverdueReminderService vs يُعاد جدولته في WorkManager (سطر 507-541)

**التوصية**: استخراج منطق "إعادة الجدولة الأساسي" إلى دالة/كلاس مشترك (`RescheduleEngine`) يُستدعى من الطرفين، مع تمرير callbacks للعمليات الخاصة بكل بيئة (حفظ، إشعارات، جدولة WorkManager).

---

### 10. إدارة الـ Store (ObjectBox) بين الـ Isolates

**الحالة الحالية:**
```dart
// main.dart:32, 171-190
late Store store;  // Main isolate
...
tempStore = await openStore();
store = tempStore;
_storeInitialized = true;
```

```dart
// workmanager_service.dart:195-227, 346
Future<Store> _openStoreInBackground(String? directoryPath) async {
  ...
  return openStore(directory: directoryPath);  // Background isolate
}
...
store = await _openStoreInBackground(storeDirectoryPath);
```

**المشكلة الموثقة في الكود:**
- سطر 182 في `main.dart`: `e.toString().contains('another store is still open')`
- سطر 217 في `workmanager_service.dart`: نفس الخطأ
- **ObjectBox لا يدعم فتح نفس ملف القاعدة من isolateين متزامنين** (إلا مع `openStore` في وضع read-only أو باستخدام multiprocess - غير مدعوم في Flutter ObjectBox حاليًا)

**الحل الحالي**: إعادة المحاولة مع تأخير (Retry logic في كلا الجانبين)
- Main: 3 محاولات، انتظار ثانيتين
- Background: 5 محاولات، انتظار 30 ثانية!

**خطر حقيقي**: إذا كان التطبيق في الواجهة (Main isolate يملك الـ Store) → WorkManager سيفشل مرارًا لـ 2.5 دقيقة (5×30ث) قبل أن يستسلم. هذا **يؤخر** معالجة التذكيرات المتأخرة في الخلفية.

**الحل المعماري الصحيح**: 
- استخدام **Isolate واحد دائم** للعمليات الخلفية (Background Isolate) مع Channel للتواصل مع Main Isolate
- أو: نقل كل عمليات قاعدة البيانات للـ Background Isolate، والـ Main Isolate يتواصل عبر الرسائل فقط

---

### 11. اعتماد السجل المحلي (SharedPreferences) كآلية قفل موزعة

**الكود الحالي:**
```dart
// التحقق ثم الكتابة (Check-then-act) - ليس atomic
final lockTimestamp = prefs.getInt(rescheduleLockKey) ?? 0;  // قراءة
if (nowMs - lockTimestamp < 60000) { return false; }         // قرار
await prefs.setInt(rescheduleLockKey, nowMs);                // كتابة
```

**مشكلة Race Condition:**
- `SharedPreferences` في Flutter **ليس thread-safe** عبر isolates
- كل isolate له نسخة منفصلة من `SharedPreferences` في الذاكرة
- الكتابة تتم async إلى الـ platform channel
- **نافذة سباق حقيقية**: isolate A يقرأ (القفل=0)، isolate B يقرأ (القفل=0)، كلاهما يقرر المتابعة، كلاهما يكتب → **كلاهما ينفذ الاستعادة!**

**في الممارسة**: احتمال حدوث هذا منخفض لأن:
1. WorkManager يعمل كل 15 دقيقة كحد أدنى
2. OverdueReminderService يعمل عند فتح التطبيق فقط
3. الحارس 5 ثوانٍ في OverdueReminderService يقلل التداخل

**لكن**: ليس مضمونًا. الحل السليم: استخدام **File-based lock** (مثل `FileLock` من `file` package) أوNamed mutex عبر platform channel، أو نقل التنسيق لـ Isolate واحد.

---

### 12. مسؤولية الخدمات (Separation of Concerns)

**`NotificationService` كـ Singleton يحمل حالة mutable:**
```dart
// notification_service.dart:32-36, 532-545
String? _storeDirectoryPath;
String? _apiKey;
String _provider = 'google';
String _model = '';

void setStoreDirectoryPath(String path) { _storeDirectoryPath = path; }
void setAiConfig(String apiKey, String provider, String model) {
  _apiKey = apiKey;
  _provider = provider;
  _model = model;
}
```

**المشكلة**: هذه القيم تُضبط في `main.dart:245-249` وقت التهيئة:
```dart
notificationService.setAiConfig(
  settingsRepository.getApiKey() ?? '',
  settingsRepository.getProvider(),
  settingsRepository.getModel(),
);
```

**لكن**: إذا غيّر المستخدم إعدادات AI (مفتاح، موديل، Provider) **من شاشة الإعدادات** أثناء تشغيل التطبيق:
- `settingsRepository` يتحديث
- **لكن `NotificationService` لا يُعلم بالتغيير** إلا إذا استُدعيت `setAiConfig` مجددًا
- WorkManager tasks المجدولة **مسبقًا** تحمل الـ `inputData` القديمة (سطر 551-563) → ستستخدم إعدادات قديمة عند التنفيذ

**الحل**: تمرير الإعدادات كـ `inputData` وقت الجدولة فقط (كما يحدث حاليًا)، وعدم الاعتماد على الحالة الداخلية للـ singleton وقت التنفيذ. أو: إضافة listener على تغييرات الإعدادات لتحديث الـ singleton.

---

### 13. معالجة الأخطاء الصامتة (Silent Failures)

**أمثلة على `try-catch` فارغ في `NotificationService`:**

| السطر | الدالة | المشكلة |
|--------|---------|---------|
| 70-80 | `initialize` | يبتلع استثناء تهيئة الـ plugin |
| 115, 143-144, 154 | `_requestPermissions` | يفشل بصمت |
| 112-113 | `createNotificationChannel` | يفشل بصمت |
| 301-303 | `scheduleReminder` | يعيد `false` بلا log |
| 346-347 | `cancelReminder` | يفشل بصمت |
| 350-351 | `cancelReminder` (WorkManager) | يفشل بصمت |
| 369 | `getPendingNotifications` | يعيد `[]` بلا log |
| 384 | `areNotificationsEnabled` | يعيد `false` بلا log |
| 583-585 | `_scheduleMonitoringWorkManager` | يطبع debugPrint فقط |

**في `WorkManagerService`:**
- `_queueUiLog` (سطر 29-39): `catch (_) {}` - يبتلع كل شيء
- `_remoteLog` (سطر 67-69): `catch (e) { debugPrint(...); }` - على الأقل يطبع
- `_initBackgroundServices` (سطر 85, 103): `catch (_) {}` - يبتلع

**التأثير**: يجعل التشخيص **مستحيلًا تقريبًا** بدون إضافة logs يدويًا. هذا **بالضبط** سبب صعوبة تشخيص مشكلة "لا يعيد جدولة التذكيرات".

**التوصية**: 
1. إضافة `debugPrint` في كل `catch` على الأقل
2. استخدام `talker` أو `logger` package لتسجيل منظم
3. للأخطاء الحرجة: إظهار Snackbar للمستخدم أو حفظ في `debug_logs` table

---

## الخلاصة: أبرز أسباب محتملة للمشكلة

بناءً على الكود، أكثر الأسباب احتمالاً (مرتبة):

1. **Race Guard قفل قديم** من WorkManager سابق فشل قبل تحرير القفل (القسم 6) → الحل: فحص `lockTimestamp` في السجلات
2. **التذكير وصل لـ `maxReschedules`** (القسم 5) → الحل: فحص `rescheduleAttempts` في اللوج
3. **مقارنة زمنية خاطئة** بسبب timezone (القسم 2) → الحل: طباعة `scheduledAt` و `currentTime` الخام
4. **استثناء في `_initApp` قبل السطر 268** يبتلعه الـ catch في `main()` (سطر 78-115) → الحل: فحص logcat للخطأ المبكر
5. **`_isProcessing` عالق** (نادر، القسم 4) → الحل: إعادة تشغيل التطبيق
6. **WorkManager يملك الـ Store** (main isolate مغلق) عند محاولة OverdueReminderService → الحل: فحص log "another store is still open"

---

## خطوات التشخيص المقترحة التالية

1. **أضف logs مؤقتة** في `overdue_reminder_service.dart`:
   ```dart
   // سطر 61 - قبل الفلترة
   for (final r in allUnread) {
     debugPrint('DEBUG unread: id=${r.id}, scheduledAt=${r.scheduledAt.toIso8601String()}, isUtc=${r.scheduledAt.isUtc}, now=${DateTime.now().toIso8601String()}, nowUtc=${DateTime.now().isUtc}');
   }
   ```

2. **شغل التطبيق** وافتح logcat:
   ```bash
   adb logcat -s flutter:V *:S | grep -E "(OverdueReminderService|main|WorkManager)"
   ```

3. **تحقق من SharedPreferences** للقفل:
   ```dart
   // في أي شاشة، أضف مؤقتًا:
   final prefs = await SharedPreferences.getInstance();
   final keys = prefs.getKeys();
   for (final k in keys.where((k) => k.startsWith('rescheduling_lock_'))) {
     print('Lock $k: ${prefs.getInt(k)} (age: ${DateTime.now().millisecondsSinceEpoch - (prefs.getInt(k) ?? 0)}ms)');
   }
   ```

4. **اختبر بتصفير `rescheduleAttempts`** لتذكير معروف:
   ```dart
   final r = reminderRepository.getById(testId);
   r.rescheduleAttempts = 0;
   reminderRepository.save(r);
   ```

---

*تم إنشاء هذا المستند بالرجوع للكود الفعلي في:*
- `lib/repositories/reminder_repository.dart`
- `lib/models/reminder.dart`
- `lib/services/overdue_reminder_service.dart`
- `lib/main.dart`
- `lib/services/workmanager_service.dart`
- `lib/services/notification_service.dart`
- `lib/services/ai_service.dart`