import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../utils/aggregate.dart';
import '../utils/intensity.dart';
import '../utils/metrics.dart';

/// Secili donemin sutun grafigi. Hedef cizgisi yalnizca gun bazli
/// donemlerde anlamli oldugu icin disaridan kontrol edilir.
///
/// [heightCm] ve [weightKg] verilirse her sutunun ustunde ikonlu adim, km,
/// kcal (ve [waterOf] verilirse su) yazilir. Sutun genisligi bu degerlerin
/// okunacagi [_minValueSlot] degerinin altina duserse (Ay: 31, Yil: 12
/// sutun) grafik yatay kaydirilabilir olur ve son kayitli gune kayar.
class PeriodChart extends StatefulWidget {
  final List<SeriesPoint> series;
  final int goal;
  final bool showGoalLine;
  final String caption;
  final int? heightCm;
  final double? weightKg;
  final Color? barColor;

  /// Adim disi veriler (or. su) icin sutun ustunde tek satir deger.
  /// Verilirse adim/km/kcal yerine bu yazilir ve kaydirmali duzen acilir.
  final String Function(SeriesPoint p)? valueLabel;

  /// [valueLabel] icin aciklama (or. "litre").
  final String? valueLegend;

  /// Sutunun gercek aktif suresi (kcal icin); null donerse tahmin kullanilir.
  final int? Function(DateTime from, DateTime to)? activeMinutes;

  /// Verilirse km/kcal tempo kirilimindan (normal + tempolu + kosu) gelir;
  /// [activeMinutes]'tan onceliklidir.
  final ActivityBreakdown Function(DateTime from, DateTime to)? breakdown;

  /// Sutunun araligindaki su (ml). Verilirse deger satirlarina eklenir.
  final int Function(DateTime from, DateTime to)? waterOf;

  /// Sutunun araliginda hedefi tutan gun sayisi. Gun sutununda 1 ise 🏅,
  /// ay sutununda "🏅n" gosterilir. Cagiran taraf guncel hedefe gore
  /// hesaplar; hedef degisince grafik aninda guncellenir.
  final int Function(DateTime from, DateTime to)? goalDaysOf;

  /// Verilirse sutuna dokununca grafigin icinde (sutun ustunde) bu metin
  /// [tipIcon] ile gosterilir; tekrar dokunmak kapatir.
  final String Function(SeriesPoint p)? tipLabel;
  final IconData? tipIcon;

  /// Sutuna dokunulunca (or. tempo kirilimi karti).
  final ValueChanged<SeriesPoint>? onBarTap;

  /// Grafik gecmise dogru kaydirilinca (parmak saga) bir onceki doneme,
  /// ileriye dogru kaydirilinca sonraki doneme gecilir. Kaydirmali grafikte
  /// kenara gelip biraz daha cekmek, sabit grafikte yatay kaydirmak yeterli.
  final VoidCallback? onSwipePrev;
  final VoidCallback? onSwipeNext;

  const PeriodChart({
    super.key,
    required this.series,
    required this.goal,
    required this.showGoalLine,
    required this.caption,
    this.heightCm,
    this.weightKg,
    this.barColor,
    this.valueLabel,
    this.valueLegend,
    this.activeMinutes,
    this.breakdown,
    this.waterOf,
    this.goalDaysOf,
    this.tipLabel,
    this.tipIcon,
    this.onBarTap,
    this.onSwipePrev,
    this.onSwipeNext,
  });

  @override
  State<PeriodChart> createState() => _PeriodChartState();
}

class _PeriodChartState extends State<PeriodChart> {
  static const _minValueSlot = 52.0;
  static const _chartHeight = 130.0;
  static const _lineHeight = 15.5;
  static const _tipHeight = 24.0;

  final _scroll = ScrollController();
  int? _selected;

  /// Kenardan donem degisince yeni grafik hangi uctan gorunsun:
  /// -1 = sondan (onceki doneme gecildi), 1 = bastan (sonrakine gecildi).
  int _pendingEdge = 0;

  /// Tek surukleme hareketinde yalnizca bir donem atlansin.
  bool _swiped = false;
  double _dragDx = 0;

  /// Kenara gelip bu kadar (px) daha cekince donem degisir.
  static const _edgePull = 36.0;

  /// Kenarda biriken cekme miktari (negatif: basta, pozitif: sonda).
  double _overscroll = 0;
  static const _swipeDistance = 50.0;
  static const _swipeVelocity = 300.0;

  bool get _single => widget.valueLabel != null;
  bool get _multi =>
      !_single && widget.heightCm != null && widget.weightKg != null;
  bool get _showValues => _single || _multi;
  bool get _hasTip => widget.tipLabel != null;

  int get _lines => _single ? 1 : (widget.waterOf != null ? 4 : 3);

  @override
  void initState() {
    super.initState();
    _scheduleJump();
  }

  @override
  void didUpdateWidget(covariant PeriodChart old) {
    super.didUpdateWidget(old);
    final a = old.series.isEmpty ? null : old.series.first.start;
    final b = widget.series.isEmpty ? null : widget.series.first.start;
    if (old.series.length != widget.series.length || a != b) {
      _selected = null;
      _scheduleJump();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Kaydirilabilir grafikte son veri olan (veya vurgulu) sutun gorunsun.
  void _scheduleJump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final edge = _pendingEdge;
      _pendingEdge = 0;
      if (!mounted || !_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.maxScrollExtent <= 0) return;
      if (edge != 0) {
        _scroll.jumpTo(edge < 0 ? pos.maxScrollExtent : 0);
        return;
      }
      final s = widget.series;
      var target = s.lastIndexWhere((p) => p.highlight);
      if (target < 0) target = s.lastIndexWhere((p) => p.value > 0);
      if (target < 0) {
        _scroll.jumpTo(0);
        return;
      }
      final slot = (pos.maxScrollExtent + pos.viewportDimension) / s.length;
      final offset = (target + 1) * slot - pos.viewportDimension + slot;
      _scroll.jumpTo(offset.clamp(0.0, pos.maxScrollExtent));
    });
  }

  bool get _canSwipe => widget.onSwipePrev != null || widget.onSwipeNext != null;

  void _swipe(bool prev) {
    final cb = prev ? widget.onSwipePrev : widget.onSwipeNext;
    if (cb == null) return;
    _swiped = true;
    _pendingEdge = prev ? -1 : 1;
    HapticFeedback.selectionClick();
    cb();
  }

  /// Kaydirmali grafik: kenardan tasirilinca donem degisir.
  ///
  /// Clamping fizigi kenarda kaymayi durdurur ve fazlasini
  /// OverscrollNotification olarak bildirir; parmakla cekilen miktar
  /// surtunmesiz birikir. Eski yontem (Bouncing + piksel esigi) esnemenin
  /// surtunmesi yuzunden cogu zaman esige ulasmiyordu.
  bool _onScroll(ScrollNotification n) {
    if (!_canSwipe) return false;
    if (n is ScrollStartNotification) {
      _swiped = false;
      _overscroll = 0;
    } else if (n is OverscrollNotification) {
      if (n.dragDetails != null && !_swiped) {
        _overscroll += n.overscroll;
        if (_overscroll <= -_edgePull) {
          _swipe(true);
        } else if (_overscroll >= _edgePull) {
          _swipe(false);
        }
      }
    } else if (n is ScrollUpdateNotification) {
      // Kenardan geri donuldu: birikim sifirlanir.
      if ((n.scrollDelta ?? 0) != 0) _overscroll = 0;
    } else if (n is ScrollEndNotification) {
      _overscroll = 0;
    }
    return false;
  }

  /// Sabit (kaymayan) grafik: yatay surukleme donem degistirir.
  Widget _swipeable(Widget child) {
    if (!_canSwipe) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _dragDx = 0,
      onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (_dragDx > _swipeDistance || v > _swipeVelocity) {
          _swipe(true);
        } else if (_dragDx < -_swipeDistance || v < -_swipeVelocity) {
          _swipe(false);
        }
        _dragDx = 0;
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final goal = widget.goal;
    final showGoalLine = widget.showGoalLine;

    final peak = series.fold<int>(
      showGoalLine ? goal : 1,
      (m, e) => e.value > m ? e.value : m,
    );
    // Hedef cizgisi icin %10 pay: hicbir gun hedefi asmadiginda
    // maxVal == goal olup cizgi grafigin tam ust kenarina denk geliyor ve
    // gorunmuyordu.
    final headroom = (goal * 1.1).round();
    final maxVal =
        showGoalLine && goal > 0 && peak < headroom ? headroom : peak;
    final best = series.fold<int>(0, (m, e) => e.value > m ? e.value : m);
    final bestText = best <= 0
        ? ''
        : _single
            ? widget.valueLabel!(series.firstWhere((p) => p.value == best))
            : Metrics.thousands(best);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.caption,
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (best > 0)
                Text(
                  'en yüksek $bestText',
                  style: TextStyle(
                    color: AppColors.best,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Stack(
            children: [
          LayoutBuilder(
            builder: (_, c) {
              final n = series.isEmpty ? 1 : series.length;
              // Kayan nokta toplami genisligi asip tasma uyarisi vermesin.
              final fit = (c.maxWidth / n * 100).floorToDouble() / 100;
              // 7 sutunlu gorunumler dar ekranda da kaydirmasiz kalsin;
              // degerler FittedBox ile kuculur.
              final minSlot = n <= 7 ? 32.0 : _minValueSlot;
              final slot = _showValues && fit < minSlot ? minSlot : fit;
              final width = slot * n;
              final body = SizedBox(
                width: width,
                child: _body(series, maxVal, best, slot),
              );
              if (width <= c.maxWidth + 0.5) return _swipeable(body);
              return NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  // Kenardan cekilebilsin (donem gecisi) diye her zaman esnek.
                  physics: const ClampingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  child: body,
                ),
              );
            },
          ),
              // Bos donem: grafik yerine aciklama (bozuk sanilmasin).
              if (series.every((p) => p.value <= 0))
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.hourglass_empty,
                                size: 15, color: AppColors.textDim),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Bu dönemde kayıt yok',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textDim,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Alt bilgi tek satirda: sigmazsa satira kaymak yerine kuculur.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _spaced([
              if (showGoalLine && goal > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 14, child: _DashedLine()),
                    const SizedBox(width: 6),
                    Text(
                      'hedef ${Metrics.thousands(goal)}',
                      style: TextStyle(
                        color: AppColors.textDim,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              if (widget.goalDaysOf != null)
                Text(
                  '🏅 hedef tuttu',
                  style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                ),
              if (_single && widget.valueLegend != null)
                _Legend(
                  icon: widget.tipIcon ?? Icons.circle,
                  color: widget.barColor ?? AppColors.accent,
                  text: widget.valueLegend!,
                )
              else if (_multi) ...[
                _Legend(
                    icon: Icons.directions_walk,
                    color: MetricColors.steps,
                    text: 'adım'),
                _Legend(
                    icon: Icons.straighten,
                    color: MetricColors.km,
                    text: 'km'),
                _Legend(
                    icon: Icons.local_fire_department_outlined,
                    color: MetricColors.kcal,
                    text: 'kcal'),
                if (widget.waterOf != null)
                  _Legend(
                      icon: Icons.water_drop_outlined,
                      color: MetricColors.water,
                      text: 'su (L)'),
              ],
            ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Alt bilgi ogeleri arasina esit bosluk.
  static List<Widget> _spaced(List<Widget> items) => [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          items[i],
        ],
      ];

  Widget _body(List<SeriesPoint> series, int maxVal, int best, double slot) {
    final goal = widget.goal;
    final showGoalLine = widget.showGoalLine;
    final dense = slot < 16;
    // Kaydirmali grafikte her sutunun etiketi okunacak kadar yer var.
    final allLabels = slot >= 24;
    final sel =
        _selected != null && _selected! < series.length ? _selected : null;

    return Column(
      children: [
        if (_hasTip)
          SizedBox(
            height: _tipHeight,
            child: sel == null
                ? null
                : Align(
                    alignment: Alignment(
                      series.length == 1
                          ? 0
                          : -1 + 2 * sel / (series.length - 1),
                      0,
                    ),
                    child: _TipBubble(
                      icon: widget.tipIcon,
                      color: widget.barColor ?? AppColors.accent,
                      text: widget.tipLabel!(series[sel]),
                    ),
                  ),
          ),
        if (_showValues)
          SizedBox(
            height: _lines * _lineHeight + 2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(
                series.length,
                (i) => SizedBox(
                  width: slot,
                  child: _tap(series[i], _values(series[i]), i),
                ),
              ),
            ),
          ),
        if (_showValues) const SizedBox(height: 4),
        SizedBox(
          height: _chartHeight,
          child: Stack(
            children: [
              if (showGoalLine && goal > 0 && maxVal > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: (goal / maxVal) *
                      (_chartHeight - (widget.goalDaysOf != null ? 24.0 : 0.0)),
                  child: const _DashedLine(),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(series.length, (i) {
                  final p = series[i];
                  final ratio = maxVal == 0 ? 0.0 : p.value / maxVal;
                  final isBest = best > 0 && p.value == best;
                  final reached = showGoalLine && goal > 0 && p.value >= goal;
                  final isSel = sel == i;
                  final pad = dense ? 1.0 : (slot >= 40 ? 6.0 : 3.0);
                  final goalDays = (p.start != null && p.end != null)
                      ? widget.goalDaysOf?.call(p.start!, p.end!) ?? 0
                      : 0;
                  final dayBar = p.start != null && p.start == p.end;

                  return SizedBox(
                    width: slot,
                    child: _tap(
                      p,
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: pad),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: ratio),
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) {
                            // Rozet gosterilecekse ustte yer birakilir; rozet
                            // hicbir zaman barin icine dusmez.
                            final top = widget.goalDaysOf != null ? 24.0 : 0.0;
                            final h = ((_chartHeight - top) * v).clamp(
                                p.value == 0 ? 2.0 : 5.0, _chartHeight - top);
                            final base = widget.barColor ?? AppColors.accent;
                            final c = p.value == 0
                                ? AppColors.surfaceAlt
                                : isSel
                                    ? AppColors.text
                                    : isBest && widget.barColor == null
                                        ? AppColors.best
                                        : reached || p.highlight
                                            ? base
                                            : base.withValues(alpha: 0.5);
                            return Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.bottomCenter,
                              children: [
                                Container(
                                  height: h,
                                  decoration: BoxDecoration(
                                    gradient: p.value == 0
                                        ? null
                                        : LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: [
                                              c.withValues(alpha: 0.25),
                                              c,
                                            ],
                                          ),
                                    color: p.value == 0 ? c : null,
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(dense ? 2 : 5),
                                    ),
                                  ),
                                ),
                                // Hedefi tutan gun: barin USTUNDE koyu zeminli,
                                // yesil cerceveli rozet (turuncu barda da belli).
                                if (goalDays > 0)
                                  Positioned(
                                    bottom: h + 2,
                                    child: Container(
                                      width: 21,
                                      height: 21,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppColors.bg,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.accent,
                                          width: 1.3,
                                        ),
                                      ),
                                      child: Text(
                                        dayBar ? '🏅' : '$goalDays',
                                        style: TextStyle(
                                          fontSize: 11,
                                          height: 1,
                                          color: AppColors.accent,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      i,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 16,
          child: Row(
            children: List.generate(series.length, (i) {
              final p = series[i];
              return SizedBox(
                width: slot,
                child: p.showLabel || allLabels || _isNow(p)
                    ? Center(child: _label(p, sel == i))
                    : const SizedBox.shrink(),
              );
            }),
          ),
        ),
      ],
    );
  }

  /// Sutun bugunu (gun sutunu) ya da icinde bulunulan ayi (yil grafiginde
  /// ay sutunu) mi kapsiyor.
  static bool _isNow(SeriesPoint p) {
    final s = p.start;
    if (s == null) return false;
    final e = p.end ?? s;
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return !today.isBefore(DateTime(s.year, s.month, s.day)) &&
        !today.isAfter(DateTime(e.year, e.month, e.day));
  }

  /// Alt etiket. Bugun (ya da bu ay) dolgulu kucuk bir hapla isaretlenir;
  /// grafige ilk bakista "bugun hangisi" anlasilir. Secili / vurgulu
  /// sutunun yazi rengi kurali aynen korunur.
  Widget _label(SeriesPoint p, bool selected) {
    final accent = widget.barColor ?? AppColors.accent;
    final now = _isNow(p);
    final text = Text(
      p.label,
      maxLines: 1,
      overflow: TextOverflow.visible,
      softWrap: false,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: now
            ? (AppColors.isLight ? Colors.white : AppColors.bg)
            : selected
                ? AppColors.text
                : p.highlight
                    ? accent
                    : AppColors.textDim,
        fontSize: 11,
        fontWeight: now || selected
            ? FontWeight.w800
            : p.highlight
                ? FontWeight.w700
                : FontWeight.normal,
        height: 1.2,
      ),
    );
    if (!now) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: text,
    );
  }

  /// Sutun ustundeki satirlar: ikonlu adim / km / kcal (/ su).
  Widget _values(SeriesPoint p) {
    if (p.value <= 0) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Text(
          '–',
          style: TextStyle(color: AppColors.textDim, fontSize: 11),
        ),
      );
    }
    final label = widget.valueLabel;
    if (label != null) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: _line(label(p), widget.barColor ?? AppColors.text,
                FontWeight.w700),
          ),
        ),
      );
    }
    final h = widget.heightCm!;
    final w = widget.weightKg!;
    final hasRange = p.start != null && p.end != null;
    final bd = hasRange ? widget.breakdown?.call(p.start!, p.end!) : null;
    final double km;
    final int kcal;
    if (bd != null) {
      km = bd.km;
      kcal = bd.kcal.round();
    } else {
      final minutes =
          hasRange ? widget.activeMinutes?.call(p.start!, p.end!) : null;
      km = Metrics.distanceKm(p.value, h);
      kcal = Metrics.kcal(p.value, h, w, activeMin: minutes).round();
    }
    final water = hasRange ? widget.waterOf?.call(p.start!, p.end!) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _iconLine(Icons.directions_walk, MetricColors.steps,
                Metrics.compact(p.value), AppColors.text),
            _iconLine(Icons.straighten, MetricColors.km, _km(km),
                MetricColors.km),
            _iconLine(Icons.local_fire_department_outlined,
                MetricColors.kcal, Metrics.compact(kcal), MetricColors.kcal),
            if (widget.waterOf != null)
              _iconLine(
                Icons.water_drop_outlined,
                MetricColors.water,
                (water ?? 0) <= 0
                    ? '–'
                    : (water! / 1000).toStringAsFixed(1).replaceAll('.', ','),
                MetricColors.water,
              ),
          ],
        ),
      ),
    );
  }

  static Widget _iconLine(
          IconData icon, Color iconColor, String text, Color textColor) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: iconColor),
          const SizedBox(width: 1.5),
          _line(text, textColor, FontWeight.w700),
        ],
      );

  /// Sutunun tum yuksekligi dokunulabilir (kisa sutunlar da).
  Widget _tap(SeriesPoint p, Widget child, int index) {
    final cb = widget.onBarTap;
    if (cb == null && !_hasTip) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_hasTip) {
          setState(() => _selected = _selected == index ? null : index);
        }
        cb?.call(p);
      },
      child: child,
    );
  }

  static String _km(double v) {
    final digits = v >= 100 ? 0 : 1;
    return v.toStringAsFixed(digits).replaceAll('.', ',');
  }

  static Widget _line(String text, Color color, FontWeight weight) => Text(
        text,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: weight,
          height: 1.3,
        ),
      );
}

/// Grafigin icinde, dokunulan sutunun ustunde cikan bilgi kutusu.
class _TipBubble extends StatelessWidget {
  final IconData? icon;
  final Color color;
  final String text;

  const _TipBubble({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            maxLines: 1,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Legend({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
        ),
      ],
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final count = (c.maxWidth / 8).floor().clamp(1, 200);
        return Row(
          children: List.generate(
            count,
            (_) => Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                color: AppColors.textDim.withValues(alpha: 0.45),
              ),
            ),
          ),
        );
      },
    );
  }
}
