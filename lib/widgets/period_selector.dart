import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/aggregate.dart';

class PeriodSelector extends StatelessWidget {
  final Period selected;
  final ValueChanged<Period> onChanged;

  const PeriodSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: Period.values.map((p) {
        final active = p == selected;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? AppColors.accent : AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: active ? AppColors.accent : AppColors.divider,
                  ),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _icon(p),
                      size: 14,
                      color: active ? AppColors.onAccent : AppColors.textDim,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      p.label,
                      style: TextStyle(
                        color: active ? AppColors.onAccent : AppColors.textDim,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _icon(Period p) {
    switch (p) {
      case Period.day:
        return Icons.today;
      case Period.week:
        return Icons.date_range;
      case Period.month:
        return Icons.calendar_month;
      case Period.year:
        return Icons.event_note;
    }
  }
}

class RangeBar extends StatelessWidget {
  final String title;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  /// Verilirse basliga dokununca calisir (or. takvimden gun secimi);
  /// basligin yaninda takvim ikonu gorunur.
  final VoidCallback? onTitleTap;

  const RangeBar({
    super.key,
    required this.title,
    required this.onPrev,
    this.onNext,
    this.onTitleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          color: AppColors.text,
          splashRadius: 22,
        ),
        Expanded(
          child: onTitleTap == null
              ? Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTitleTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_month_outlined,
                            size: 17, color: AppColors.accent),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          color: onNext == null ? AppColors.divider : AppColors.text,
          splashRadius: 22,
        ),
      ],
    );
  }
}
