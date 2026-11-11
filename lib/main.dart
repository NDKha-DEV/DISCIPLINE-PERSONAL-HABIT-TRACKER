import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const DisciplineApp());
}

enum HabitFrequency { daily, weekly, custom }

class Habit {
  Habit({
    required this.id,
    required this.name,
    required this.description,
    required this.frequency,
    required this.selectedDays,
    required this.reminderTime,
    required this.reminderEnabled,
    required this.createdAt,
    required this.isActive,
  });

  final String id;
  final String name;
  final String description;
  final HabitFrequency frequency;
  final List<int> selectedDays;
  final TimeOfDay reminderTime;
  final bool reminderEnabled;
  final DateTime createdAt;
  final bool isActive;

  String get frequencyLabel {
    switch (frequency) {
      case HabitFrequency.daily:
        return 'Hàng ngày';
      case HabitFrequency.weekly:
        return 'Các ngày trong tuần';
      case HabitFrequency.custom:
        return 'Tùy chọn thứ trong tuần';
    }
  }

  String get selectedDayLabel {
    if (selectedDays.isEmpty) {
      return 'Chưa chọn ngày';
    }
    final days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return selectedDays.map((day) => days[day - 1]).join(', ');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'frequency': frequency.name,
      'selectedDays': selectedDays,
      'reminderTime': '${reminderTime.hour}:${reminderTime.minute}',
      'reminderEnabled': reminderEnabled,
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive,
    };
  }

  factory Habit.fromJson(Map<String, dynamic> json) {
    final rawTime = (json['reminderTime'] ?? '9:00').toString();
    final parts = rawTime.split(':');
    final hour = int.tryParse(parts.first) ?? 9;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    return Habit(
      id: json['id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      frequency: HabitFrequency.values.firstWhere(
        (value) => value.name == (json['frequency'] ?? HabitFrequency.daily.name),
        orElse: () => HabitFrequency.daily,
      ),
      selectedDays: List<int>.from(json['selectedDays'] ?? const <int>[]),
      reminderTime: TimeOfDay(hour: hour, minute: minute),
      reminderEnabled: json['reminderEnabled'] ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] ?? DateTime.now().toIso8601String()) ?? DateTime.now(),
      isActive: json['isActive'] ?? true,
    );
  }
}

class HabitSummary {
  const HabitSummary({
    required this.expected,
    required this.completed,
    required this.remaining,
    required this.percent,
  });

  final int expected;
  final int completed;
  final int remaining;
  final double percent;
}

class HabitProvider extends ChangeNotifier {
  HabitProvider() {
    initialize();
  }

  static const String _habitsKey = 'discipline_habits_v1';
  static const String _completionKey = 'discipline_completions_v1';
  static const String _permissionKey = 'discipline_reminder_permission_v1';

  final List<Habit> _habits = [];
  final Map<String, bool> _completionMap = {};
  bool _webReminderPermission = false;

  List<Habit> get habits => List.unmodifiable(_habits);
  bool get webReminderPermission => _webReminderPermission;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final habitsJson = prefs.getString(_habitsKey);
    if (habitsJson != null && habitsJson.isNotEmpty) {
      final decoded = jsonDecode(habitsJson) as List<dynamic>;
      _habits
        ..clear()
        ..addAll(decoded.map((item) => Habit.fromJson(item as Map<String, dynamic>)));
    }

    final completionJson = prefs.getString(_completionKey);
    if (completionJson != null && completionJson.isNotEmpty) {
      final decoded = jsonDecode(completionJson) as Map<String, dynamic>;
      _completionMap
        ..clear()
        ..addAll(decoded.map((key, value) => MapEntry(key, value as bool)));
    }

    _webReminderPermission = prefs.getBool(_permissionKey) ?? false;
    notifyListeners();
  }

  Future<void> addHabit(Habit habit) async {
    _habits.add(habit);
    await _persistHabits();
    notifyListeners();
  }

  Future<void> updateHabit(Habit updatedHabit) async {
    final index = _habits.indexWhere((habit) => habit.id == updatedHabit.id);
    if (index >= 0) {
      _habits[index] = updatedHabit;
      await _persistHabits();
      notifyListeners();
    }
  }

  Future<void> deleteHabit(String habitId) async {
    _habits.removeWhere((habit) => habit.id == habitId);
    final removalKeys = _completionMap.keys.where((key) => key.startsWith('$habitId|')).toList();
    for (final key in removalKeys) {
      _completionMap.remove(key);
    }
    await _persistHabits();
    await _persistCompletions();
    notifyListeners();
  }

  Future<void> toggleCompletion(String habitId, DateTime date) async {
    final habit = _habits.firstWhere(
      (item) => item.id == habitId,
      orElse: () => Habit(
        id: '',
        name: '',
        description: '',
        frequency: HabitFrequency.daily,
        selectedDays: const [],
        reminderTime: const TimeOfDay(hour: 9, minute: 0),
        reminderEnabled: false,
        createdAt: DateTime.now(),
        isActive: true,
      ),
    );
    if (habit.id.isEmpty || !habit.isActive) {
      return;
    }

    final safeDate = _normalizedDate(date);
    final key = _completionKeyFor(habitId, safeDate);
    if (_completionMap[key] == true) {
      _completionMap.remove(key);
    } else {
      _completionMap[key] = true;
    }
    await _persistCompletions();
    notifyListeners();
  }

  bool isCompleted(String habitId, DateTime date) {
    return _completionMap[_completionKeyFor(habitId, _normalizedDate(date))] == true;
  }

  bool matchesHabitDate(Habit habit, DateTime date) {
    final weekday = _normalizedDate(date).weekday;
    switch (habit.frequency) {
      case HabitFrequency.daily:
        return true;
      case HabitFrequency.weekly:
      case HabitFrequency.custom:
        return habit.selectedDays.isEmpty || habit.selectedDays.contains(weekday);
    }
  }

  int expectedCountForDate(DateTime date) {
    final normalized = _normalizedDate(date);
    return _habits.where((habit) => habit.isActive && matchesHabitDate(habit, normalized)).length;
  }

  int completedCountForDate(DateTime date) {
    final normalized = _normalizedDate(date);
    int total = 0;
    for (final habit in _habits) {
      if (habit.isActive && matchesHabitDate(habit, normalized) && isCompleted(habit.id, normalized)) {
        total += 1;
      }
    }
    return total;
  }

  HabitSummary summaryForDate(DateTime date) {
    final expected = expectedCountForDate(date);
    final completed = completedCountForDate(date);
    final remaining = expected - completed;
    final percent = expected == 0 ? 0.0 : (completed / expected) * 100;
    return HabitSummary(
      expected: expected,
      completed: completed,
      remaining: remaining,
      percent: percent,
    );
  }

  Future<void> setReminderPermission(bool enabled) async {
    _webReminderPermission = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permissionKey, enabled);
    notifyListeners();
  }

  String _completionKeyFor(String habitId, DateTime date) {
    return '$habitId|${DateFormat('yyyy-MM-dd').format(date)}';
  }

  DateTime _normalizedDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  Future<void> _persistHabits() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _habits.map((habit) => habit.toJson()).toList();
    await prefs.setString(_habitsKey, jsonEncode(data));
  }

  Future<void> _persistCompletions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_completionKey, jsonEncode(_completionMap));
  }
}

class DisciplineApp extends StatelessWidget {
  const DisciplineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HabitProvider>(
      create: (_) => HabitProvider(),
      child: MaterialApp(
        title: 'Discipline – Personal Habit Tracker',
        debugShowCheckedModeBanner: false,
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF2F6FED),
          scaffoldBackgroundColor: const Color(0xFFF6F8FF),
          appBarTheme: const AppBarTheme(centerTitle: true),
        ),
        home: const RootLayout(),
      ),
    );
  }
}

class RootLayout extends StatefulWidget {
  const RootLayout({super.key});

  @override
  State<RootLayout> createState() => _RootLayoutState();
}

class _RootLayoutState extends State<RootLayout> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    HomeScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) => setState(() => _selectedIndex = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Trang chủ'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Thống kê'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Cài đặt'),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const HabitEditorScreen()),
              ),
              label: const Text('Thêm thói quen'),
              icon: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HabitProvider>();
    final today = DateTime.now();
    final summary = provider.summaryForDate(today);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Discipline',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEEE, d MMMM yyyy', 'vi').format(today),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.sunny_snowing, color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.72),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Tiến độ hôm nay',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                      ),
                      Text(
                        '${summary.completed}/${summary.expected}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LinearProgressIndicator(
                      value: summary.expected > 0 ? summary.completed / summary.expected : 0,
                      minHeight: 12,
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${summary.percent.toStringAsFixed(0)}% hoàn thành',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: provider.habits.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.task_alt_rounded, size: 72, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            'Chưa có thói quen nào',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[700]),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Nhấn nút “Thêm thói quen” để bắt đầu',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: provider.habits.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final habit = provider.habits[index];
                        final isDone = provider.isCompleted(habit.id, today);
                        final isInSchedule = provider.matchesHabitDate(habit, today);

                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              habit.name,
                                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          if (!habit.isActive)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.red[50],
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                'Vô hiệu hóa',
                                                style: TextStyle(fontSize: 11, color: Colors.red[700]),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      if (habit.description.isNotEmpty)
                                        Text(
                                          habit.description,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                                        ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          Chip(
                                            avatar: const Icon(Icons.repeat, size: 16),
                                            label: Text(habit.frequencyLabel),
                                          ),
                                          if (habit.reminderEnabled)
                                            Chip(
                                              avatar: const Icon(Icons.access_time, size: 16),
                                              label: Text(habit.reminderTime.format(context)),
                                            ),
                                          if (isInSchedule)
                                            Chip(
                                              avatar: const Icon(Icons.calendar_today, size: 16),
                                              label: Text(habit.selectedDayLabel),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  children: [
                                    IconButton(
                                      onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => HabitEditorScreen(habit: habit)),
                                      ),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      onPressed: () => _confirmDelete(context, provider, habit),
                                      icon: const Icon(Icons.delete_outline),
                                      color: Colors.red,
                                    ),
                                  ],
                                ),
                                SizedBox(
                                  width: 72,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isDone ? Theme.of(context).colorScheme.primary : Colors.grey[200],
                                      foregroundColor: isDone ? Colors.white : Colors.grey[800],
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    onPressed: habit.isActive && isInSchedule ? () => provider.toggleCompletion(habit.id, today) : null,
                                    child: Text(isDone ? 'Hoàn tất' : 'Làm'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, HabitProvider provider, Habit habit) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa thói quen'),
        content: Text('Bạn có chắc muốn xóa “${habit.name}”?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              provider.deleteHabit(habit.id);
              Navigator.pop(dialogContext);
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }
}

class HabitEditorScreen extends StatefulWidget {
  const HabitEditorScreen({super.key, this.habit});

  final Habit? habit;

  @override
  State<HabitEditorScreen> createState() => _HabitEditorScreenState();
}

class _HabitEditorScreenState extends State<HabitEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late HabitFrequency _selectedFrequency;
  late final Set<int> _selectedDays;
  late TimeOfDay _reminderTime;
  late bool _reminderEnabled;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final habit = widget.habit;
    _nameController = TextEditingController(text: habit?.name ?? '');
    _descriptionController = TextEditingController(text: habit?.description ?? '');
    _selectedFrequency = habit?.frequency ?? HabitFrequency.daily;
    _selectedDays = habit == null ? {DateTime.now().weekday} : Set<int>.from(habit.selectedDays);
    _reminderTime = habit?.reminderTime ?? const TimeOfDay(hour: 9, minute: 0);
    _reminderEnabled = habit?.reminderEnabled ?? false;
    _isActive = habit?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.habit == null ? 'Thêm thói quen' : 'Sửa thói quen'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Tên thói quen *'),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Vui lòng nhập tên thói quen.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Mô tả'),
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('Tần suất'),
              const SizedBox(height: 8),
              SegmentedButton<HabitFrequency>(
                segments: const [
                  ButtonSegment(value: HabitFrequency.daily, label: Text('Hàng ngày')),
                  ButtonSegment(value: HabitFrequency.weekly, label: Text('Các ngày')),
                  ButtonSegment(value: HabitFrequency.custom, label: Text('Tùy chọn')),
                ],
                selected: {_selectedFrequency},
                onSelectionChanged: (value) => setState(() {
                  _selectedFrequency = value.first;
                  if (_selectedFrequency == HabitFrequency.daily) {
                    _selectedDays.clear();
                  } else if (_selectedDays.isEmpty) {
                    _selectedDays.add(DateTime.now().weekday);
                  }
                }),
              ),
              const SizedBox(height: 16),
              if (_selectedFrequency != HabitFrequency.daily) ...[
                _buildSectionTitle('Ngày thực hiện'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(7, (index) {
                    final weekday = index + 1;
                    final selected = _selectedDays.contains(weekday);
                    return FilterChip(
                      label: Text(['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][index]),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        if (selected) {
                          _selectedDays.remove(weekday);
                        } else {
                          _selectedDays.add(weekday);
                        }
                      }),
                    );
                  }),
                ),
              ],
              if (_selectedFrequency != HabitFrequency.daily && _selectedDays.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Vui lòng chọn ít nhất một ngày trong tuần.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 16),
              _buildSectionTitle('Nhắc nhở'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Bật nhắc nhở'),
                  Switch(
                    value: _reminderEnabled,
                    onChanged: (value) => setState(() => _reminderEnabled = value),
                  ),
                ],
              ),
              if (_reminderEnabled)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Giờ nhắc'),
                  trailing: TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _reminderTime,
                      );
                      if (picked != null) {
                        setState(() => _reminderTime = picked);
                      }
                    },
                    child: Text(_reminderTime.format(context)),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Kích hoạt thói quen'),
                  Switch(
                    value: _isActive,
                    onChanged: (value) => setState(() => _isActive = value),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saveHabit,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Lưu thói quen'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  void _saveHabit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }
    if (_selectedFrequency != HabitFrequency.daily && _selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ít nhất một ngày thực hiện.')),
      );
      return;
    }

    final provider = context.read<HabitProvider>();
    final habit = Habit(
      id: widget.habit?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      frequency: _selectedFrequency,
      selectedDays: _selectedFrequency == HabitFrequency.daily ? const [] : _selectedDays.toList()..sort(),
      reminderTime: _reminderTime,
      reminderEnabled: _reminderEnabled,
      createdAt: widget.habit?.createdAt ?? DateTime.now(),
      isActive: _isActive,
    );

    if (widget.habit == null) {
      await provider.addHabit(habit);
    } else {
      await provider.updateHabit(habit);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.habit == null ? 'Đã lưu thói quen mới.' : 'Đã cập nhật thói quen.'),
      ),
    );
  }
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HabitProvider>();
    final today = DateTime.now();
    final todaySummary = provider.summaryForDate(today);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Thống kê',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Ngày'),
                Tab(text: 'Tuần'),
                Tab(text: 'Tháng'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _DayStatView(summary: todaySummary),
                  _WeekStatView(provider: provider),
                  _MonthStatView(provider: provider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayStatView extends StatelessWidget {
  const _DayStatView({required this.summary});

  final HabitSummary summary;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetricTile(title: 'Dự kiến', value: summary.expected.toString(), color: Colors.blue),
      _MetricTile(title: 'Hoàn thành', value: summary.completed.toString(), color: Colors.green),
      _MetricTile(title: 'Chưa hoàn thành', value: summary.remaining.toString(), color: Colors.orange),
      _MetricTile(title: 'Tỷ lệ', value: '${summary.percent.toStringAsFixed(0)}%', color: Colors.purple),
    ];

    return ListView(
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          physics: const NeverScrollableScrollPhysics(),
          children: items,
        ),
      ],
    );
  }
}

class _WeekStatView extends StatelessWidget {
  const _WeekStatView({required this.provider});

  final HabitProvider provider;

  @override
  Widget build(BuildContext context) {
    final dates = List<DateTime>.generate(7, (index) => DateTime.now().subtract(Duration(days: 6 - index)));
    final summaries = dates.map((date) => provider.summaryForDate(date)).toList();
    final totalExpected = summaries.fold<int>(0, (sum, item) => sum + item.expected);
    final totalCompleted = summaries.fold<int>(0, (sum, item) => sum + item.completed);
    final rate = totalExpected == 0 ? 0.0 : (totalCompleted / totalExpected) * 100;

    return ListView(
      children: [
        _MetricTile(title: 'Tổng lượt dự kiến', value: totalExpected.toString(), color: Colors.blue),
        const SizedBox(height: 12),
        _MetricTile(title: 'Tổng hoàn thành', value: totalCompleted.toString(), color: Colors.green),
        const SizedBox(height: 12),
        _MetricTile(title: 'Tỷ lệ tuần', value: '${rate.toStringAsFixed(0)}%', color: Colors.purple),
        const SizedBox(height: 18),
        SizedBox(
          height: 260,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: 100,
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= dates.length) {
                        return const SizedBox();
                      }
                      final label = DateFormat('EEE', 'vi').format(dates[index]).replaceFirst('Th', 'T');
                      return Text(label, style: const TextStyle(fontSize: 10));
                    },
                    reservedSize: 28,
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(dates.length, (index) {
                final percent = summaries[index].expected == 0 ? 0.0 : summaries[index].percent;
                return BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: percent,
                      color: Theme.of(context).colorScheme.primary,
                      width: 18,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class _MonthStatView extends StatelessWidget {
  const _MonthStatView({required this.provider});

  final HabitProvider provider;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final totalDays = DateTime(now.year, now.month + 1, 0).day;
    final dates = List<DateTime>.generate(totalDays, (index) => DateTime(now.year, now.month, index + 1));
    final summaries = dates.map((date) => provider.summaryForDate(date)).toList();
    final totalExpected = summaries.fold<int>(0, (sum, item) => sum + item.expected);
    final totalCompleted = summaries.fold<int>(0, (sum, item) => sum + item.completed);
    final rate = totalExpected == 0 ? 0.0 : (totalCompleted / totalExpected) * 100;

    return ListView(
      children: [
        _MetricTile(title: 'Dự kiến tháng', value: totalExpected.toString(), color: Colors.blue),
        const SizedBox(height: 12),
        _MetricTile(title: 'Hoàn thành tháng', value: totalCompleted.toString(), color: Colors.green),
        const SizedBox(height: 12),
        _MetricTile(title: 'Tỷ lệ tháng', value: '${rate.toStringAsFixed(0)}%', color: Colors.purple),
        const SizedBox(height: 18),
        SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  color: Theme.of(context).colorScheme.primary,
                  barWidth: 3,
                  belowBarData: BarAreaData(show: true, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)),
                  spots: List.generate(summaries.length, (index) {
                    final value = summaries[index].expected == 0 ? 0.0 : summaries[index].percent;
                    return FlSpot(index.toDouble(), value);
                  }),
                ),
              ],
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 5,
                    reservedSize: 20,
                    getTitlesWidget: (value, meta) => Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.title, required this.value, required this.color});

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HabitProvider>();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Cài đặt',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Thông tin ứng dụng'),
              subtitle: const Text('Discipline – Personal Habit Tracker'),
              trailing: const Text('1.0.0'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('Nhắc nhở khi ứng dụng đang mở'),
              subtitle: const Text('Đây là giải pháp lưu trữ trên web; thông báo nền không được triển khai.'),
              value: provider.webReminderPermission,
              onChanged: (value) => provider.setReminderPermission(value),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber[800]),
                    const SizedBox(width: 8),
                    Text('Giới hạn kỹ thuật trên web', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Trình duyệt có thể không hỗ trợ thông báo nền như ứng dụng native. Ứng dụng vẫn hoạt động bình thường bằng cách lưu trạng thái và nhắc nhở trực tiếp khi đang mở.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
