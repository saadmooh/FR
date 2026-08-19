# خطة تنفيذ الإحصائيات الخوارزمية (بدون AI)

## الهدف
استبدال تحليل الإحصائيات القائم على AI في `StatisticsScreen` بحسابات خوارزمية تعمل على الجهاز وتتم تشغيلها في الخلفية بعد كل إعادة جدولة للمنشورات.

## القرارات المتخذة
1. **النطاق**: استبدال تحليل AI بالكامل (إزالة استدعاءات `AIService.analyzeStats` و `analyzeCategoryStatistics`)
2. **التحليلات**: جميع الأنواع الستة - أوقات النشاط القصوى، أنماط الفئات، الاتجاهات، وقت الفتح، أنماط الإخفاق، التوصيات
3. **الحساب**: خدمة خلفية تُشغل بعد إعادة جدولة المنشورات
4. **التخزين**: توسيع كيان `CategoryStatistic` بحقول جديدة

## خطوات التنفيذ

### 1. توسيع كيان CategoryStatistic (`lib/models/category_statistic.dart`)
إضافة حقول جديدة لنتائج الخوارزمية:
```dart
// نتائج التحليل الخوارزمي
String? preferredTimesJson;           // مصفوفة JSON بأوقات "HH:00-HH:59"
String? insightsJson;                 // مصفوفة JSON بالرؤى المكتشفة
double? algorithmicConfidenceScore;   // درجة ثقة 0.0-1.0
String? peakActivityHoursJson;        // ساعات النشاط القصوى عالمياً
String? peakActivityDaysJson;         // أيام النشاط القصوى عالمياً
String? missedPatternsJson;           // أنماط الإخفاق
String? recommendationsJson;          // توصيات الجدولة
@Property(type: PropertyType.date)
DateTime? lastAlgorithmicAnalysis;    // تاريخ آخر تحليل
```

### 2. إنشاء AlgorithmicAnalysisService (`lib/services/algorithmic_analysis_service.dart`)
خدمة جديدة بالطرق التالية:
- `analyzeAllCategories(Box<CategoryStatistic>, Box<Reminder>)` - نقطة الدخول الرئيسية
- `analyzeGlobalPatterns(List<Reminder>)` - أوقات/أيام الذرة، الاتجاهات
- `analyzeCategory(CategoryStatistic, List<Reminder>)` - تحليل كل فئة
- `computeTimeToOpenStats(List<Reminder>)` - متوسط ثوانٍ للفتح حسب الفئة/التعقيد
- `computeMissedPatterns(List<Reminder>)` - متى تنتهي التذكيرات دون قراءة
- `generateRecommendations(CategoryStatistic, globalPatterns)` - أوقات جدولة مثلى

**تفاصيل الخوارزميات:**
- **النشاط القصوى**: تحليل تكرار `openedAt.hour` و `weekday` عبر جميع التذكيرات المفتوحة
- **أنماط الفئات**: استخدام `openedHoursJson`/`openedDaysJson` الموجودة، إيجاد أعلى 3 ساعات/أيام
- **الاتجاهات**: مقارنة معدلات الفتح على نوافذ 7 أيام متحركة
- **وقت الفتح**: تجميع حسب الفئة+التعقيد، حساب الوسيط (مقاوم للقيم الشاذة)
- **أنماط الإخفاق**: تكرار `scheduledAt.hour`/`weekday` للتذكيرات المنتهية غير المقروءة
- **التوصيات**: ربط النشاط القصوى بأوقات فراغ المستخدم

### 3. تكامل المشغل الخلفي
العثور على مكان حدوث إعادة الجدولة (غالباً في `ReminderRepository` أو خدمة) والاستدعاء:
```dart
// بعد إعادة جدولة ناجحة
await AlgorithmicAnalysisService.instance.analyzeAllCategories();
```

النظر في استخدام `Isolate` أو `compute()` للحسابات الثقيلة لتجنب تجميد الواجهة.

### 4. تحديث CategoryStatisticRepository
إضافة طرق لحفظ/استرجاع النتائج الخوارزمية:
- `saveAlgorithmicAnalysis(CategoryStatistic stat, AlgorithmicResults results)`
- `getAlgorithmicAnalysis(int statId)` - إرجاع النتائج محللة

### 5. تحديث StatisticsScreen (`lib/screens/statistics_screen.dart`)
- إزالة تبعية `AIService` وطرق `_loadAIAnalysis`، `_analyzeCategory`
- إزالة بطاقة "AI Insights" (أسطر 199-259)
- استبدال زر تحليل الفئة (أسطر 391-398) بعرض النتائج المحسوبة مسبقاً
- عرض `preferredTimesJson`، `insightsJson`، `algorithmicConfidenceScore` من `CategoryStatistic`
- إضافة مؤشر "آخر تحليل: {التاريخ}"

### 6. تحديث main.dart / حقن التبعيات
- تسجيل `AlgorithmicAnalysisService` كـ singleton
- إزالة `AIService` من مُنشئ `StatisticsScreen`

### 7. تشغيل توليد الكود
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 8. استراتيجية الهجرة
- نشر تغييرات الكيان أولاً
- سجلات `CategoryStatistic` الحالية ستكون حقول خوارزمية = null
- الخدمة الخلفية تملأها في التشغيل التالي
- الواجهة تتعامل مع null بأمان (تعرض "لم يتم التحليل بعد" أو تحسب عند الطلب كبديل)

## الملفات المراد تعديلها
1. `lib/models/category_statistic.dart` - إضافة حقول جديدة
2. `lib/services/algorithmic_analysis_service.dart` - ملف جديد
3. `lib/repositories/category_statistic_repository.dart` - إضافة طرق حفظ/استرجاع
4. `lib/screens/statistics_screen.dart` - إزالة AI، عرض نتائج خوارزمية
5. `lib/main.dart` - تحديث DI

## التحقق
- تشغيل `flutter analyze` و `flutter test`
- الاختبار ببيانات نموذجية: إنشاء تذكيرات بساعات/أيام مختلفة، التحقق من صحة التحليل
- التحقق من أن الحساب الخلفي لا يعيق الواجهة
- تأكيد التعامل مع null للفئات غير المحللة

## المخاطر
- هجرة مخطط ObjectBox: الحقول الجديدة nullable، لذا متوافقة مع الإصدارات السابقة
- توقيت الحساب الخلفي: التأكد من تشغيله بعد اكتمال إعادة الجدولة
- أداء البيانات الكبيرة: استخدام Isolate إذا معالجة >1000 تذكير