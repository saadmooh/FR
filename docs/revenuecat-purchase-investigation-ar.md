# تقرير فحص مشكلة RevenueCat + Google Play Billing

> تاريخ الفحص: 2026-08-25
> النطاق: فحص الكود فقط — لم يتم تعديل أي ملف. بانتظار التأكيد قبل تطبيق الإصلاح.

---

## الخلاصة التنفيذية (الاحتمال الأرجح)

**`Purchases.logIn()` غير موجود إطلاقًا في المشروع كله (صفر استدعاءات).**
المستخدم يشتري وهو **anonymous** في RevenueCat (`$RCAnonymousID:...`)، وهويته
الحقيقية (Firebase/Supabase) لا تُربط بهوية RevenueCat أبدًا. الشراء يُسجَّل على
هوية مجهولة قابلة للضياع، وعند فقدانها (إعادة تثبيت / مسح بيانات / فشل مزامنة
الإيصال) يفقد RevenueCat القدرة على ربط الاشتراك بالمستخدم — بينما Google Play
يعتبر الاشتراك قائمًا (لذلك يصلك إيميل التأكيد).

هذا يفسّر بالضبط لماذا `getCustomerInfo()` عند كل launch يعيد "لا اشتراك نشط"
رغم وصول إيميل الشراء من Google.

---

## 1) استدعاءات `Purchases.logIn()` و `Purchases.logOut()`

| الدالة | الموقع | الحالة |
|---|---|---|
| `Purchases.logIn()` | — | **غير موجودة نهائيًا في المشروع** |
| `Purchases.configure()` | `lib/services/revenuecat_service.dart:21` | داخل `initialize()` فقط |
| `Purchases.logOut()` | `lib/services/revenuecat_service.dart:79` | داخل `RevenueCatService.logout()` |

تفاصيل حاسمة:

- **`configure()` لا تُستدعى بعد تسجيل دخول** ولا بعده — لا يوجد أي ربط هوية.
- **`RevenueCatService.logout()` (سطر 77–84) ليس لها أي مستدٍ في المشروع
  كله.** زر "Sign Out" في `lib/screens/settings_screen.dart:300` يستدعي
  `widget.authService.signOut()` فقط (Firebase + Google + Supabase — راجع
  `lib/services/auth_service.dart:65-75`) ولا يمس RevenueCat إطلاقًا.
- **إجابة سؤالك المباشر: نعم، المستخدم يشتري وهو anonymous بنسبة 100%.**

تسلسل الشراء الفعلي في الكود:

```
main.dart:120        → configure() → يُنشأ App User ID مجهول ($RCAnonymousID:...)
login_screen.dart:23 → تسجيل دخول Google → Firebase/Supabase فقط، RevenueCat لا يعلم
login_screen.dart:26 → فحص isPremium (false لأن الهوية المجهولة جديدة)
paywall_screen.dart:56 → purchasePackage() → الشراء يتم تحت الهوية المجهولة
(لا logIn بعدها أبدًا)
```

## 2) ترتيب التهيئة في `main.dart`

- `lib/main.dart:119-120`: `revenueCatService = RevenueCatService(); await revenueCatService.initialize();`
- هذا يحدث **قبل** استعادة جلسة Supabase/Firebase (`lib/main.dart:123-136`)
  — لكن هذا ليس هو الخطر هنا، لأنه حتى لو عُرفت حالة الدخول، لا يوجد كود
  `logIn()` ليُنفَّذ أصلًا.
- **لا يوجد خطر configure مزدوج**: `initialize()` تُستدعى مرة واحدة فقط من
  `main`. حتى `_reopenStore()` عند العودة من الخلفية (`lib/main.dart:365-405`)
  تعيد بناء الـ router فقط ولا تعيد تهيئة RevenueCat. ✅

## 3) نقاط debugPrint المقترحة (لم تُطبَّق بعد)

المواقع المحددة عند موافقتك:

1. `lib/services/revenuecat_service.dart:24` — بعد `getCustomerInfo()` مباشرة:
   ```dart
   debugPrint('App User ID: ${await Purchases.appUserID}');
   debugPrint('Is Anonymous: ${await Purchases.isAnonymous}');
   ```
2. `lib/services/revenuecat_service.dart:37-39` — داخل `_updatePremiumStatus()`:
   ```dart
   debugPrint('All entitlements: ${_customerInfo?.entitlements.all}');
   debugPrint('Active entitlements: ${_customerInfo?.entitlements.active}');
   ```
3. `lib/services/revenuecat_service.dart:30-33` — داخل listener التحديثات.
4. `lib/screens/paywall_screen.dart:57` — بعد نجاح الشراء مباشرة.

ملاحظة تقنية: `Purchases.appUserID` و `isAnonymous` خصائص getter وليست Future
في purchases_flutter الحالية — الصيغة ستكون:
```dart
debugPrint('App User ID: ${Purchases.appUserID}');
debugPrint('Is Anonymous: ${Purchases.isAnonymous}');
```

## 4) فحص `paywall_screen.dart` بعد الشراء

- `lib/screens/paywall_screen.dart:56-58`: الكود يفحص **فقط**
  `entitlements.active['premium']` — **لا يطبع `entitlements.all` إطلاقًا.**
- اكتشاف إضافي مهم في نفس الدالة:
  - إذا رجع الرد بدون entitlement نشط، الكود **يتجاهل الأمر بصمت** (لا رسالة
    خطأ ولا success) — فقط `setState(() => _isLoading = false)` في سطر 85.
  - رسالة "فشل الشراء" تظهر **فقط عند رمي استثناء** (سطر 71-82).
  - بما أنك ترى "فشل الشراء" مع وصول إيميل Google، فهذا يعني أن
    `purchasePackage()` **يرمي استثناءً** بعد إتمام عملية Google Play نفسها.
    أشهر سببين مطابقين لهذا السلوك:
    1. فشل إرسال/معالجة الإيصال على خوادم RevenueCat (مشكلة API key أو ربط
       التطبيق في Dashboard)، أو
    2. محاولة شراء متكررة لمنتج مملوك مسبقًا ("already owned") — أي أن
       الاشتراك موجود فعليًا لكن تحت هوية/إيصال لا يستطيع الكود قراءته.
- ملاحظة معمارية: الـ paywall يستدعي `Purchases` مباشرة بدل المرور عبر
  `RevenueCatService.purchasePackage()` (سطر 54-64 في الخدمة)، فيوجد منطق
  مكرر ومسارَان مختلفان لنفس العملية.

## 5) هل يوجد ما يصفّر هوية المستخدم؟

- **لا شيء في الكود** يستدعي `logOut()` أو يعيد `configure()` بعد الدخول.
- الخطر الحقيقي خارج الكود: هوية `$RCAnonymousID` تُخزَّن محليًا وتضيع عند
  إعادة التثبيت أو مسح بيانات التطبيق — وبما أن الشراء مرتبط بها وبدون
  `logIn()`، يصبح الاشتراك **يتيمًا نهائيًا** من منظور RevenueCat.

## 6) الحكم على التسلسل configure → logIn → purchase

**التسلسل الحالي غير مكتمل ومنطوق الخطأ:**

```
configure (anonymous) → [logIn مفقود!] → purchase (تحت هوية مجهولة)
```

### الاحتمالات مرتبة تنازليًا:

1. **الأرجح — غياب `logIn()` تمامًا** + الشراء تحت هوية مجهولة ضاعت (إعادة
   تثبيت/مسح بيانات) أو فشل مزامنة إيصال الشراء إلى RevenueCat. مدعوم بـ:
   صفر استدعاءات logIn في المشروع، وظهور "فشل الشراء" (استثناء فعلي) رغم
   تأكيد Google.
2. **محتمل — عدم تطابق معرّف الـ entitlement**: الكود يتطلب الاسم الحرفي
   `'premium'` في `lib/services/revenuecat_service.dart:10` و
   `lib/screens/paywall_screen.dart:58,93`. إذا كان المعرف في Dashboard
   مختلفًا (حالة أحرف/اسم آخر) ستظهر نفس الأعراض تمامًا.
3. **محتمل — عدم تطابق مشروع RevenueCat**: الـ API key المكتوب يدويًا في
   `lib/services/revenuecat_service.dart:9` يجب أن يكون لنفس المشروع الذي
   مربوط فيه تطبيق Google Play ونفس المنتجات.

### الإصلاح المقترح (بعد تأكيدك):

1. استدعاء `await Purchases.logIn(firebaseUid)` فور نجاح تسجيل الدخول في
   `auth_service.dart` (بعد سطر 39) وفور استعادة الجلسة في `main.dart`
   (بعد سطر 123).
2. استدعاء `RevenueCatService().logout()` داخل `AuthService.signOut()`.
3. إضافة debug logging في الموارد المذكورة أعلاه (بند 3 و4).
4. معالجة خطأ "already purchased" باستدعاء `restorePurchases()` تلقائيًا.
5. توحيد مسار الشراء عبر `RevenueCatService` بدل الاستدعاء المباشر في الـ paywall.

> ⚠️ ملاحظة أمنية جانبية: `lib/services/revenuecat_service.dart:9` يحتوي
> Google public SDK key مكتوبًا بشكل ثابت في الكود — مقبول نسبيًا لأنه
> public key، لكن يُفضَّل نقله إلى `--dart-define` مثل بقية المفاتيح.

**بانتظار تأكيدك قبل تطبيق أي تعديل.**

---

# سجل التطبيق (تم التنفيذ بعد التأكيد)

## التعديلات المطبَّقة فعليًا

### 1. `lib/services/revenuecat_service.dart`
- **`linkToUser(String firebaseUid)`** (سطر ~75): يتحقق أن المستخدم anonymous،
  ثم `Purchases.logIn(firebaseUid)` ويحدّث `_customerInfo` من
  `result.customerInfo`، ثم يستدعي `restoreAfterLogin()` تلقائيًا إذا لم يكن
  premium (لاستعادة المشتريات اليتيمة من نفس حساب Google Play).
- **`restoreAfterLogin()`** (سطر ~100): استعادة + تسجيل الـ entitlements
  النشطة + تحديث الحالة.
- **`purchasePackage()`** (سطر ~59): أعادت تغيير التوقيع إلى
  `Future<CustomerInfo?>` مع `rethrow` بعد التسجيل — الـ paywall يتولى عرض
  رسائل الخطأ بنفسه. رُحِّلت أيضًا إلى الـ API غير المهجور:
  `Purchases.purchase(PurchaseParams.package(package))`.
- **debug logging**: طباعة `App User ID` و `Is Anonymous` في `initialize()`
  (سطر 23-24)، وطباعة `entitlements.all` و `.active` داخل
  `_updatePremiumStatus()` (سطر 41-42).
- **`logout()`** (سطر ~122): أصبح يتخطى `logOut()` بأمان عندما يكون المستخدم
  anonymous (لأن الـ API يرمي استثناءً في هذه الحالة)، ويصفّر `_customerInfo`.

### 2. `lib/services/auth_service.dart`
- بعد نجاح `signInWithCredential` مباشرة: `RevenueCatService().linkToUser(user.uid)`
- في `signOut()`: `await RevenueCatService().logout()` أولًا.

### 3. `lib/main.dart` (سطر 138-143)
- عند cold start مع جلسة محفوظة (دون تسجيل دخول جديد): إعادة الربط عبر
  `revenueCatService.linkToUser(rcFirebaseUser.uid)`.

### 4. `lib/screens/paywall_screen.dart`
- الشراء يتم الآن عبر `RevenueCatService().purchasePackage()` (توحيد المسار).
- **لا تجاهل صامت**: إذا اكتمل الشراء بلا entitlement نشط → محاولة
  `restoreAfterLogin()` ثم رسالة خطأ صريحة إن فشلت.
- **معالجة الإلغاء**: `PlatformException` يُحوَّل عبر
  `PurchasesErrorHelper.getErrorCode`، وإلغاء المستخدم لا يُظهر "فشل الشراء".
- دوال مساعدة: `_showSuccessAndClose()` و `_showError()`.

## ملاحظات API (purchases_flutter 10.7.0)
- `Purchases.appUserID` و `isAnonymous` كلاهما **Future** (يلزم `await`).
- `logIn()` يعيد `LogInResult{created, customerInfo}`.
- `logOut()` يرمي استثناءً إذا كان المستخدم anonymous.

## خطوات الاختبار الموصى بها
1. سجّل دخول بحساب Google → راقب اللوق:
   `RevenueCat logIn success` ثم `Is Anonymous: false`.
2. اشترِ باقة → يجب ظهور `premium` في Active entitlements.
3. أغلق التطبيق بالكامل وافتحه (cold start) → `Premium status: true`
   دون المرور بشاشة الدخول.
4. جرّب Sign Out ثم Sign In بنفس الحساب → الاشتراك يبقى مرتبطًا.
5. لحالة "المشتري الضائع" القديم: سجّل دخول → يجب أن تستعيد
   `restoreAfterLogin()` اشتراكه من حساب Google Play نفسه.

## نتائج الفحص بعد التعديل
- `flutter analyze`: لا أخطاء في الملفات المعدَّلة (الملاحظات المتبقية
  pre-existing وغير متعلقة).
- `flutter test`: جميع الاختبارات ناجحة.
