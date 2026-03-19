import 'package:flutter/material.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/category_statistic_repository.dart';
import '../services/ai_service.dart';
import '../models/category_statistic.dart';
import '../widgets/stat_card.dart';
import '../core/app_theme.dart';

class StatisticsScreen extends StatefulWidget {
  final ReminderRepository reminderRepository;
  final CategoryStatisticRepository categoryStatRepository;
  final AIService aiService;

  const StatisticsScreen({
    super.key,
    required this.reminderRepository,
    required this.categoryStatRepository,
    required this.aiService,
  });

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  List<CategoryStatistic> _categoryStats = [];
  String _aiAnalysis = '';
  bool _isLoading = true;
  String? _analyzingCategoryId;
  final Map<int, Map<String, dynamic>> _categoryAnalysis = {};

  void _showResult(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '✅ $message' : '❌ $message'),
        backgroundColor: success ? AppColors.whiteAccent : AppColors.error,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() {
    final total = widget.reminderRepository.getTotalCount();
    final opened = widget.reminderRepository.getOpenedCount();
    final missed = widget.reminderRepository.getMissed().length;

    final stats = widget.categoryStatRepository.getAll();

    setState(() {
      _categoryStats = stats;
      _isLoading = false;
    });

    _loadAIAnalysis(total, opened, missed);
  }

  Future<void> _loadAIAnalysis(int total, int opened, int missed) async {
    try {
      final analysis = await widget.aiService.analyzeStats({
        'total': total,
        'opened': opened,
        'missed': missed,
      });
      _showResult(true, 'Stats: $analysis');

      if (mounted) {
        setState(() => _aiAnalysis = analysis);
      }
    } catch (e) {
      if (mounted) {
        _showResult(false, 'Error: $e');
      }
    }
  }

  Future<void> _analyzeCategory(CategoryStatistic stat) async {
    if (_analyzingCategoryId != null) return;

    setState(() => _analyzingCategoryId = stat.id.toString());

    try {
      final result = await widget.aiService.analyzeCategoryStatistics(stat);

      if (mounted) {
        setState(() {
          _categoryAnalysis[stat.id] = result;
          _analyzingCategoryId = null;
        });
        _showResult(true, 'Analysis complete');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _analyzingCategoryId = null);
        _showResult(false, 'Analysis failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.reminderRepository.getTotalCount();
    final opened = widget.reminderRepository.getOpenedCount();
    final pending = widget.reminderRepository.getUnread().length;

    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      appBar: AppBar(
        title: const Text(
          'Statistics',
          style: TextStyle(
            color: AppColors.whiteTextPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        backgroundColor: AppColors.whiteBackground,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.whiteAccent),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.whiteAccent,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => _loadStats(),
              color: AppColors.whiteAccent,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 140,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          SizedBox(
                            width: 115,
                            child: StatCard(
                              icon: Icons.bookmark,
                              value: total.toString(),
                              label: 'Total',
                              color: AppColors.whiteAccent,
                            ),
                          ),
                          const SizedBox(width: 14),
                          SizedBox(
                            width: 115,
                            child: StatCard(
                              icon: Icons.check_circle,
                              value: opened.toString(),
                              label: 'Opened',
                              color: AppColors.success,
                            ),
                          ),
                          const SizedBox(width: 14),
                          SizedBox(
                            width: 115,
                            child: StatCard(
                              icon: Icons.schedule,
                              value: pending.toString(),
                              label: 'Pending',
                              color: AppColors.warning,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    if (_aiAnalysis.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.whiteSurface,
                          borderRadius: BorderRadius.zero,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.whiteAccent.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.auto_awesome,
                                    color: AppColors.whiteAccent,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'AI Insights',
                                  style: TextStyle(
                                    color: AppColors.whiteTextPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            ..._aiAnalysis.split('|').map((part) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  part.trim(),
                                  style: const TextStyle(
                                    color: AppColors.whiteTextSecondary,
                                    height: 1.5,
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    const SizedBox(height: 28),

                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.whiteAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.pie_chart,
                            color: AppColors.whiteAccent,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Category Breakdown',
                          style: TextStyle(
                            color: AppColors.whiteTextPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    if (_categoryStats.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 48,
                                color: AppColors.whiteTextSecondary.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No data yet',
                                style: TextStyle(
                                  color: AppColors.whiteTextSecondary,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._categoryStats.map((stat) => _buildCategoryRow(stat)),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCategoryRow(CategoryStatistic stat) {
    final openRate = stat.totalCount > 0
        ? stat.openedCount / stat.totalCount
        : 0.0;
    final analysis = _categoryAnalysis[stat.id];
    final isAnalyzing = _analyzingCategoryId == stat.id.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.whiteSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${stat.categoryEn} (${stat.complexityEn})',
                  style: const TextStyle(
                    color: AppColors.whiteTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.whiteAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${stat.openedCount}/${stat.totalCount}',
                  style: const TextStyle(
                    color: AppColors.whiteAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isAnalyzing)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.whiteAccent,
                    ),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(
                    Icons.analytics_outlined,
                    color: AppColors.whiteAccent,
                  ),
                  onPressed: () => _analyzeCategory(stat),
                  tooltip: 'Analyze',
                ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: openRate,
              backgroundColor: AppColors.whiteBorder,
              valueColor: AlwaysStoppedAnimation<Color>(
                openRate > 0.7
                    ? AppColors.success
                    : openRate > 0.4
                    ? AppColors.warning
                    : AppColors.error,
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(openRate * 100).toStringAsFixed(0)}% opened',
            style: const TextStyle(
              color: AppColors.whiteTextSecondary,
              fontSize: 12,
            ),
          ),
          if (analysis != null) ...[
            const SizedBox(height: 16),
            Divider(color: AppColors.whiteBorder, height: 1),
            const SizedBox(height: 14),
            _buildAnalysisResults(analysis),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisResults(Map<String, dynamic> analysis) {
    final analysisText = analysis['analysis'] as String? ?? '';
    final preferredTimes = analysis['preferred_times'] as List<dynamic>? ?? [];
    final confidenceScore = analysis['confidence_score'] as num? ?? 0.0;
    final insights = analysis['insights'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.whiteAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: AppColors.whiteAccent,
                size: 14,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Analysis',
              style: TextStyle(
                color: AppColors.whiteTextPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        if (analysisText.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            analysisText,
            style: const TextStyle(
              color: AppColors.whiteTextSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
        if (preferredTimes.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'Preferred Times',
            style: TextStyle(
              color: AppColors.whiteTextPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: preferredTimes
                .map(
                  (time) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.whiteAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      time.toString(),
                      style: const TextStyle(
                        color: AppColors.whiteAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        if (confidenceScore > 0) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                'Confidence: ',
                style: TextStyle(
                  color: AppColors.whiteTextSecondary,
                  fontSize: 12,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${(confidenceScore * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (insights.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'Insights',
            style: TextStyle(
              color: AppColors.whiteTextPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          ...insights.map(
            (insight) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(
                      color: AppColors.whiteAccent,
                      fontSize: 14,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      insight.toString(),
                      style: const TextStyle(
                        color: AppColors.whiteTextSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
