# تشخيص مشكلة التوقف عند شاشة Splash

## 1. بنية شاشة الـ Splash نفسها

### 1. هل شاشة splash هي `StatefulWidget`؟ أين بالضبط تُستدعى منطق الانتقال؟
لا، شاشة الـ Splash هي `StatelessWidget` ولا تحتوي على أي منطق انتقال مدمج.

**الملف:** `lib/screens/splash_screen.dart:6`
```dart
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final error = initError;
    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/app_icon.png',
                width: 96,
                height: 96,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 24),
              Text(
                'Bookmark Reminder',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.whiteTextPrimary,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              if (error != null) ...[
                const SizedBox(height: 24),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

### 2. هل تعتمد على `FutureBuilder` / `StreamBuilder`، أم على `Navigator.push` مباشر بعد `await`؟
لا تعتمد على أي منهما. شاشة الـ Splash هي واجهة عرض ثابتة تعرض سبينر دائماً. منطق الانتقال يعتمد بالكامل على **توجيه go_router** عبر `redirect` في `AppRouter`.

**الملف:** `lib/core/app_router.dart:58`
```dart
router = GoRouter(
  initialLocation: '/',
  refreshListenable: Listenable.merge([
    authService,
    revenueCatService,
  ]),
  redirect: (context, state) {
    final status = authService.status;
    final isPremium = revenueCatService.isPremium;
    final isOnLogin = state.matchedLocation == '/login';
    final isOnPaywall = state.matchedLocation == '/paywall';

    if (status == AuthStatus.loading) {
      return '/';
    }

    if (status == AuthStatus.unauthenticated) {
      return isOnLogin ? null : '/login';
    }

    if (!isPremium) {
      return isOnPaywall ? null : '/paywall';
    }

    if (isOnLogin || isOnPaywall) {
      return '/reminders';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => const NoTransitionPage(
        child: SplashScreen(),
      ),
    ),
    // ...
  ],
);
```

### 3. هل هناك `setState` بعد اكتمال العملية غير المتزامنة؟ وهل تتحقق من `mounted` قبل استدعائه؟
لا يوجد `setState` في `SplashScreen` على الإطلاق. التغييرات في `AuthStatus` و `isPremium` تتم عبر `ChangeNotifier.notifyListeners()` في `AuthService` و `RevenueCatService`، مما يُعيد بناء `GoRouter` من خلال `refreshListenable`.

### 4. هل الانتقال يتم عبر `Navigator.pushReplacement` أم `pushAndRemoveUntil` أم عبر تغيير حالة في `Provider/Bloc/Riverpod` يُعاد بناء الشجرة على أساسها؟
الانتقال يتم عبر **تغيير الحالة** في `AuthService` و `RevenueCatService` (كلاهما `ChangeNotifier`)، والـ `GoRouter` يُعاد بناءه تلقائياً عبر `refreshListenable: Listenable.merge([authService, revenueCatService])`.

---

## 2. العمليات غير المتزامنة التي تُنفَّذ قبل الانتقال

### 5. اذكر بالترتيب كل عملية `await` تحدث داخل splash
**الملاحظة المهمة:** شاشة الـ Splash نفسها لا تقوم بأي عمليات غير متزامنة. جميع العمليات غير المتزامنة تتم في **`_initApp()`** داخل `main.dart` **قبل** استدعاء `runApp()`.

**الملف:** `lib/main.dart:127-340`

العمليات بالترتيب:
1. `await Firebase.initializeApp()` (السطر 129)
2. `await Supabase.initialize(...)` (السطر 138) - مشروط بـ `AppConfig.isSupabaseConfigured`
3. `await revenueCatService.initialize()` (السطر 156)
4. `await initLocalTimeZone()` (السطر 164)
5. `await _openMainStore()` (السطر 172)
6. `await SharedPreferences.getInstance()` (السطر 180)
7. `await ProxyConfigService.instance.prefetch().timeout(...)` غير متزامن عبر `unawaited` (السطر 205)
8. `await _showQueuedBgLogs(prefs)` (السطر 220)
9. `await Workmanager().initialize(...)` (السطر 231) - للأندرويد/iOS فقط
10. `await defaultStoreDirectory()` (السطر 242)
11. `await notificationService.initialize(...)` (السطر 246)
12. `await overdueReminderService.reviewOverdueReminders()` (السطر 268)
13. `await notificationService.requestBackgroundPermissions()` (السطر 287)
14. `await notificationService.handleAppLaunchFromNotification()` (السطر 295)
15. `await ReceiveSharingIntent.instance.getInitialMedia()` (السطر 304)

### 6. هل كل هذه العمليات مُغلّفة داخل `try/catch`؟ ماذا يحدث فعليًا إذا فشلت واحدة منها؟
معظم العمليات مُغلّفة داخل `try/catch`، لكن **الأهم**:

- **ObjectBox initialization** (السطر 171-177): يُرمى الاستثناء مرة أخرى (`rethrow`) بعد تسجيله!
```dart
try {
  store = await _openMainStore();
} catch (e) {
  debugPrint('ObjectBox initialization failed: $e');
  if (initError == null) initError = 'ObjectBox initialization failed: $e';
  rethrow;  // ⚠️ هذا يوقف _initApp بالكامل!
}
```

- **WorkManager initialization** (السطر 230-239): مُغلّفة جيداً
- **Notification service initialization** (السطر 245-255): مُغلّفة جيداً
- **Overdue reminder service** (السطر 267-283): مُغلّفة جيداً

**المشكلة المحتملة:** إذا فشل `_openMainStore()`، فإن `rethrow` يوقف تنفيذ `_initApp()` بالكامل، مما يمنع إنشاء `AppRouter` و `runApp()`.

### 7. هل هناك أي عملية بدون `timeout`؟
نعم، عدة عمليات بدون `timeout`:

1. **`Firebase.initializeApp()`** (السطر 129) - بدون timeout
2. **`Supabase.initialize(...)`** (السطر 138) - بدون timeout
3. **`revenueCatService.initialize()`** (السطر 156) - بدون timeout
4. **`initLocalTimeZone()`** (السطر 164) - بدون timeout
5. **`SharedPreferences.getInstance()`** (السطر 180) - بدون timeout
6. **`defaultStoreDirectory()`** (السطر 242) - بدون timeout
7. **`notificationService.initialize(...)`** (السطر 246) - بدون timeout
8. **`ReceiveSharingIntent.instance.getInitialMedia()`** (السطر 304) - بدون timeout

**الوحيد الذي لديه timeout:** `ProxyConfigService.instance.prefetch()` (السطر 206):
```dart
unawaited(
  ProxyConfigService.instance.prefetch().timeout(
    const Duration(seconds: 12),
  ).catchError((_) {}),
);
```

### 8. هل تستخدم `Future.wait([...])`؟
لا، لا يستخدم `Future.wait` في `_initApp()`. العمليات تُنفَّذ تسلسلياً باستخدام `await`.

---

## 3. حالة الشبكة والخدمات الخارجية

### 9. هل يعتمد splash على اتصال إنترنت؟
نعم، بشكل غير مباشر. `_initApp()` يُستدعى **قبل** `runApp()`، ويتضمن:
- `Firebase.initializeApp()` - قد تحتاج إنترنت
- `Supabase.initialize(...)` - تحتاج إنترنت
- `revenueCatService.initialize()` - تتضمن `Purchases.getCustomerInfo()` الذي يتصل بـ RevenueCat
- `notificationService.initialize()` - قد تتصل بـ FCM

**الملف:** `lib/services/revenuecat_service.dart:35`
```dart
Future<void> initialize() async {
  await Purchases.setLogLevel(LogLevel.debug);
  await Purchases.configure(PurchasesConfiguration(_apiKey));

  debugPrint('App User ID: ${await Purchases.appUserID}');
  debugPrint('Is Anonymous: ${await Purchases.isAnonymous}');

  try {
    _customerInfo = await Purchases.getCustomerInfo();  // ⚠️ قد تعلق بدون إنترنت
    _updatePremiumStatus();
  } catch (e) {
    debugPrint('Failed to get customer info: $e');
  }

  Purchases.addCustomerInfoUpdateListener((customerInfo) {
    _customerInfo = customerInfo;
    _updatePremiumStatus();
  });
}
```

### 10. هل جربت تشغيل التطبيق في وضع Airplane Mode؟
هذا سؤال يتطلب اختبار فعلي. لكن بناءً على الكود، **نعم**، يمكن أن تكون المشكلة متعلقة بالشبكة لأن `_initApp()` تنتظر اتصال شبكي لـ:
- Firebase
- Supabase
- RevenueCat (`Purchases.getCustomerInfo()`)

### 11. هل هناك استدعاء لأي SDK خارجي قد يعلّق (hang) بدل أن يرمي استثناء صريحًا؟
نعم، **RevenueCat SDK** هو المرشح الأقوى:
```dart
_customerInfo = await Purchases.getCustomerInfo();  // قد تعلق بدون timeout
```

---

## 4. الحالة المحلية والتخزين

### 12. هل تُقرأ بيانات من `SharedPreferences` أو `Hive` أو قاعدة بيانات SQLite محلية أثناء splash؟
نعم:
- `SharedPreferences.getInstance()` (السطر 180)
- قراءة `prefs.getString('last_ai_reschedule_error')` (السطر 213)
- قراءة `prefs.getStringList(_bgUiLogQueueKey)` (السطر 59)

**لا يوجد** تحليل (parsing) معقد للبيانات المحلية في `_initApp()`.

### 13. هل هناك عملية migration لقاعدة بيانات محلية؟
نعم، `_openMainStore()` يحتوي على منطق إعادة المحاولة:
**الملف:** `lib/main.dart:96`
```dart
Future<Store> _openMainStore() async {
  await loadObjectBoxLibraryAndroidCompat();
  final directoryPath = (await defaultStoreDirectory()).path;

  if (Store.isOpen(directoryPath)) {
    debugPrint('[main] ObjectBox store already open, attaching to it');
    return Store.attach(getObjectBoxModel(), directoryPath);
  }

  const maxAttempts = 10;
  const baseDelay = Duration(milliseconds: 500);
  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await openStore(directory: directoryPath);
    } catch (e) {
      if (e.toString().contains('another store is still open') &&
          attempt < maxAttempts) {
        final delay = baseDelay * attempt;
        debugPrint(
          '[main] Store lock held by another isolate '
          '(attempt $attempt/$maxAttempts), retrying in ${delay.inMilliseconds}ms...',
        );
        await Future.delayed(delay);
      } else {
        rethrow;
      }
    }
  }
  throw StateError('Failed to open ObjectBox store after $maxAttempts attempts');
}
```

---

## 5. الـ Logs والتشخيص المباشر

### 14. عند تشغيل التطبيق بوضع debug مع `flutter run`، هل تظهر أي رسالة خطأ؟
لا يمكن تحديد ذلك بدون تشغيل فعلي. لكن هناك نقطة مهمة:

**الملف:** `lib/main.dart:72-86`
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch unhandled errors during initialization
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  try {
    await _initApp();
  } catch (e, stackTrace) {
    debugPrint('App initialization failed: $e\n$stackTrace');
    initError = 'App initialization failed: $e';
  }
}
```

**المشكلة:** إذا فشل `_initApp()` (مثلاً بسبب `rethrow` من ObjectBox)، فإن `initError` يُضبط، لكن **لا يتم استدعاء `runApp()` إطلاقاً**، مما يعني أن التطبيق يتوقف تماماً دون عرض أي واجهة (أو يعرض شاشة بيضاء).

### 15. هل أضفت `print` أو `debugPrint` قبل وبعد كل خطوة رئيسية في splash؟
نعم، هناك `debugPrint` في معظم العمليات، لكن **لا يوجد `debugPrint` يوضح متى تكتمل `_initApp()` بنجاح** ومتى يتم استدعاء `runApp()`.

**المقترح:** أضف `debugPrint` قبل وبعد:
- بداية ونهاية `_initApp()`
- قبل `runApp()`

### 16. هل الفحص تم على الجهاز الحقيقي فقط أم أيضًا على المحاكي؟
هذا سؤال يتطلب اختبار فعلي.

### 17. هل تحدث المشكلة دائمًا (100% من المرات) أم أحيانًا فقط؟
هذا سؤال يتطلب اختبار فعلي. لكن هناك احتمال **Race Condition** في:
- `AuthService._internal()` يُستدعى قبل `RevenueCatService` يُستدعى
- `authService.authStateChanges()` قد يُطلق حدث قبل أن `revenueCatService` يكون جاهزاً

---

## 6. الفرق بين debug و release

### 18. هل جربت تشغيل نسخة `--release` أو `--profile`؟
هذا سؤال يتطلب اختبار فعلي.

### 19. هل هناك أي `Platform Channel` مخصص يُستدعى من splash؟
لا يوجد `Platform Channel` مخصص في الكود المعروض. لكن:
- `Workmanager` يستخدم platform channels داخلياً
- `RevenueCat` (Purchases Flutter) يستخدم platform channels
- `Firebase` يستخدم platform channels

---

## 7. التغييرات الأخيرة

### 20. متى بالضبط بدأت المشكلة بالظهور؟
هذا سؤال يتطلب مراجعة git history.

### 21. هل تم تعديل أي شيء في `main.dart`؟
هذا سؤال يتطلب مراجعة git history. لكن بناءً على الكود الحالي، هناك **نقاط مهمة**:

1. **`WidgetsFlutterBinding.ensureInitialized()`** موجود (السطر 73) - جيد
2. **ترتيب استدعاءات `runApp`** صحيح
3. **المشكلة المحتملة:** `_initApp()` غير متزامنة وتحتوي على `rethrow` في ObjectBox

---

## الاستنتاج الأولي

### الأسباب المحتملة للتوقف عند Splash:

1. **السبب الأكثر احتمالاً:** `rethrow` في ObjectBox initialization (`main.dart:176`) يوقف `_initApp()` بالكامل، مما يمنع استدعاء `runApp()`.

2. **السبب الثاني:** RevenueCat SDK (`Purchases.getCustomerInfo()`) يعلق بدون timeout في حالة عدم وجود اتصال شبكي.

3. **السبب الثالث:** Race Condition بين `AuthService` و `RevenueCatService` - `AuthService` يُستدعى أولاً ويُشغل `authStateChanges()`، لكن `RevenueCatService` لا يزال في حالة `loading`، مما يبقي `redirect` في `GoRouter` يُعيد `'/'` للأبد.

### الحلول المقترحة:

1. **إزالة `rethrow` من ObjectBox initialization:**
```dart
try {
  store = await _openMainStore();
} catch (e) {
  debugPrint('ObjectBox initialization failed: $e');
  if (initError == null) initError = 'ObjectBox initialization failed: $e';
  // لا تعيد رمي الاستثناء! اسمح للتطبيق بالمتابعة
}
```

2. **إضافة timeout لـ RevenueCat:**
```dart
try {
  _customerInfo = await Purchases.getCustomerInfo().timeout(
    const Duration(seconds: 10),
  );
  _updatePremiumStatus();
} catch (e) {
  debugPrint('Failed to get customer info: $e');
}
```

3. **إضافة `debugPrint` لتتبع تقدم `_initApp()`:**
```dart
Future<void> _initApp() async {
  debugPrint('[init] Starting _initApp');
  // ... كل خطوة
  debugPrint('[init] _initApp completed successfully');
}
```
