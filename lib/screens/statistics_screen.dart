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
    final analysis = await widget.aiService.analyzeStats({
      'total': total,
      'opened': opened,
      'missed': missed,
    });

    if (mounted) {
      setState(() => _aiAnalysis = analysis);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.reminderRepository.getTotalCount();
    final opened = widget.reminderRepository.getOpenedCount();
    final pending = widget.reminderRepository.getUnread().length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Statistics',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent)),
            )
          : RefreshIndicator(
              onRefresh: () async => _loadStats(),
              color: AppColors.accent,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary row
                    SizedBox(
                      height: 130,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          SizedBox(
                            width: 110,
                            child: StatCard(
                              icon: Icons.bookmark,
                              value: total.toString(),
                              label: 'Total',
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 110,
                            child: StatCard(
                              icon: Icons.check_circle,
                              value: opened.toString(),
                              label: 'Opened',
                              color: AppColors.success,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 110,
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
                    const SizedBox(height: 24),

                    // AI Analysis
                    if (_aiAnalysis.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.auto_awesome, color: AppColors.accent, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'AI Insights',
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ..._aiAnalysis.split('|').map((part) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  part.trim(),
                                  style: const TextStyle(color: AppColors.textSecondary),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Category breakdown
                    const Text(
                      'Category Breakdown',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_categoryStats.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'No data yet',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    else
                      ..._categoryStats.map((stat) => _buildCategoryRow(stat)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCategoryRow(CategoryStatistic stat) {
    final openRate = stat.totalCount > 0 ? stat.openedCount / stat.totalCount : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
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
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${stat.openedCount}/${stat.totalCount}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: openRate,
              backgroundColor: AppColors.surfaceLight,
              valueColor: AlwaysStoppedAnimation<Color>(
                openRate > 0.7 ? AppColors.success : openRate > 0.4 ? AppColors.warning : AppColors.error,
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(openRate * 100).toStringAsFixed(0)}% opened',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
