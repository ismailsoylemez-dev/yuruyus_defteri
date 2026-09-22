import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/step_provider.dart';
import '../theme/app_theme.dart';
import '../utils/metrics.dart';

/// Kilo takibi: kayit ekleme / silme, trend grafigi ve degisim ozeti.
/// En yeni kayit profil kilosu olur; kalori hesabi guncel kiloyla yapilir.
class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key});

  @override
  State<WeightScreen> createState() => _WeightScreenState();
}

enum _Span { month, quarter, year, all }

extension on _Span {
  String get label => switch (this) {
        _Span.month => '1 Ay',
        _Span.quarter => '3 Ay',
        _Span.year => '1 Yıl',
        _Span.all => 'Tümü',
      };

  int? get days => switch (this) {
        _Span.month => 30,
        _Span.quarter => 90,
        _Span.year => 365,
        _Span.all => null,
      };
}

class _WeightScreenState extends State<WeightScreen> {
  _Span _span = _Span.quarter;

  static String _kg(double v) =>
      v.toStringAsFixed(1).replaceAll('.', ',');

  Future<void> _add() async {
    final settings = context.read<SettingsProvider>();
    final step = context.read<StepProvider>();
    final res = await showDialog<(DateTime, double)>(
      context: context,
      builder: (_) => _AddWeightDialog(initialKg: settings.weightKg),
    );
    if (res == null || !mounted) return;
    await settings.addWeight(res.$1, res.$2);
    await step.cloud?.setWeight(Metrics.dayKey(res.$1), res.$2);
    // Kalori hesabi yeni kiloyla: bildirim ve widget tazelensin.
    await step.refreshAll(force: true);
  }

  Future<void> _remove(String key) async {
    final settings = context.read<SettingsProvider>();
    final step = context.read<StepProvider>();
    await settings.removeWeight(key);
    await step.cloud?.setWeight(key, null);
    await step.refreshAll(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final log = settings.weightLog;
    final keys = log.keys.toList()..sort();
    final all = [
      for (final k in keys)
        if (Metrics.tryParseKey(k) != null) MapEntry(Metrics.parseKey(k), log[k]!),
    ];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = _span.days == null
        ? null
        : Metrics.addDays(today, -_span.days!);
    final shown = from == null
        ? all
        : all.where((e) => !e.key.isBefore(from)).toList();

    double? changeSince(int days) {
      if (all.length < 2) return null;
      final last = all.last;
      final limit = Metrics.addDays(last.key, -days);
      final base = all.lastWhere(
        (e) => !e.key.isAfter(limit),
        orElse: () => all.first,
      );
      if (identical(base, last)) return null;
      return last.value - base.value;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Kilo takibi')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Kilo ekle'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _Summary(
            current: all.isEmpty ? settings.weightKg : all.last.value,
            lastDate: all.isEmpty ? null : all.last.key,
            week: changeSince(7),
            month: changeSince(30),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final s in _Span.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: Text(s.label),
                      selected: _span == s,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _span = s),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 210,
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.divider),
              boxShadow: AppColors.cardShadow,
            ),
            child: shown.length < 2
                ? Center(
                    child: Text(
                      shown.isEmpty
                          ? 'Bu aralıkta kayıt yok.\nSağ alttan kilo ekle.'
                          : 'Trend için en az 2 kayıt gerekli.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textDim, fontSize: 13),
                    ),
                  )
                : CustomPaint(
                    size: Size.infinite,
                    painter: _TrendPainter(
                      points: shown,
                      line: AppColors.accent,
                      grid: AppColors.divider,
                      label: AppColors.textDim,
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          if (all.isNotEmpty)
            Text(
              'Kayıtlar',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 8),
          for (var i = all.length - 1; i >= 0; i--)
            _EntryTile(
              date: all[i].key,
              kg: all[i].value,
              diff: i == 0 ? null : all[i].value - all[i - 1].value,
              onDelete: () => _remove(Metrics.dayKey(all[i].key)),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final double current;
  final DateTime? lastDate;
  final double? week;
  final double? month;

  const _Summary({
    required this.current,
    required this.lastDate,
    required this.week,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    Widget delta(String label, double? v) {
      final color = v == null || v.abs() < 0.05
          ? AppColors.textDim
          : v < 0
              ? AppColors.accent
              : AppColors.best;
      final text = v == null
          ? '–'
          : '${v > 0 ? '+' : ''}${v.toStringAsFixed(1).replaceAll('.', ',')} kg';
      return Expanded(
        child: Column(
          children: [
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_WeightScreenState._kg(current)} kg',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                Text(
                  lastDate == null
                      ? 'profildeki kilo'
                      : 'son kayıt ${Metrics.numericDate(lastDate!)}',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
          delta('7 gün', week),
          delta('30 gün', month),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final DateTime date;
  final double kg;
  final double? diff;
  final VoidCallback onDelete;

  const _EntryTile({
    required this.date,
    required this.kg,
    required this.diff,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final d = diff;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${Metrics.numericDate(date)} ${Metrics.longLabel(date)}',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
          ),
          if (d != null && d.abs() >= 0.05)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                '${d > 0 ? '+' : ''}${d.toStringAsFixed(1).replaceAll('.', ',')}',
                style: TextStyle(
                  color: d < 0 ? AppColors.accent : AppColors.best,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Text(
            '${_WeightScreenState._kg(kg)} kg',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            tooltip: 'Sil',
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 20, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}

class _AddWeightDialog extends StatefulWidget {
  final double initialKg;
  const _AddWeightDialog({required this.initialKg});

  @override
  State<_AddWeightDialog> createState() => _AddWeightDialogState();
}

class _AddWeightDialogState extends State<_AddWeightDialog> {
  late final _ctrl = TextEditingController(
    text: widget.initialKg.toStringAsFixed(1).replaceAll('.', ','),
  );
  DateTime _day = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final v = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    if (v == null || v < 30 || v > 250) {
      setState(() => _error = '30 - 250 kg arası bir değer gir');
      return;
    }
    Navigator.of(context).pop((_day, v));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Kilo ekle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Kilo (kg)',
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: DateTime(now.year - 5),
                lastDate: now,
                cancelText: 'Vazgeç',
                confirmText: 'Seç',
              );
              if (picked != null) setState(() => _day = picked);
            },
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: Text('${Metrics.numericDate(_day)} ${Metrics.longLabel(_day)}'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}

/// Basit trend cizgisi: noktalar zamana gore yerlesir, y ekseninde
/// en dusuk / en yuksek kilo, altta ilk ve son tarih.
class _TrendPainter extends CustomPainter {
  final List<MapEntry<DateTime, double>> points;
  final Color line;
  final Color grid;
  final Color label;

  _TrendPainter({
    required this.points,
    required this.line,
    required this.grid,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0;
    const bottom = 20.0;
    final w = size.width - left;
    final h = size.height - bottom;
    var lo = points.map((e) => e.value).reduce(math.min);
    var hi = points.map((e) => e.value).reduce(math.max);
    if (hi - lo < 1) {
      lo -= 0.5;
      hi += 0.5;
    }
    final t0 = points.first.key.millisecondsSinceEpoch.toDouble();
    final t1 = points.last.key.millisecondsSinceEpoch.toDouble();
    final span = math.max(1.0, t1 - t0);

    Offset at(MapEntry<DateTime, double> e) => Offset(
          left + (e.key.millisecondsSinceEpoch - t0) / span * w,
          (hi - e.value) / (hi - lo) * (h - 8) + 4,
        );

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final g in [0.0, 0.5, 1.0]) {
      final y = g * (h - 8) + 4;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
      _text(canvas, (hi - g * (hi - lo)).toStringAsFixed(1).replaceAll('.', ','),
          Offset(0, y - 7), 11);
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = at(points[i]);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final dot = Paint()..color = line;
    for (final e in points) {
      canvas.drawCircle(at(e), 3.2, dot);
    }

    _text(canvas, Metrics.numericDate(points.first.key), Offset(left, h + 4), 11);
    final lastText = Metrics.numericDate(points.last.key);
    _text(canvas, lastText, Offset(size.width - 62, h + 4), 11);
  }

  void _text(Canvas c, String s, Offset o, double size) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: label, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points || old.line != line;
}
