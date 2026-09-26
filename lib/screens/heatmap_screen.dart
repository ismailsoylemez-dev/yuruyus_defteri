import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/route_service.dart';
import '../theme/app_theme.dart';

/// Kisisel isi haritasi: bugune kadar yurunen tum yollar; cok gecilen
/// yollar kirmizi ve kalin, az gecilenler mavi ve ince.
class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  static const _levelColors = [
    Color(0xFF2563EB), // 1 gun
    Color(0xFF06B6D4), // 2-4
    Color(0xFFF59E0B), // 5-9
    Color(0xFFDC2626), // 10+
  ];
  static const _levelWidths = [3.0, 3.8, 4.8, 6.0];
  static const _levelLabels = ['1 kez', '2-4', '5-9', '10+'];

  /// Oturum boyunca hesaplanan sonuc: (yil, gizlilik) -> (zaman, veri).
  static final Map<String, (DateTime, HeatmapData)> _cache = {};

  /// Bilgi karti bu oturumda kapatildi mi.
  static bool _infoClosed = false;

  final _boundaryKey = GlobalKey();
  HeatmapData? _data;
  bool _loading = true;
  bool _privacy = true;
  bool _sharing = false;
  int _year = DateTime.now().year;
  int _mapGen = 0;

  bool get _future => _year > DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_future) {
      setState(() {
        _data = null;
        _loading = false;
      });
      return;
    }
    final key = '$_year|$_privacy';
    final c = _cache[key];
    // 5 dk icinde tekrar hesaplanmaz (yeni antrenman sonrasi tazelenir).
    if (c != null && DateTime.now().difference(c.$1).inMinutes < 5) {
      setState(() {
        _data = c.$2;
        _loading = false;
        _mapGen++;
      });
      return;
    }
    setState(() => _loading = true);
    final year = _year;
    final d = await RouteService.heatmap(privacyM: _privacy ? 200 : 0, year: year);
    if (!mounted || year != _year) return;
    if (d != null) _cache[key] = (DateTime.now(), d);
    setState(() {
      _data = d;
      _loading = false;
      _mapGen++; // harita yeni veriyle, ilk karede dogru kadrajla kurulur
    });
  }

  void _shiftYear(int delta) {
    setState(() => _year += delta);
    _load();
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final img = await boundary.toImage(pixelRatio: 3);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/ayak_izi_$_year.png');
      await f.writeAsBytes(bytes.buffer.asUint8List());
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(f.path)],
        text: '$_year yılında ${_data?.km.toStringAsFixed(0) ?? '-'} km yol yürüdüm! #YürüyüşDefteri',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paylaşım sırasında bir hata oluştu.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _showInfo() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _InfoBody(),
        ),
      ),
    );
  }

  /// Renkli ama sakin zemin: OSM renkleri hafif soluk, izler one cikar.
  Widget _tiles(BuildContext context, Widget tile, TileImage image) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.75, 0.20, 0.05, 0, 12,
        0.10, 0.85, 0.05, 0, 12,
        0.10, 0.20, 0.70, 0, 12,
        0, 0, 0, 1, 0,
      ]),
      child: tile,
    );
  }

  Widget _buildMap(HeatmapData? d) {
    final pts = d == null ? const <LatLng>[] : [for (final l in d.lines) ...l.$2];
    final fit = pts.length >= 2
        ? CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts),
            padding: const EdgeInsets.fromLTRB(40, 70, 40, 60),
            maxZoom: 16,
          )
        : null;
    return FlutterMap(
      // Yeni veri gelince harita yeniden kurulur: kadraj ilk karede verilir,
      // sonradan kamera tasinmaz (ilk acilista siyah kalma sorunu buydu).
      key: ValueKey('map$_mapGen'),
      options: MapOptions(
        initialCenter: d?.home ?? (pts.isNotEmpty ? pts.first : const LatLng(39.0, 35.0)),
        initialZoom: pts.isEmpty ? 6 : 14,
        initialCameraFit: fit,
        minZoom: 3,
        maxZoom: 18,
        backgroundColor: const Color(0xFFE8EEF3),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.ismail.adim_sayar',
          maxNativeZoom: 19,
          retinaMode: true,
          tileBuilder: _tiles,
        ),
        if (d != null)
          for (var lv = 0; lv < 4; lv++)
            PolylineLayer(
              polylines: [
                for (final l in d.lines)
                  if (l.$1 == lv)
                    Polyline(
                      points: l.$2,
                      strokeWidth: _levelWidths[lv],
                      color: _levelColors[lv].withValues(alpha: lv == 0 ? 0.8 : 0.95),
                      borderColor: Colors.white.withValues(alpha: 0.85),
                      borderStrokeWidth: 1.2,
                      strokeCap: StrokeCap.round,
                      strokeJoin: StrokeJoin.round,
                    ),
              ],
            ),
        const RichAttributionWidget(
          showFlutterMapAttribution: false,
          attributions: [TextSourceAttribution('OpenStreetMap katkıcıları')],
        ),
      ],
    );
  }

  Widget _overlayMessage(IconData icon, String title, String text) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.accent),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.4)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final now = DateTime.now().year;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayak İzi Haritam'),
        actions: [
          IconButton(
            tooltip: 'Bu ekran ne gösterir?',
            onPressed: _showInfo,
            icon: Icon(Icons.info_outline_rounded, color: AppColors.textDim),
          ),
          if (d != null && !d.isEmpty)
            _sharing
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    tooltip: 'Paylaş',
                    onPressed: _share,
                    icon: Icon(Icons.ios_share_rounded, color: AppColors.accent),
                  ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (!_infoClosed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      const Color(0xFFF59E0B).withValues(alpha: 0.16),
                      const Color(0xFF7C3AED).withValues(alpha: 0.12),
                    ]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.travel_explore_rounded, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Seçili yılda yürüdüğün tüm yollar tek haritada. Sık geçtiğin yollar '
                          'kırmızı ve kalın, bir kez geçtiklerin mavi ve ince çizilir.',
                          style: TextStyle(color: AppColors.text, fontSize: 12.5, height: 1.35),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _infoClosed = true),
                        icon: Icon(Icons.close_rounded, size: 18, color: AppColors.textDim),
                      ),
                    ],
                  ),
                ),
              ),
            // Yil secici
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _loading ? null : () => _shiftYear(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Text(
                      '$_year',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    // Gelecek yila bir adim gidilebilir (bilgi mesaji gosterilir).
                    onPressed: _loading || _year > now ? null : () => _shiftYear(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _Stat(
                      icon: Icons.explore_rounded,
                      color: MetricColors.km,
                      value: d == null ? '–' : '${d.km.toStringAsFixed(d.km < 100 ? 1 : 0).replaceAll('.', ',')} km',
                      label: 'keşfedilen yol',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      icon: Icons.calendar_month_rounded,
                      color: MetricColors.time,
                      value: d == null ? '–' : '${d.days}',
                      label: 'yürüyüş günü',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      icon: Icons.local_fire_department_rounded,
                      color: MetricColors.kcal,
                      value: d == null ? '–' : '${d.maxCount}×',
                      label: 'en sık yol',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: Stack(
                      children: [
                        if (!_loading) Positioned.fill(child: _buildMap(d)) else
                          Positioned.fill(child: Container(color: const Color(0xFFE8EEF3))),
                        Positioned(
                          top: 10,
                          left: 10,
                          right: 10,
                          child: Row(
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.travel_explore_rounded, size: 16, color: Color(0xFFF59E0B)),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          d == null
                                              ? 'Yürüyüş Defteri · $_year'
                                              : 'Yürüyüş Defteri · $_year · ${d.km.toStringAsFixed(0)} km',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var lv = 0; lv < 4; lv++) ...[
                                  if (lv > 0) const SizedBox(width: 8),
                                  Container(
                                    width: 14,
                                    height: _levelWidths[lv],
                                    decoration: BoxDecoration(
                                      color: _levelColors[lv],
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _levelLabels[lv],
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_loading)
                          const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('Rotalar işleniyor…', style: TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )
                        else if (_future)
                          _overlayMessage(
                            Icons.hourglass_top_rounded,
                            '$_year henüz gelmedi 🙂',
                            'Bu yıl için henüz veri yok. Yeni yılın ilk yürüyüşüyle haritan burada dolmaya başlayacak!',
                          )
                        else if (d == null || d.isEmpty)
                          _overlayMessage(
                            Icons.directions_walk_rounded,
                            '$_year için iz yok',
                            'Bu yılda kayıtlı rota bulunamadı. Antrenman yaptıkça yürüdüğün yollar burada birikir.',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ev çevresini gizle',
                          style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'En sık başladığın/bitirdiğin yerin 200 m çevresi çizilmez.',
                          style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _privacy,
                    onChanged: _loading
                        ? null
                        : (v) {
                            setState(() => _privacy = v);
                            _load();
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Bu ekran ne gosterir?" icerigi.
class _InfoBody extends StatelessWidget {
  const _InfoBody();

  @override
  Widget build(BuildContext context) {
    Widget item(IconData i, Color c, String t, String d) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(i, color: c, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(d, style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ayak İzi Haritam',
            style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        item(Icons.travel_explore_rounded, const Color(0xFFF59E0B), 'Tüm yolların tek haritada',
            'Seçtiğin yılda antrenmanlarda ve otomatik rotada kaydedilen bütün izler üst üste çizilir.'),
        item(Icons.palette_outlined, const Color(0xFFDC2626), 'Renk = kaç farklı gün',
            'Mavi 1 kez, turkuaz 2-4, turuncu 5-9, kırmızı 10+ farklı günde yürüdüğün yol.'),
        item(Icons.calendar_month_rounded, MetricColors.time, 'Yıl yıl gezin',
            'Oklarla önceki yıllara geç; her yılın haritası ve istatistikleri ayrı hesaplanır.'),
        item(Icons.cloud_done_outlined, MetricColors.km, 'Bulutta güvende',
            'Rotaların hesabına yedeklenir; yeni telefonda bu harita buluttan yeniden oluşur.'),
        item(Icons.shield_outlined, AppColors.accent, 'Gizlilik',
            '"Ev çevresini gizle" açıkken en sık başladığın yerin 200 m çevresi çizilmez; paylaşımda adresin görünmez.'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _Stat({required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppColors.isLight ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(color: AppColors.text, fontSize: 14.5, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textDim, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
