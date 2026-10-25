// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/custom_code/widgets/index.dart'; // Imports other custom widgets
import 'package:flutter/material.dart' hide RepeatMode;
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_auth/firebase_auth.dart' as fba;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// =============================================================================
// ScreenerApp v2 (tema oscuro) — screener S&P 500 + Nasdaq-100
// Lee Firestore screener/latest + screener/partN (screener_job.py v2).
// Pensado para web e iPad en horizontal.
// =============================================================================

// ----------------------------------------------------------------- paleta

const Color _cBg = Color(0xFF111316);
const Color _cPanel = Color(0xFF171A1E);
const Color _cSurface = Color(0xFF1D2126);
const Color _cBorder = Color(0xFF2D3238);
const Color _cDivider = Color(0xFF22262B);
const Color _cText = Color(0xFFE7E9EC);
const Color _cMuted = Color(0xFF8B9099);
const Color _kGreen = Color(0xFF3FC97E);
const Color _kGreenFill = Color(0xFF1B8A4C);
const Color _kRed = Color(0xFFE5534B);
const Color _kRedFill = Color(0xFFB33A34);
const Color _kStar = Color(0xFFF5C451);
const Color _kAmber = Color(0xFFE0A93B);

ThemeData _darkTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: _cBg,
    canvasColor: _cPanel,
    dividerColor: _cDivider,
    colorScheme: base.colorScheme.copyWith(
      primary: _kGreen,
      onPrimary: Colors.white,
      secondary: _kGreen,
      surface: _cPanel,
      onSurface: _cText,
      error: _kRed,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme)
        .apply(bodyColor: _cText, displayColor: _cText),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _cSurface,
      isDense: true,
      hintStyle: const TextStyle(color: _cMuted),
      labelStyle: const TextStyle(color: _cMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _cBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _cBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kGreen, width: 1.4),
      ),
    ),
  );
}

Widget _themed(Widget child) => Theme(data: _darkTheme(), child: child);

Future<void> _openTradingView(String ticker) async {
  String t;
  if (ticker.endsWith('.MC')) {
    t = 'BME:${ticker.substring(0, ticker.length - 3)}';
  } else if (ticker.endsWith('.DE')) {
    t = 'XETR:${ticker.substring(0, ticker.length - 3)}';
  } else if (ticker.endsWith('.PA') || ticker.endsWith('.AS')) {
    t = 'EURONEXT:${ticker.substring(0, ticker.length - 3)}';
  } else {
    t = ticker.replaceAll('-', '.');
  }
  final uri = Uri.parse('https://www.tradingview.com/chart/?symbol=$t');
  // App nativa (iPad): intenta abrir directamente la app de TradingView;
  // si iOS no la asocia a este enlace, cae al navegador.
  if (!kIsWeb) {
    try {
      final ok =
          await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
      if (ok) return;
    } catch (_) {}
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

// ----------------------------------------------------------------- logos

const String _kLogoBase = 'https://storage.googleapis.com/bolsascreener-logos/';

class _Logo extends StatelessWidget {
  const _Logo({required this.ticker, required this.size, this.fallback});
  final String ticker;
  final double size;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        child: Image.network(
          '$_kLogoBase$ticker.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (ctx, err, st) => SizedBox.expand(
            child: fallback ?? const ColoredBox(color: _cSurface),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- campos

enum _Kind { number, boolean, text, choice, date }

class _Field {
  const _Field(this.key, this.label, this.cat, this.kind,
      {this.dec = 2, this.signed = false, this.width = 80, this.hdr});
  final String key;
  final String label;
  final String cat;
  final _Kind kind;
  final int dec;
  final bool signed;
  final double width;
  final String? hdr;

  String get header => hdr ?? label;
}

const String _cId = 'Empresa';
const String _cPlan = 'Plan de entrada y puntuación';
const String _cEma = 'Medias (EMA)';
const String _cTec = 'Técnico';
const String _cRet = 'Rentabilidad';
const String _cRel = 'Fuerza relativa (puntos %)';
const String _cPat = 'Patrones de vela';
const String _cVal = 'Valoración';
const String _cRes = 'Resultados';
const String _cAna = 'Analistas';
const String _cCor = 'Cortos y dividendo';

const List<String> _kCatOrder = [
  _cId,
  _cPlan,
  _cEma,
  _cTec,
  _cRet,
  _cRel,
  _cPat,
  _cVal,
  _cRes,
  _cAna,
  _cCor
];

const Map<String, String> _kPeriods = {
  '1w': '1 semana',
  '1m': '1 mes',
  '3m': '3 meses',
  '6m': '6 meses',
  '1y': '1 año',
  'ytd': 'en el año',
};

const Map<String, String> _kRefs = {
  'sec': 'sector',
  'ind': 'industria',
  'idx': 'su índice',
  'spy': 'S&P 500',
  'qqq': 'Nasdaq-100',
  'dia': 'Dow Jones',
};

const Set<String> _kCrossKeys = {
  'xu20',
  'xd20',
  'xu50',
  'xd50',
  'xu200',
  'xd200',
  'gc',
  'dc'
};

const Set<String> _kSessionKeys = {
  'hb_2050',
  'hb_any',
  'hs_any',
  'hb20',
  'hb50',
  'hb100',
  'hb200',
  'hs20',
  'hs50',
  'hs100',
  'hs200'
};

List<_Field> _buildFields() {
  final f = <_Field>[];
  void n(String k, String l, String c,
          {int dec = 2, bool s = false, double w = 80, String? h}) =>
      f.add(
          _Field(k, l, c, _Kind.number, dec: dec, signed: s, width: w, hdr: h));
  void b(String k, String l, String c, {double w = 84, String? h}) =>
      f.add(_Field(k, l, c, _Kind.boolean, width: w, hdr: h));
  void ch(String k, String l, String c, {double w = 140, String? h}) =>
      f.add(_Field(k, l, c, _Kind.choice, width: w, hdr: h));
  void t(String k, String l, String c, {double w = 90}) =>
      f.add(_Field(k, l, c, _Kind.text, width: w));
  void d(String k, String l, String c, {double w = 96, String? h}) =>
      f.add(_Field(k, l, c, _Kind.date, width: w, hdr: h));

  t('ticker', 'Ticker', _cId, w: 148);
  t('name', 'Empresa', _cId, w: 140);
  ch('sector', 'Sector', _cId, w: 150);
  ch('ind_name', 'Industria', _cId, w: 150);
  b('in_spx', 'En S&P 500', _cId);
  b('in_ndx', 'En Nasdaq-100', _cId);
  b('in_dow', 'En Dow Jones', _cId);
  b('in_ibex', 'En IBEX 35', _cId);
  b('in_dax', 'En DAX 40', _cId);
  ch('market', 'Mercado', _cId, w: 86);
  n('price', 'Precio', _cId, w: 92);
  n('mcap_b', 'Capitalización (miles de M\$)', _cId,
      dec: 1, h: 'Cap. (miles M\$)');
  n('dvol_m', 'Volumen medio diario en millones (moneda local)', _cId,
      dec: 0, h: 'Vol. medio (M)');

  n('score', 'Puntuación (0-100)', _cPlan, dec: 0, w: 82, h: 'Puntuación');
  n('p_entry', 'Entrada (sobre máx./bajo mín. de la última sesión)', _cPlan,
      w: 96, h: 'Entrada');
  n('p_stop', 'Stop', _cPlan, w: 96);
  n('p_stop_pct', 'Distancia al stop %', _cPlan, w: 76, h: 'Stop %');
  n('p_stop_atr', 'Distancia al stop en ATR', _cPlan, w: 76, h: 'Stop en ATR');
  n('p_target', 'Objetivo (siguiente máximo/mínimo relevante)', _cPlan,
      w: 96, h: 'Objetivo');
  n('p_target_pct', 'Recorrido hasta el objetivo %', _cPlan,
      w: 84, h: 'Recorrido %');
  n('p_rr', 'Beneficio/riesgo real (hasta el objetivo)', _cPlan,
      w: 76, h: 'B/R real');
  n('p_shares', 'Acciones (con tu riesgo y tope)', _cPlan,
      dec: 0, w: 76, h: 'Acciones');
  n('p_amount', 'Importe de la posición', _cPlan, dec: 0, w: 96, h: 'Importe');
  n('p_risk', 'Riesgo real de la posición', _cPlan,
      dec: 0, w: 86, h: 'Riesgo real');
  n('p_risk_pct', 'Riesgo real en % de tu riesgo máximo', _cPlan,
      dec: 0, w: 80, h: 'Riesgo usado %');

  for (final p in [20, 50, 100, 200]) {
    n('d_ema$p', '% sobre EMA$p', _cEma, s: true, w: 72);
  }
  n('d_e50_200', 'EMA50 sobre EMA200 %', _cEma,
      s: true, h: 'EMA50 vs EMA200 %');
  for (final p in [20, 50, 100, 200]) {
    n('a_ema$p', 'ATRs sobre EMA$p', _cEma, s: true);
  }
  for (final p in [20, 50, 100, 200]) {
    n('s_ema$p', 'Pendiente EMA$p (cambio % en 5 sesiones)', _cEma,
        s: true, h: 'Pendiente EMA$p %');
  }
  ch('slope_all', 'Pendiente de las 4 EMAs', _cEma, w: 96, h: 'Pendiente EMAs');
  ch('trend', 'Tendencia (orden de EMAs)', _cEma, w: 84, h: 'Tendencia');

  n('rsi_d', 'RSI diario', _cTec, dec: 0, w: 60);
  n('adx', 'ADX (fuerza de la tendencia)', _cTec, dec: 0, w: 60, h: 'ADX');
  n('ema20_run', 'Cierres seguidos sobre (+) o bajo (−) la EMA20', _cTec,
      dec: 0, s: true, w: 76, h: 'Racha EMA20');
  n('chg_1d', 'Variación de la última sesión %', _cTec, s: true, h: 'Día %');
  n('day_high', 'Máximo de la última sesión', _cTec, w: 96, h: 'Máx. sesión');
  n('day_low', 'Mínimo de la última sesión', _cTec, w: 96, h: 'Mín. sesión');
  n('beta', 'Beta', _cTec, w: 60);
  n('rsi_w', 'RSI semanal', _cTec, dec: 0, w: 66);
  n('atr_pct', 'ATR % (volatilidad diaria)', _cTec, h: 'ATR %');
  n('vol_rel', 'Volumen relativo (vs media 20)', _cTec, h: 'Volumen relativo');
  n('gap', 'Gap de hoy %', _cTec, s: true);
  n('d_high52', '% bajo máximo 52 semanas', _cTec,
      s: true, h: '% vs máx. 52 sem.');
  n('d_low52', '% sobre mínimo 52 semanas', _cTec,
      s: true, h: '% vs mín. 52 sem.');
  n('high52', 'Máximo 52 semanas', _cTec, w: 96, h: 'Máx. 52 sem.');
  n('low52', 'Mínimo 52 semanas', _cTec, w: 96, h: 'Mín. 52 sem.');
  n('clean3m', 'Limpieza tendencia 3m (R² ±)', _cTec,
      s: true, h: 'Limpieza 3m');
  n('clean6m', 'Limpieza tendencia 6m (R² ±)', _cTec,
      s: true, h: 'Limpieza 6m');
  b('brk_long', 'Cierre > máximo de ayer y > EMA20', _cTec,
      h: 'Ruptura alcista');
  b('brk_short', 'Cierre < mínimo de ayer y < EMA20', _cTec,
      h: 'Ruptura bajista');
  for (final p in [20, 50, 200]) {
    n(
        'xu$p',
        'Cruce alcista: precio cruza por encima de EMA$p (sesiones desde el cruce)',
        _cTec,
        dec: 0,
        w: 96,
        h: 'Cruce alcista EMA$p');
    n(
        'xd$p',
        'Cruce bajista: precio cruza por debajo de EMA$p (sesiones desde el cruce)',
        _cTec,
        dec: 0,
        w: 96,
        h: 'Cruce bajista EMA$p');
  }
  n(
      'gc',
      'Cruce dorado: EMA50 cruza por encima de EMA200 (sesiones desde el cruce)',
      _cTec,
      dec: 0,
      w: 96,
      h: 'Cruce dorado 50/200');
  n(
      'dc',
      'Cruce de la muerte: EMA50 cruza por debajo de EMA200 (sesiones desde el cruce)',
      _cTec,
      dec: 0,
      w: 96,
      h: 'Cruce muerte 50/200');

  _kPeriods
      .forEach((k, l) => n('r_$k', 'Rentabilidad $l %', _cRet, s: true, w: 88));

  _kRefs.forEach((ref, rl) {
    _kPeriods.forEach(
        (k, l) => n('rs_${ref}_$k', 'vs $rl $l', _cRel, s: true, w: 82));
  });

  n('hb_2050', 'Martillo alcista en EMA20 o EMA50 (sesiones)', _cPat,
      dec: 0, h: 'Martillo alcista');
  n('hb_any', 'Martillo alcista en cualquier EMA (sesiones)', _cPat,
      dec: 0, h: 'Martillo alcista (cualquier EMA)');
  for (final p in [20, 50, 100, 200]) {
    n('hb$p', 'Martillo alcista EMA$p (sesiones)', _cPat,
        dec: 0, h: 'Martillo EMA$p');
  }
  n('hb_stop', 'Stop martillo (mínimo de la vela)', _cPat, h: 'Stop martillo');
  n('hb_stop_pct', 'Distancia al stop del martillo %', _cPat,
      h: 'Dist. stop %');
  n('hb_rr', 'Beneficio/riesgo martillo', _cPat, w: 76, h: 'Beneficio/ riesgo');
  n('hs_any', 'Martillo bajista en cualquier EMA (sesiones)', _cPat,
      dec: 0, h: 'Martillo bajista');
  for (final p in [20, 50, 100, 200]) {
    n('hs$p', 'Martillo bajista EMA$p (sesiones)', _cPat,
        dec: 0, h: 'Mart. bajista EMA$p');
  }
  n('hs_stop', 'Stop martillo bajista (máximo de la vela)', _cPat,
      h: 'Stop martillo bajista');
  n('hs_stop_pct', 'Distancia al stop bajista %', _cPat, h: 'Dist. stop %');
  n('hs_rr', 'Beneficio/riesgo martillo bajista', _cPat,
      w: 76, h: 'Beneficio/ riesgo');

  n('pe', 'PER', _cVal, dec: 1, w: 62);
  n('fpe', 'PER forward', _cVal, dec: 1, w: 70);
  n('pe_vs_sec', 'PER / PER sector (x)', _cVal, h: 'PER / sector');
  n('pe_vs_ind', 'PER / PER industria (x)', _cVal, h: 'PER / industria');
  n('fpe_vs_sec', 'PER fwd / PER fwd sector (x)', _cVal, h: 'PER fwd / sector');
  n('fpe_vs_ind', 'PER fwd / PER fwd industria (x)', _cVal,
      h: 'PER fwd / industria');

  n('eps_surp', 'Sorpresa EPS último trimestre %', _cRes,
      s: true, dec: 1, h: 'Sorpresa EPS %');
  n('eps_surp_4q', 'Sorpresa EPS media 4 trimestres %', _cRes,
      s: true, dec: 1, h: 'Sorpresa media 4T %');
  n('eps_beats_4q', 'Trimestres batidos (de 4)', _cRes,
      dec: 0, h: 'Batidos (de 4)');
  n('eps_beat_streak', 'Racha de trimestres batiendo', _cRes,
      dec: 0, h: 'Racha batiendo');
  n('eps_miss_streak', 'Racha de trimestres fallando', _cRes,
      dec: 0, h: 'Racha fallando');
  d('eps_last_date', 'Últimos resultados', _cRes);
  n('earn_react', 'Reacción a los últimos resultados %', _cRes,
      s: true, dec: 1, h: 'Reacción resultados %');
  d('next_earn', 'Próximos resultados', _cRes);
  n('days_to_earn', 'Días hasta resultados', _cRes, dec: 0, w: 84);
  n('earn_bd', 'Días hábiles hasta resultados', _cRes,
      dec: 0, w: 84, h: 'Días hábiles a resultados');
  b('earn_est', 'Fecha de resultados estimada', _cRes, h: 'Fecha estimada');
  n('rev7', 'Revisión EPS año, 7 días %', _cRes,
      s: true, dec: 1, h: 'Rev. EPS 7d %');
  n('rev30', 'Revisión EPS año, 30 días %', _cRes,
      s: true, dec: 1, h: 'Rev. EPS 30d %');
  n('rev90', 'Revisión EPS año, 90 días %', _cRes,
      s: true, dec: 1, h: 'Rev. EPS 90d %');
  n('rev_q30', 'Revisión EPS trimestre, 30 días %', _cRes,
      s: true, dec: 1, h: 'Rev. EPS trim. 30d %');
  n('rev_up30', 'Analistas que suben EPS (30 días)', _cRes,
      dec: 0, h: 'Suben EPS 30d');
  n('rev_dn30', 'Analistas que bajan EPS (30 días)', _cRes,
      dec: 0, h: 'Bajan EPS 30d');
  n('rev_growth', 'Crecimiento ventas interanual %', _cRes,
      s: true, dec: 1, h: 'Crec. ventas %');
  n('eps_growth', 'Crecimiento beneficio interanual %', _cRes,
      s: true, dec: 1, h: 'Crec. beneficio %');

  n('target_up', 'Potencial a precio objetivo %', _cAna,
      s: true, dec: 1, h: 'Potencial objetivo %');
  n('rec_mean', 'Recomendación media (1 compra · 5 venta)', _cAna,
      h: 'Recomendación');
  n('n_analysts', 'Número de analistas', _cAna, dec: 0, h: 'Analistas');

  n('div_yield', 'Rentabilidad por dividendo %', _cCor, h: 'Dividendo %');
  d('ex_div', 'Próxima fecha ex-dividendo', _cCor, h: 'Ex-dividendo');
  n('days_to_exdiv', 'Días hasta ex-dividendo', _cCor,
      dec: 0, h: 'Días a ex-div.');
  n('short_float', 'Short interest % del free float (solo EE. UU.)', _cCor,
      dec: 1, h: 'Short % float');
  n('short_ratio', 'Días para cubrir (solo EE. UU.)', _cCor,
      dec: 1, h: 'Días para cubrir');
  n('short_pub', 'Cortos publicados CNMV, % del capital (solo España)', _cCor,
      dec: 2, h: 'Cortos CNMV %');
  n('short_n', 'Fondos con cortos publicados CNMV (solo España)', _cCor,
      dec: 0, h: 'Fondos cortos CNMV');
  return f;
}

final List<_Field> _kFields = _buildFields();
final Map<String, _Field> _kFieldMap = {for (final f in _kFields) f.key: f};

const Map<String, List<String>> _kDefaultCols = {
  'long': [
    'ticker',
    'name',
    'market',
    'score',
    'price',
    'p_entry',
    'p_stop_pct',
    'p_stop_atr',
    'p_target_pct',
    'p_rr',
    'p_shares',
    'p_risk',
    'a_ema20',
    'rs_sec_3m',
    'rs_idx_1m',
    'vol_rel',
    'dvol_m',
    'adx',
    'earn_bd'
  ],
  'short': [
    'ticker',
    'name',
    'market',
    'score',
    'price',
    'p_entry',
    'p_stop_pct',
    'p_stop_atr',
    'p_target_pct',
    'p_rr',
    'p_shares',
    'p_risk',
    'a_ema20',
    'rs_sec_3m',
    'rs_idx_1m',
    'vol_rel',
    'dvol_m',
    'adx',
    'earn_bd',
    'div_yield',
    'days_to_exdiv',
    'short_float',
    'short_pub'
  ],
};

const Map<String, String> _kHelp = {
  'hb_2050':
      'Sesiones desde la vela (0 = hoy). Máximo 3 = en las últimas 4 velas.',
  'hb_any':
      'Sesiones desde la vela (0 = hoy). Máximo 3 = en las últimas 4 velas.',
  'hs_any':
      'Sesiones desde la vela (0 = hoy). Máximo 3 = en las últimas 4 velas.',
  'days_to_earn':
      'Ej.: mínimo 0 y máximo 14 = resultados en las próximas 2 semanas.',
  'days_to_exdiv':
      'Ej.: máximo 30 = ex-dividendo en el próximo mes (en corto pagas el dividendo).',
  'clean3m':
      'De -1 a 1. +1 = subida perfectamente lineal, -1 = caída perfectamente lineal.',
  'clean6m':
      'De -1 a 1. +1 = subida perfectamente lineal, -1 = caída perfectamente lineal.',
  'pe_vs_ind':
      '1 = igual que su industria. 0,8 = un 20 % más barata. 1,5 = un 50 % más cara.',
  'pe_vs_sec':
      '1 = igual que su sector. 0,8 = un 20 % más barata. 1,5 = un 50 % más cara.',
  'vol_rel': '1 = volumen normal. 1,5 = un 50 % más de lo habitual.',
  'rec_mean': '1 = compra fuerte, 3 = mantener, 5 = venta.',
  'eps_beats_4q': '4 = ha batido los cuatro últimos trimestres.',
  'p_stop_atr':
      'Distancia del stop en ATRs. Menos de 1 = el stop puede saltar por ruido; 1,5 o más es holgado.',
  'p_rr':
      'Recorrido hasta el siguiente máximo relevante (mínimo en cortos) dividido por la distancia al stop. '
          'Sin objetivo (valor en máximos) queda vacío.',
  'p_risk_pct':
      'Riesgo real de la posición en % de tu riesgo máximo. Bajo = el tope de posición limita tanto '
          'que la operación apenas arriesga.',
  'adx':
      'Menos de 20 = sin tendencia clara; 20-40 = tendencia sana; más de 40 = muy extendida.',
  'ema20_run':
      '+8 = lleva 8 cierres seguidos sobre la EMA20; −3 = lleva 3 bajo ella.',
  'earn_bd':
      'Días hábiles hasta los próximos resultados. Para operaciones de 2 semanas, mínimo 15.',
  'd_e50_200': 'Positivo = EMA50 por encima de la EMA200.',
  'short_pub':
      'Suma de las posiciones cortas netas que la CNMV publica (las de 0,5 % o más '
          'del capital). 0 = ningún fondo supera ese umbral. Solo valores españoles.',
  'short_n':
      'Número de fondos con una posición corta publicada (0,5 % o más). Solo valores españoles.',
  's_ema20':
      'Cambio % de la EMA en las últimas 5 sesiones. Mínimo 0 = ascendente; máximo 0 = descendente.',
  's_ema50':
      'Cambio % de la EMA en las últimas 5 sesiones. Mínimo 0 = ascendente; máximo 0 = descendente.',
  's_ema100':
      'Cambio % de la EMA en las últimas 5 sesiones. Mínimo 0 = ascendente; máximo 0 = descendente.',
  's_ema200':
      'Cambio % de la EMA en las últimas 5 sesiones. Mínimo 0 = ascendente; máximo 0 = descendente.',
};

// ----------------------------------------------------------------- filtros y presets

class _Filter {
  _Filter(this.key, {this.min, this.max, this.boolVal, this.values});
  final String key;
  double? min;
  double? max;
  bool? boolVal;
  Set<String>? values;

  _Filter copy() => _Filter(key,
      min: min,
      max: max,
      boolVal: boolVal,
      values: values == null ? null : Set<String>.of(values!));

  Map<String, dynamic> toJson() => {
        'k': key,
        'min': min,
        'max': max,
        'b': boolVal,
        'v': values?.toList(),
      };

  static _Filter fromJson(Map<String, dynamic> j) => _Filter(
        j['k'].toString(),
        min: (j['min'] as num?)?.toDouble(),
        max: (j['max'] as num?)?.toDouble(),
        boolVal: j['b'] as bool?,
        values: (j['v'] as List?)?.map((e) => e.toString()).toSet(),
      );
}

class _Preset {
  _Preset(this.name, this.mode, this.filters, {this.sortKey, this.sortAsc});
  final String name;
  final String mode;
  final List<_Filter> filters;
  final String? sortKey;
  final bool? sortAsc;

  Map<String, dynamic> toJson() => {
        'n': name,
        'm': mode,
        'f': filters.map((e) => e.toJson()).toList(),
        's': sortKey,
        'a': sortAsc,
      };

  static _Preset fromJson(Map<String, dynamic> j) => _Preset(
        j['n'].toString(),
        j['m'].toString(),
        (j['f'] as List)
            .map((e) => _Filter.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        sortKey: j['s'] as String?,
        sortAsc: j['a'] as bool?,
      );
}

List<_Preset> _builtInPresets() => [
      _Preset(
          'Swing 2 semanas (filtros duros + puntuación)',
          'long',
          [
            _Filter('d_ema20', min: 0),
            _Filter('d_ema50', min: 0),
            _Filter('d_e50_200', min: 0),
            _Filter('days_to_earn', min: 22),
            _Filter('p_stop_atr', min: 1),
            _Filter('p_rr', min: 1.5),
            _Filter('dvol_m', min: 50),
            _Filter('p_risk_pct', min: 60),
          ],
          sortKey: 'score',
          sortAsc: false),
      _Preset(
          'Pullback alcista con martillo en EMA20/50',
          'long',
          [
            _Filter('d_ema200', min: 0),
            _Filter('s_ema50', min: 0),
            _Filter('hb_2050', max: 3),
          ],
          sortKey: 'hb_rr',
          sortAsc: false),
      _Preset(
          'Tendencia alcista limpia',
          'long',
          [
            _Filter('trend', values: {'alcista'}),
            _Filter('clean6m', min: 0.7),
            _Filter('rsi_d', max: 70),
          ],
          sortKey: 'clean6m',
          sortAsc: false),
      _Preset(
          'Ruptura: cierre sobre máximo de ayer y EMA20',
          'long',
          [
            _Filter('brk_long', boolVal: true),
            _Filter('d_ema50', min: 0),
            _Filter('vol_rel', min: 1.2),
          ],
          sortKey: 'vol_rel',
          sortAsc: false),
      _Preset(
          'Sobreventa dentro de tendencia alcista',
          'long',
          [
            _Filter('d_ema200', min: 0),
            _Filter('rsi_d', max: 35),
          ],
          sortKey: 'rsi_d',
          sortAsc: true),
      _Preset(
          'Más fuerte que su industria (3 meses)',
          'long',
          [
            _Filter('rs_ind_3m', min: 5),
            _Filter('d_ema50', min: 0),
          ],
          sortKey: 'rs_ind_3m',
          sortAsc: false),
      _Preset(
          'Bate resultados y suben estimaciones',
          'long',
          [
            _Filter('eps_beats_4q', min: 3),
            _Filter('rev30', min: 0),
          ],
          sortKey: 'rev30',
          sortAsc: false),
      _Preset(
          'Barata frente a su industria',
          'long',
          [
            _Filter('pe_vs_ind', max: 0.8),
            _Filter('d_ema200', min: 0),
          ],
          sortKey: 'pe_vs_ind',
          sortAsc: true),
      _Preset(
          'Resultados en menos de 2 semanas',
          'long',
          [
            _Filter('days_to_earn', min: 0, max: 14),
          ],
          sortKey: 'days_to_earn',
          sortAsc: true),
      _Preset(
          'Swing 2 semanas (filtros duros + puntuación)',
          'short',
          [
            _Filter('d_ema20', max: 0),
            _Filter('d_ema50', max: 0),
            _Filter('d_e50_200', max: 0),
            _Filter('days_to_earn', min: 22),
            _Filter('p_stop_atr', min: 1),
            _Filter('p_rr', min: 1.5),
            _Filter('dvol_m', min: 50),
            _Filter('p_risk_pct', min: 60),
          ],
          sortKey: 'score',
          sortAsc: false),
      _Preset(
          'Rebote bajista con martillo bajista en EMA',
          'short',
          [
            _Filter('d_ema200', max: 0),
            _Filter('s_ema50', max: 0),
            _Filter('hs_any', max: 3),
          ],
          sortKey: 'hs_rr',
          sortAsc: false),
      _Preset(
          'Tendencia bajista limpia',
          'short',
          [
            _Filter('trend', values: {'bajista'}),
            _Filter('clean6m', max: -0.7),
            _Filter('rsi_d', min: 30),
          ],
          sortKey: 'clean6m',
          sortAsc: true),
      _Preset(
          'Ruptura bajista: cierre bajo mínimo de ayer y EMA20',
          'short',
          [
            _Filter('brk_short', boolVal: true),
            _Filter('d_ema50', max: 0),
            _Filter('vol_rel', min: 1.2),
          ],
          sortKey: 'vol_rel',
          sortAsc: false),
      _Preset(
          'Sobrecompra dentro de tendencia bajista',
          'short',
          [
            _Filter('d_ema200', max: 0),
            _Filter('rsi_d', min: 65),
          ],
          sortKey: 'rsi_d',
          sortAsc: false),
      _Preset(
          'Más débil que su industria y que el S&P (3 meses)',
          'short',
          [
            _Filter('rs_ind_3m', max: -5),
            _Filter('rs_spy_3m', max: -10),
          ],
          sortKey: 'rs_ind_3m',
          sortAsc: true),
      _Preset(
          'Falla resultados y bajan estimaciones',
          'short',
          [
            _Filter('eps_beats_4q', max: 1),
            _Filter('rev30', max: 0),
          ],
          sortKey: 'rev30',
          sortAsc: true),
      _Preset(
          'Cara frente a su industria y bajo EMA50',
          'short',
          [
            _Filter('pe_vs_ind', min: 1.5),
            _Filter('d_ema50', max: 0),
          ],
          sortKey: 'pe_vs_ind',
          sortAsc: false),
      _Preset(
          'Corto cómodo: poco dividendo y poco short interest',
          'short',
          [
            _Filter('div_yield', max: 1),
            _Filter('short_float', max: 5),
            _Filter('days_to_earn', min: 15),
            _Filter('d_ema50', max: 0),
          ],
          sortKey: 'r_3m',
          sortAsc: true),
    ];

// ----------------------------------------------------------------- utilidades

double? _d(dynamic v) => v is num ? v.toDouble() : null;

String _cur(Map<String, dynamic> r) => r['currency'] == 'EUR' ? '€' : '\$';

const Set<String> _kMoneyKeys = {
  'price',
  'high52',
  'low52',
  'hb_stop',
  'hs_stop',
  'day_high',
  'day_low',
  'p_entry',
  'p_stop',
  'p_target',
  'p_amount',
  'p_risk'
};

dynamic _minN(List<dynamic> l) {
  num? m;
  for (final v in l) {
    if (v is num && (m == null || v < m)) m = v;
  }
  return m;
}

int _cmp(dynamic a, dynamic b, bool asc) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  int c;
  if (a is num && b is num) {
    c = a.compareTo(b);
  } else if (a is bool && b is bool) {
    c = (a ? 1 : 0).compareTo(b ? 1 : 0);
  } else {
    c = a.toString().compareTo(b.toString());
  }
  return asc ? c : -c;
}

String _num(double d, int dec) {
  final neg = d < 0;
  final s = d.abs().toStringAsFixed(dec);
  final parts = s.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  final out =
      parts.length > 1 ? '${buf.toString()},${parts[1]}' : buf.toString();
  return neg ? '-$out' : out;
}

String _plain(double? d) {
  if (d == null) return '';
  if (d == d.roundToDouble()) return d.toInt().toString();
  return d.toString().replaceAll('.', ',');
}

double? _parse(String s) {
  final t = s.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

String _fmtDate(String iso) {
  final p = iso.split('-');
  if (p.length != 3) return iso;
  return '${p[2]}-${p[1]}-${p[0]}';
}

String _fmt(_Field f, dynamic v) {
  if (v == null) return '–';
  if (_kSessionKeys.contains(f.key) && v is num) return 'Sí (${v.toInt()})';
  if (_kCrossKeys.contains(f.key) && v is num) {
    final n = v.toInt();
    if (n == 0) return 'Hoy';
    return n == 1 ? 'Hace 1 día' : 'Hace $n días';
  }
  switch (f.kind) {
    case _Kind.boolean:
      return v == true ? 'Sí' : 'No';
    case _Kind.number:
      if (v is! num) return v.toString();
      final d = v.toDouble();
      var s = _num(d, f.dec);
      if (f.signed && d > 0) s = '+$s';
      return s;
    case _Kind.date:
      return _fmtDate(v.toString());
    case _Kind.text:
    case _Kind.choice:
      return v.toString();
  }
}

Color? _colorFor(_Field f, dynamic v) {
  if (v == null) return null;
  if (f.signed && v is num) {
    if (v > 0) return _kGreen;
    if (v < 0) return _kRed;
    return null;
  }
  if (f.key == 'trend') {
    if (v == 'alcista') return _kGreen;
    if (v == 'bajista') return _kRed;
  }
  if (f.key == 'slope_all') {
    if (v == 'todas suben') return _kGreen;
    if (v == 'todas bajan') return _kRed;
  }
  if (f.key == 'brk_long' && v == true) return _kGreen;
  if (f.key == 'brk_short' && v == true) return _kRed;
  if (_kSessionKeys.contains(f.key) && v is num) {
    return f.key.startsWith('hb') ? _kGreen : _kRed;
  }
  if (_kCrossKeys.contains(f.key) && v is num) {
    return (f.key.startsWith('xu') || f.key == 'gc') ? _kGreen : _kRed;
  }
  if (v is num) {
    switch (f.key) {
      case 'p_stop_atr':
        return v < 1 ? _kRed : (v >= 1.5 ? _kGreen : null);
      case 'p_rr':
        return v < 1.2 ? _kRed : (v >= 1.5 ? _kGreen : null);
      case 'earn_bd':
        return v <= 15 ? _kRed : null;
      case 'days_to_earn':
        return v <= 21 ? _kRed : null;
      case 'score':
        return v >= 70 ? _kGreen : (v < 40 ? _cMuted : null);
      case 'adx':
        return (v >= 20 && v <= 40) ? _kGreen : null;
    }
  }
  if (f.key == 'hb_rr' && v is num) return _kGreen;
  if (f.key == 'hs_rr' && v is num) return _kRed;
  return null;
}

bool _match(Map<String, dynamic> r, _Filter f) {
  final fd = _kFieldMap[f.key];
  if (fd == null) return true;
  final v = r[f.key];
  switch (fd.kind) {
    case _Kind.boolean:
      if (f.boolVal == null) return true;
      return (v == true) == f.boolVal;
    case _Kind.choice:
    case _Kind.text:
      final vals = f.values;
      if (vals == null || vals.isEmpty) return true;
      return vals.contains(v?.toString());
    case _Kind.number:
      if (f.min == null && f.max == null) return true;
      if (v is! num) return false;
      final d = v.toDouble();
      if (f.min != null && d < f.min!) return false;
      if (f.max != null && d > f.max!) return false;
      return true;
    case _Kind.date:
      return true;
  }
}

String _filterLabel(_Filter f) {
  final fd = _kFieldMap[f.key];
  final name = fd?.label ?? f.key;
  if (fd == null) return name;
  switch (fd.kind) {
    case _Kind.boolean:
      return '$name: ${f.boolVal == true ? 'sí' : 'no'}';
    case _Kind.choice:
    case _Kind.text:
      final v = (f.values ?? <String>{}).toList()..sort();
      final txt = v.length <= 3
          ? v.join(', ')
          : '${v.take(3).join(', ')} y ${v.length - 3} más';
      return '$name: $txt';
    case _Kind.number:
      if (f.min != null && f.max != null) {
        return '$name entre ${_plain(f.min)} y ${_plain(f.max)}';
      }
      if (f.min != null) return '$name ≥ ${_plain(f.min)}';
      return '$name ≤ ${_plain(f.max)}';
    case _Kind.date:
      return name;
  }
}

ButtonStyle _outlineStyle({Color fg = _cText}) => OutlinedButton.styleFrom(
      foregroundColor: fg,
      side: const BorderSide(color: _cBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );

ButtonStyle _fillStyle(Color fill) => FilledButton.styleFrom(
      backgroundColor: fill,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    );

// ----------------------------------------------------------------- widget raíz

class ScreenerApp extends StatefulWidget {
  const ScreenerApp({
    super.key,
    this.width,
    this.height,
  });

  final double? width;
  final double? height;

  @override
  State<ScreenerApp> createState() => _ScreenerAppState();
}

class _ScreenerAppState extends State<ScreenerApp> {
  late final Stream<fba.User?> _auth =
      fba.FirebaseAuth.instance.authStateChanges();

  @override
  Widget build(BuildContext context) {
    return _themed(LayoutBuilder(builder: (context, c) {
      final mq = MediaQuery.of(context);
      final w = (widget.width != null && widget.width!.isFinite)
          ? widget.width!
          : (c.hasBoundedWidth ? c.maxWidth : mq.size.width);
      final h = (widget.height != null && widget.height!.isFinite)
          ? widget.height!
          : (c.hasBoundedHeight
              ? c.maxHeight
              : mq.size.height - mq.padding.top - mq.padding.bottom);
      return SizedBox(
        width: w,
        height: h,
        child: Material(
          color: _cBg,
          child: StreamBuilder<fba.User?>(
            stream: _auth,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.data == null) return const _Login();
              return _Home(width: w, height: h);
            },
          ),
        ),
      );
    }));
  }
}

// ----------------------------------------------------------------- login

class _Login extends StatefulWidget {
  const _Login();

  @override
  State<_Login> createState() => _LoginState();
}

class _LoginState extends State<_Login> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await fba.FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(), password: _pass.text);
    } on fba.FirebaseAuthException catch (e) {
      if (mounted) setState(() => _err = e.message ?? e.code);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: _cPanel,
            border: Border.all(color: _cBorder),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _kGreen.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.trending_up, color: _kGreen),
                  ),
                  const SizedBox(width: 12),
                  const Text('Screener',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              const Text('S&P 500 + Nasdaq-100',
                  style: TextStyle(color: _cMuted)),
              const SizedBox(height: 28),
              const Text('Email',
                  style: TextStyle(color: _cMuted, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 16),
              const Text('Contraseña',
                  style: TextStyle(color: _cMuted, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _pass,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _busy ? null : _go(),
              ),
              if (_err != null) ...[
                const SizedBox(height: 14),
                Text(_err!, style: const TextStyle(color: _kRed)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                style: _fillStyle(_kGreenFill),
                onPressed: _busy ? null : _go,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Entrar',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- pantalla principal

class _Home extends StatefulWidget {
  const _Home({required this.width, required this.height});
  final double width;
  final double height;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  SharedPreferences? _prefs;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _sectors = {};
  Map<String, dynamic> _industries = {};
  Map<String, dynamic> _bench = {};
  Map<String, dynamic> _sectorsEu = {};
  double? _fx;
  Map<String, dynamic> _regime = {};
  bool _showRed = false;
  String _asof = '';

  String _mode = 'long';
  int _tab = 0;
  String? _selected;
  Map<String, dynamic>? _detail;
  final Map<String, List<_Filter>> _filters = {'long': [], 'short': []};
  final Map<String, List<String>> _cols = {
    'long': List<String>.of(_kDefaultCols['long']!),
    'short': List<String>.of(_kDefaultCols['short']!),
  };
  final Map<String, Map<String, double>> _colW = {'long': {}, 'short': {}};
  final Map<String, Set<String>> _favs = {
    'long': <String>{},
    'short': <String>{}
  };
  final Map<String, bool> _onlyFav = {'long': false, 'short': false};
  final Map<String, String> _sortKey = {'long': 'r_3m', 'short': 'r_3m'};
  final Map<String, bool> _sortAsc = {'long': false, 'short': true};
  List<_Preset> _userPresets = [];
  String _search = '';
  double _risk = 1000;
  double _maxPos = 50000;

  final _searchCtl = TextEditingController();
  final _riskCtl = TextEditingController();
  final _maxCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    if (_syncTimer?.isActive ?? false) {
      _syncTimer!.cancel();
      _pushSettings();
    }
    _searchCtl.dispose();
    _riskCtl.dispose();
    _maxCtl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _restore();
    } catch (_) {}
    await _pullSettings();
    _riskCtl.text = _plain(_risk);
    _maxCtl.text = _plain(_maxPos);
    await _load();
  }

  // ---------------------------------------------------- sincronización por usuario
  // Favoritos, presets, filtros, columnas, orden, riesgo y posición máxima se
  // guardan en Firestore users/{uid} para compartirlos entre dispositivos.
  // Los anchos de columna y el modo Largos/Cortos quedan en cada dispositivo.

  Timer? _syncTimer;
  bool _syncing = false;

  String? get _uid => fba.FirebaseAuth.instance.currentUser?.uid;

  Map<String, dynamic> _settingsJson() => {
        'v': 1,
        'favs': {
          for (final m in ['long', 'short']) m: _favs[m]!.toList()
        },
        'presets': _userPresets.map((e) => e.toJson()).toList(),
        'filters': {
          for (final m in ['long', 'short'])
            m: _filters[m]!.map((e) => e.toJson()).toList()
        },
        'cols': {
          for (final m in ['long', 'short']) m: _cols[m]
        },
        'sortKey': _sortKey,
        'sortAsc': _sortAsc,
        'risk': _risk,
        'maxPos': _maxPos,
      };

  void _applySettings(Map<String, dynamic> j, {required bool mergeLocal}) {
    try {
      for (final m in ['long', 'short']) {
        final rf = ((j['favs'] as Map?)?[m] as List?)
            ?.map((e) => e.toString())
            .toSet();
        if (rf != null) {
          _favs[m] = mergeLocal ? {..._favs[m]!, ...rf} : rf;
        }
        final rfl = (j['filters'] as Map?)?[m] as List?;
        if (rfl != null) {
          _filters[m] = rfl
              .map((e) => _Filter.fromJson(Map<String, dynamic>.from(e as Map)))
              .where((f) => _kFieldMap.containsKey(f.key))
              .toList();
        }
        final rc = (j['cols'] as Map?)?[m] as List?;
        if (rc != null) {
          final c = rc
              .map((e) => e.toString())
              .where(_kFieldMap.containsKey)
              .toList();
          if (c.isNotEmpty) _cols[m] = c;
        }
        final sk = (j['sortKey'] as Map?)?[m];
        if (sk is String && _kFieldMap.containsKey(sk)) _sortKey[m] = sk;
        final sa = (j['sortAsc'] as Map?)?[m];
        if (sa is bool) _sortAsc[m] = sa;
      }
      final rp = (j['presets'] as List?)
          ?.map((e) => _Preset.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (rp != null) {
        if (mergeLocal) {
          final names = rp.map((p) => '${p.mode}|${p.name}').toSet();
          _userPresets = [
            ...rp,
            ..._userPresets
                .where((p) => !names.contains('${p.mode}|${p.name}')),
          ];
        } else {
          _userPresets = rp;
        }
      }
      final r = _d(j['risk']);
      if (r != null && r > 0) _risk = r;
      final mp = _d(j['maxPos']);
      if (mp != null && mp > 0) _maxPos = mp;
    } catch (_) {}
  }

  Future<void> _pullSettings() async {
    final uid = _uid;
    if (uid == null) return;
    _syncing = true;
    try {
      final prevUid = _prefs?.getString('scr_sync_uid');
      final doc = await cf.FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final m = doc.data();
      final remote = (m != null && m['data'] is String)
          ? jsonDecode(m['data'] as String) as Map<String, dynamic>
          : null;
      if (prevUid != null && prevUid != uid) {
        // Este dispositivo era de otro usuario: no mezclar sus ajustes.
        for (final k in ['long', 'short']) {
          _favs[k] = <String>{};
          _filters[k] = [];
        }
        _userPresets = [];
      }
      final firstHere = prevUid != uid;
      if (remote != null) {
        _applySettings(remote, mergeLocal: firstHere && prevUid == null);
      }
      if (mounted) setState(() {});
      _save(push: false);
      await _prefs?.setString('scr_sync_uid', uid);
      if (remote == null || (firstHere && prevUid == null))
        await _pushSettings();
    } catch (_) {
      // Sin conexión o sin permisos: se sigue con los ajustes del dispositivo.
    } finally {
      _syncing = false;
    }
  }

  void _schedulePush() {
    if (_syncing) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 800), _pushSettings);
  }

  Future<void> _pushSettings() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await cf.FirebaseFirestore.instance.collection('users').doc(uid).set({
        'data': jsonEncode(_settingsJson()),
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  Future<void> _refreshAll() async {
    await _pullSettings();
    _computePlans();
    _riskCtl.text = _plain(_risk);
    _maxCtl.text = _plain(_maxPos);
    await _load();
  }

  // ---------------------------------------------------- persistencia

  void _restore() {
    final p = _prefs;
    if (p == null) return;
    try {
      _mode = p.getString('scr_mode') ?? 'long';
      for (final m in ['long', 'short']) {
        final fs = p.getString('scr_f_$m');
        if (fs != null) {
          _filters[m] = (jsonDecode(fs) as List)
              .map((e) => _Filter.fromJson(Map<String, dynamic>.from(e as Map)))
              .where((f) => _kFieldMap.containsKey(f.key))
              .toList();
        }
        final cs = p.getStringList('scr_c_$m');
        if (cs != null && cs.isNotEmpty) {
          _cols[m] = cs.where(_kFieldMap.containsKey).toList();
        }
        final fv = p.getStringList('scr_fav_$m');
        if (fv != null) _favs[m] = fv.toSet();
        _onlyFav[m] = p.getBool('scr_of_$m') ?? false;
        final ws = p.getString('scr_w_$m');
        if (ws != null) {
          final mw = Map<String, dynamic>.from(jsonDecode(ws) as Map);
          _colW[m] = {
            for (final e in mw.entries)
              if (e.value is num) e.key: (e.value as num).toDouble()
          };
        }
        final sk = p.getString('scr_s_$m');
        if (sk != null && _kFieldMap.containsKey(sk)) _sortKey[m] = sk;
        final sa = p.getBool('scr_a_$m');
        if (sa != null) _sortAsc[m] = sa;
      }
      final ps = p.getString('scr_presets');
      if (ps != null) {
        _userPresets = (jsonDecode(ps) as List)
            .map((e) => _Preset.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      _risk = p.getDouble('scr_risk') ?? _risk;
      _maxPos = p.getDouble('scr_maxpos') ?? _maxPos;
    } catch (_) {}
  }

  void _save({bool push = true}) {
    if (push) _schedulePush();
    final p = _prefs;
    if (p == null) return;
    try {
      p.setString('scr_mode', _mode);
      for (final m in ['long', 'short']) {
        p.setString('scr_f_$m',
            jsonEncode(_filters[m]!.map((e) => e.toJson()).toList()));
        p.setStringList('scr_c_$m', _cols[m]!);
        p.setString('scr_w_$m', jsonEncode(_colW[m]));
        p.setStringList('scr_fav_$m', _favs[m]!.toList());
        p.setBool('scr_of_$m', _onlyFav[m]!);
        p.setString('scr_s_$m', _sortKey[m]!);
        p.setBool('scr_a_$m', _sortAsc[m]!);
      }
      p.setString('scr_presets',
          jsonEncode(_userPresets.map((e) => e.toJson()).toList()));
      p.setDouble('scr_risk', _risk);
      p.setDouble('scr_maxpos', _maxPos);
    } catch (_) {}
  }

  // ---------------------------------------------------- carga de datos

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = cf.FirebaseFirestore.instance;
      final meta = await db.collection('screener').doc('latest').get();
      final m = meta.data();
      if (m == null) {
        throw Exception('Todavía no hay datos. Ejecuta el job una vez.');
      }
      final n = (m['parts'] as num?)?.toInt() ?? 0;
      if (n <= 0) throw Exception('El documento "latest" no indica partes.');
      final docs = await Future.wait(List.generate(
          n, (i) => db.collection('screener').doc('part$i').get()));
      final sb = StringBuffer();
      for (final d in docs) {
        final s = d.data()?['data'];
        if (s is! String) throw Exception('Falta el documento ${d.id}.');
        sb.write(s);
      }
      final j = jsonDecode(sb.toString()) as Map<String, dynamic>;
      final cols = (j['cols'] as List).map((e) => e.toString()).toList();
      final rows = <Map<String, dynamic>>[];
      for (final raw in (j['rows'] as List)) {
        final l = raw as List;
        final r = <String, dynamic>{};
        for (var i = 0; i < cols.length && i < l.length; i++) {
          r[cols[i]] = l[i];
        }
        r['hb_2050'] = _minN([r['hb20'], r['hb50']]);
        r['hb_any'] = _minN([r['hb20'], r['hb50'], r['hb100'], r['hb200']]);
        r['hs_any'] = _minN([r['hs20'], r['hs50'], r['hs100'], r['hs200']]);
        final sl = [r['s_ema20'], r['s_ema50'], r['s_ema100'], r['s_ema200']];
        if (sl.every((x) => x is num)) {
          final ns = sl.cast<num>();
          r['slope_all'] = ns.every((x) => x > 0)
              ? 'todas suben'
              : (ns.every((x) => x < 0) ? 'todas bajan' : 'mixtas');
        }
        rows.add(r);
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _sectors = Map<String, dynamic>.from((j['sectors'] as Map?) ?? {});
        _industries =
            Map<String, dynamic>.from((j['industries'] as Map?) ?? {});
        _bench = Map<String, dynamic>.from((j['benchmarks'] as Map?) ?? {});
        _sectorsEu = Map<String, dynamic>.from((j['sectors_eu'] as Map?) ?? {});
        _fx = _d(((j['fx'] as Map?) ?? {})['EURUSD']);
        _regime = Map<String, dynamic>.from((j['regime'] as Map?) ?? {});
        _computePlans();
        _asof = (j['asof'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ---------------------------------------------------- plan de entrada y puntuación

  String _regimeOf(Map<String, dynamic> r) {
    final key = r['region'] == 'EU' || r['currency'] == 'EUR' ? 'eu' : 'us';
    return ((_regime[key] as Map?)?['status'] ?? 'ambar').toString();
  }

  /// Calcula entrada, stop, objetivo, B/R y tamaño para el modo actual.
  /// Largos: entrada sobre el máximo de la última sesión, stop en su mínimo
  /// (o el del martillo si es más bajo). Cortos: al revés.
  void _computePlans() {
    final long = _mode == 'long';
    for (final r in _rows) {
      for (final k in const [
        'p_entry',
        'p_stop',
        'p_stop_pct',
        'p_stop_atr',
        'p_target',
        'p_target_pct',
        'p_rr',
        'p_shares',
        'p_amount',
        'p_risk',
        'p_risk_pct'
      ]) {
        r[k] = null;
      }
      final hi = _d(r['day_high']);
      final lo = _d(r['day_low']);
      final px = _d(r['price']);
      final atrp = _d(r['atr_pct']);
      if (hi == null || lo == null || px == null) continue;
      final entry = long ? hi : lo;
      final pat = long ? _d(r['hb_stop']) : _d(r['hs_stop']);
      final stop = long
          ? (pat != null ? math.min(lo, pat) : lo)
          : (pat != null ? math.max(hi, pat) : hi);
      final dist = (entry - stop).abs();
      if (dist <= 0 || entry <= 0) continue;
      final tgt = long ? _d(r['tgt_l']) : _d(r['tgt_s']);
      final fx =
          (r['currency'] == 'EUR' && _fx != null && _fx! > 0) ? _fx! : 1.0;
      final risk = _risk / fx;
      final maxPos = _maxPos / fx;
      final shares = (math.min(risk / dist, maxPos / entry) / 5).floor() * 5;
      r['p_entry'] = entry;
      r['p_stop'] = stop;
      r['p_stop_pct'] = dist / entry * 100;
      if (atrp != null && atrp > 0) r['p_stop_atr'] = dist / (atrp * px / 100);
      if (tgt != null) {
        final run = (tgt - entry).abs();
        r['p_target'] = tgt;
        r['p_target_pct'] = run / entry * 100;
        r['p_rr'] = run / dist;
      }
      r['p_shares'] = shares;
      r['p_amount'] = shares * entry;
      r['p_risk'] = shares * dist;
      r['p_risk_pct'] = risk > 0 ? shares * dist / risk * 100 : null;
    }
  }

  /// Puntuación 0-100 sobre los valores que pasan los filtros.
  /// Fuerza relativa 30 (15 percentil 3m vs sector + 15 percentil 1m vs índice),
  /// entrada 25 (extensión sobre EMA20 en ATR), B/R 20, volumen 10, ADX 10,
  /// colchón hasta máx./mín. 52 sem. 5. Multiplicador por régimen de mercado.
  void _score(List<Map<String, dynamic>> rows) {
    final long = _mode == 'long';
    final sign = long ? 1.0 : -1.0;
    Map<Map<String, dynamic>, double> pctRank(
        double? Function(Map<String, dynamic>) get) {
      final vals = <Map<String, dynamic>, double>{};
      for (final r in rows) {
        final v = get(r);
        if (v != null) vals[r] = v * sign;
      }
      final sorted = vals.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final out = <Map<String, dynamic>, double>{};
      final n = sorted.length;
      for (var i = 0; i < n; i++) {
        out[sorted[i].key] = n == 1 ? 1.0 : i / (n - 1);
      }
      return out;
    }

    final rs3 = pctRank((r) => _d(r['rs_sec_3m']) ?? _d(r['rs_ind_3m']));
    final rs1 = pctRank((r) => _d(r['rs_idx_1m']) ?? _d(r['rs_spy_1m']));
    for (final r in rows) {
      var sc = 15 * (rs3[r] ?? 0) + 15 * (rs1[r] ?? 0);
      final ext = _d(r['a_ema20']);
      if (ext != null) {
        final e = ext * sign;
        sc += e < 0 ? 15 : (e <= 1 ? 25 : (e <= 2 ? 15 : 0));
      }
      final rr = _d(r['p_rr']);
      if (rr != null) sc += 20 * ((rr - 1.5) / 1.5).clamp(0.0, 1.0);
      final vr = _d(r['vol_rel']);
      final chg = _d(r['chg_1d']) ?? 0;
      if (vr != null) {
        final withMove = long ? chg > 0 : chg < 0;
        sc += (vr >= 1.2 && withMove) ? 10 : (vr >= 1 ? 5 : 0);
      }
      final ax = _d(r['adx']);
      if (ax != null) sc += (ax >= 20 && ax <= 40) ? 10 : 4;
      final room = long ? _d(r['d_high52']) : _d(r['d_low52']);
      if (room != null && (long ? room <= -5 : room >= 5)) sc += 5;
      final st = _regimeOf(r);
      final mult = long
          ? (st == 'verde' ? 1.0 : (st == 'ambar' ? 0.7 : 0.5))
          : (st == 'verde' ? 0.7 : 1.0);
      r['score'] = (sc * mult).round();
    }
  }

  // ---------------------------------------------------- lógica

  Color get _accent => _mode == 'long' ? _kGreen : _kRed;
  Color get _accentFill => _mode == 'long' ? _kGreenFill : _kRedFill;

  List<Map<String, dynamic>> _visible() {
    final fs = _filters[_mode]!;
    final q = _search.trim().toLowerCase();
    final onlyFav = _onlyFav[_mode]!;
    final favs = _favs[_mode]!;
    final out = _rows.where((r) {
      if (q.isNotEmpty) {
        final t = (r['ticker'] ?? '').toString().toLowerCase();
        final nm = (r['name'] ?? '').toString().toLowerCase();
        if (!t.startsWith(q) && !nm.contains(q)) return false;
      }
      if (onlyFav) return favs.contains(r['ticker']?.toString());
      if (_mode == 'long' && !_showRed && _regimeOf(r) == 'rojo') return false;
      for (final f in fs) {
        if (!_match(r, f)) return false;
      }
      return true;
    }).toList();
    _score(out);
    final k = _sortKey[_mode]!;
    final asc = _sortAsc[_mode]!;
    out.sort((a, b) => _cmp(a[k], b[k], asc));
    return out;
  }

  void _setMode(String m) {
    setState(() {
      _mode = m;
      _detail = null;
      _computePlans();
    });
    _save();
  }

  void _applyPreset(_Preset p, void Function(VoidCallback) set) {
    set(() {
      _filters[_mode] = p.filters.map((e) => e.copy()).toList();
      if (p.sortKey != null) _sortKey[_mode] = p.sortKey!;
      if (p.sortAsc != null) _sortAsc[_mode] = p.sortAsc!;
    });
    _save();
  }

  void _applyGroupFilter(String key, String value, {Set<String>? markets}) {
    setState(() {
      final fs = _filters[_mode]!;
      fs.removeWhere(
          (f) => f.key == 'sector' || f.key == 'ind_name' || f.key == 'market');
      fs.add(_Filter(key, values: {value}));
      if (markets != null) fs.add(_Filter('market', values: markets));
      _onlyFav[_mode] = false;
      _tab = 0;
    });
    _save();
  }

  void _toast(String msg) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------- diálogos

  Future<Object?> _editFilter(_Field fd, _Filter? cur) {
    return showDialog<Object>(
      context: context,
      builder: (_) => _themed(
          _FilterEditor(field: fd, initial: cur, rows: _rows, accent: _accent)),
    );
  }

  Future<_Field?> _pickField() {
    return showDialog<_Field>(
      context: context,
      builder: (_) => _themed(_FieldPicker(accent: _accent)),
    );
  }

  Future<String?> _askText(String title, String label) {
    return showDialog<String>(
      context: context,
      builder: (_) => _themed(_TextAsk(title: title, label: label)),
    );
  }

  Future<void> _pickColumns() async {
    final res = await showDialog<List<String>>(
      context: context,
      builder: (_) => _themed(_ColumnPicker(
        current: _cols[_mode]!,
        defaults: _kDefaultCols[_mode]!,
        accent: _accent,
      )),
    );
    if (res != null && res.isNotEmpty) {
      setState(() => _cols[_mode] = res);
      _save();
    }
  }

  Future<void> _deletePresetDialog(void Function(VoidCallback) set) async {
    final us = _userPresets.where((p) => p.mode == _mode).toList();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _themed(SimpleDialog(
        backgroundColor: _cPanel,
        title: const Text('Borrar preset'),
        children: [
          for (final p in us)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p.name),
              child: Text(p.name),
            ),
        ],
      )),
    );
    if (name == null) return;
    set(() =>
        _userPresets.removeWhere((p) => p.mode == _mode && p.name == name));
    _save();
  }

  void _openDetail(Map<String, dynamic> r) {
    setState(() {
      _selected = r['ticker']?.toString();
      _detail = r;
    });
  }

  void _closeDetail() => setState(() => _detail = null);

  void _toggleFav(String t) {
    setState(() {
      final f = _favs[_mode]!;
      if (!f.remove(t)) f.add(t);
    });
    _save();
  }

  String _favText() {
    final long = _mode == 'long';
    final favs = _favs[_mode]!;
    final rows =
        _rows.where((r) => favs.contains(r['ticker']?.toString())).toList();
    _score(rows);
    rows.sort((a, b) => _cmp(a['score'], b['score'], false));

    String sg(dynamic v, {int dec = 1, String suf = ' %'}) {
      final d = _d(v);
      if (d == null) return '–';
      return '${d > 0 ? '+' : ''}${_num(d, dec)}$suf';
    }

    String nv(dynamic v, {int dec = 2}) {
      final d = _d(v);
      return d == null ? '–' : _num(d, dec);
    }

    String st(String k) {
      final m = _regime[k] as Map?;
      final s = (m?['status'] ?? '').toString();
      return s == 'verde'
          ? 'VERDE'
          : (s == 'rojo' ? 'ROJO' : (s.isEmpty ? '–' : 'ÁMBAR'));
    }

    final us = _regime['us'] as Map?;
    final eu = _regime['eu'] as Map?;
    final b = StringBuffer();
    b.writeln(
        '${long ? 'Favoritos largos' : 'Favoritos cortos'} · cierre del ${_fmtDate(_asof)}');
    if (_regime.isNotEmpty) {
      b.writeln(
          'Mercado EE. UU.: ${st('us')} (SPY ${sg(us?['spy_ema20'])} s/EMA20, '
          '${sg(us?['spy_ema50'])} s/EMA50, VIX ${nv(us?['vix'], dec: 1)}, '
          '${nv(us?['breadth'], dec: 0)} % del S&P > EMA50)');
      b.writeln('Mercado Europa: ${st('eu')} (IBEX ${sg(eu?['ibex_ema20'])}, '
          'DAX ${sg(eu?['dax_ema20'])} s/EMA20, ${nv(eu?['breadth'], dec: 0)} % > EMA50)');
    }
    b.writeln(
        'Riesgo por operación ${_num(_risk, 0)} \$ · posición máx. ${_num(_maxPos, 0)} \$ '
        '· entrada ${long ? 'sobre el máximo' : 'bajo el mínimo'} de la última sesión');

    for (final r in rows) {
      final cs = _cur(r);
      b.writeln();
      b.writeln('${r['ticker']} · ${r['name']} — ${nv(r['price'])} $cs · '
          'puntuación ${r['score'] ?? '–'}${r['market'] != null ? ' · ${r['market']}' : ''}');

      final e = _d(r['p_entry']);
      if (e != null) {
        final tgt = _d(r['p_target']);
        b.writeln('Entrada ${nv(e)} · stop ${nv(r['p_stop'])} '
            '(${nv(r['p_stop_pct'], dec: 1)} % · ${nv(r['p_stop_atr'], dec: 1)} ATR) · '
            '${tgt != null ? 'objetivo ${nv(tgt)} (${long ? '+' : '−'}${nv(r['p_target_pct'], dec: 1)} %) · '
                'B/R ${nv(r['p_rr'])}' : 'sin objetivo (${long ? 'en máximos' : 'en mínimos'})'}');
        b.writeln(
            'Tamaño ${r['p_shares'] ?? '–'} acc. · ${nv(r['p_amount'], dec: 0)} $cs · '
            'riesgo real ${nv(r['p_risk'], dec: 0)} $cs (${nv(r['p_risk_pct'], dec: 0)} %)');
      }
      b.writeln(
          'ATR ${nv(r['atr_pct'], dec: 1)} % · extensión EMA20 ${sg(r['a_ema20'], suf: ' ATR')} · '
          'ADX ${nv(r['adx'], dec: 0)} · RSI ${nv(r['rsi_d'], dec: 0)} · '
          'racha EMA20 ${sg(r['ema20_run'], dec: 0, suf: '')}');
      b.writeln('FR 3m vs sector ${sg(r['rs_sec_3m'], suf: '')} · '
          'FR 1m vs índice ${sg(r['rs_idx_1m'], suf: '')} · '
          'vol. relativo ${nv(r['vol_rel'])} · vol. medio ${nv(r['dvol_m'], dec: 0)} M');
      b.writeln(
          'EMA20 ${sg(r['d_ema20'])} · EMA50 ${sg(r['d_ema50'])} · EMA200 ${sg(r['d_ema200'])} · '
          'EMA50/200 ${sg(r['d_e50_200'])} · tendencia ${r['trend'] ?? '–'} · beta ${nv(r['beta'])}');
      final bd = r['earn_bd'];
      final ne = r['next_earn'];
      if (bd != null || ne != null) {
        final warn = (bd is num && bd <= 15) ? ' ⚠ dentro de la ventana' : '';
        b.writeln('Resultados en ${bd ?? '?'} días hábiles'
            '${ne != null ? ' (${_fmtDate(ne.toString())})' : ''}$warn');
      } else {
        b.writeln('Resultados: sin fecha');
      }
      if (!long) {
        final extra = <String>[];
        final dy = _d(r['div_yield']);
        if (dy != null && dy > 0) extra.add('dividendo ${_num(dy, 2)} %');
        final dx = r['days_to_exdiv'];
        if (dx != null) extra.add('ex-dividendo en $dx días');
        final sf = _d(r['short_float']);
        if (sf != null) extra.add('short ${_num(sf, 1)} % del float');
        final sp = _d(r['short_pub']);
        if (sp != null) extra.add('cortos CNMV ${_num(sp, 2)} %');
        if (extra.isNotEmpty) b.writeln(extra.join(' · '));
      }
    }
    return b.toString().trimRight();
  }

  Future<void> _shareFavs() async {
    final long = _mode == 'long';
    final title =
        '${long ? 'Favoritos largos' : 'Favoritos cortos'} · cierre del ${_fmtDate(_asof)}';
    final res = await showDialog<String>(
      context: context,
      builder: (_) => _themed(_ShareDialog(
        title: title,
        count: _favs[_mode]!.length,
        text: _favText(),
        accent: _accent,
      )),
    );
    if (!mounted) return;
    if (res == 'copied') _toast('Lista copiada');
    if (res == 'clear') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => _themed(AlertDialog(
          backgroundColor: _cPanel,
          title: const Text('Vaciar favoritos'),
          content: Text(
              '¿Quitar los ${_favs[_mode]!.length} favoritos de ${long ? 'largos' : 'cortos'}?'),
          actions: [
            TextButton(
                style: TextButton.styleFrom(foregroundColor: _cMuted),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                style: _fillStyle(_kRedFill),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Vaciar')),
          ],
        )),
      );
      if (ok == true) {
        setState(() => _favs[_mode]!.clear());
        _save();
      }
    }
  }

  _GridCol _tickerCol(double? w) {
    final f = _kFieldMap['ticker']!;
    final favs = _favs[_mode]!;
    return _GridCol(
      key: 'ticker',
      label: f.header,
      width: w ?? f.width,
      bold: true,
      text: (r) => (r['ticker'] ?? '').toString(),
      leading: (r) {
        final t = (r['ticker'] ?? '').toString();
        final on = favs.contains(t);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggleFav(t),
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(on ? Icons.star : Icons.star_border,
                    size: 17, color: on ? _kStar : _cMuted),
              ),
            ),
            r['has_logo'] == true
                ? _Logo(ticker: t, size: 18)
                : const SizedBox(width: 18, height: 18),
          ],
        );
      },
      trailing: (r) => Tooltip(
        message: 'Ver gráfico',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openTradingView((r['ticker'] ?? '').toString()),
          child: const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.candlestick_chart_outlined,
                size: 17, color: _cMuted),
          ),
        ),
      ),
    );
  }

  void _moveCol(String from, String to) {
    final l = _cols[_mode]!;
    final i = l.indexOf(from);
    final j = l.indexOf(to);
    if (i < 0 || j < 0 || i == j) return;
    setState(() {
      l.removeAt(i);
      final j2 = l.indexOf(to);
      l.insert(i < j ? j2 + 1 : j2, from);
    });
    _save();
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _cPanel,
      constraints: BoxConstraints(
          maxWidth: math.min(MediaQuery.of(context).size.width, 900)),
      builder: (ctx) => _themed(StatefulBuilder(builder: (ctx, setModal) {
        void set(VoidCallback fn) {
          setState(fn);
          setModal(() {});
        }

        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.85,
          child: _filterPanel(set, includeSearch: false),
        );
      })),
    );
  }

  // ---------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final wide = widget.width >= 900;
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = _errorView();
    } else if (_tab == 0) {
      body = _screener(wide);
    } else {
      body = _sectorsView();
    }
    final det = _detail;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: _cBg,
              child: Column(
                children: [
                  _topBar(wide),
                  const Divider(height: 1, color: _cDivider),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
          if (det != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeDetail,
                child: ColoredBox(color: Colors.black.withAlpha(90)),
              ),
            ),
          if (det != null)
            Positioned.fill(
              child: _Detail(
                key: ValueKey('${det['ticker']}_$_mode'),
                row: det,
                mode: _mode,
                risk: _risk,
                maxPos: _maxPos,
                fx: _fx,
                regime: _regimeOf(det),
                accent: _accent,
                accentFill: _accentFill,
                onClose: _closeDetail,
                isFav: _favs[_mode]!.contains(det['ticker']?.toString()),
                onToggleFav: () => _toggleFav(det['ticker'].toString()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: _cMuted),
            const SizedBox(height: 12),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
                style: _outlineStyle(),
                onPressed: _load,
                child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _modeToggle() {
    Widget seg(String m, String label, Color fill, Color txt) {
      final sel = _mode == m;
      return InkWell(
        onTap: () => _setMode(m),
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: 128,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? fill : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : txt)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _cSurface,
        border: Border.all(color: _cBorder),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('long', 'Largos', _kGreenFill, _kGreen),
          seg('short', 'Cortos', _kRedFill, _kRed),
        ],
      ),
    );
  }

  Widget _tabBtn(int i, String label) {
    final sel = _tab == i;
    return InkWell(
      onTap: () => setState(() => _tab = i),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: sel ? _accent : Colors.transparent, width: 2.5),
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 16,
                fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                color: sel ? _cText : _cMuted)),
      ),
    );
  }

  Widget _topBar(bool wide) {
    final right = <Widget>[
      if (_asof.isNotEmpty)
        Text('Cierre del ${_fmtDate(_asof)}',
            style: const TextStyle(fontSize: 14, color: _cMuted)),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Recargar datos',
        icon: const Icon(Icons.refresh, color: _cText),
        onPressed: _loading ? null : _refreshAll,
      ),
      Container(width: 1, height: 28, color: _cBorder),
      const SizedBox(width: 6),
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: _cText),
        onPressed: () => fba.FirebaseAuth.instance.signOut(),
        icon: const Icon(Icons.logout, size: 18),
        label: const Text('Salir'),
      ),
    ];
    final left = <Widget>[
      _modeToggle(),
      const SizedBox(width: 28),
      _tabBtn(0, 'Screener'),
      _tabBtn(1, 'Sectores e índices'),
    ];
    if (wide) {
      return Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [...left, const Spacer(), ...right]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [...left, ...right],
      ),
    );
  }

  Widget _searchField(void Function(VoidCallback) set) {
    return TextField(
      controller: _searchCtl,
      onChanged: (v) => set(() => _search = v),
      decoration: InputDecoration(
        hintText: 'Buscar ticker o empresa',
        prefixIcon: const Icon(Icons.search, size: 20, color: _cMuted),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, size: 18, color: _cMuted),
                onPressed: () {
                  _searchCtl.clear();
                  set(() => _search = '');
                },
              ),
      ),
    );
  }

  Widget _screener(bool wide) {
    final vis = _visible();
    final results = _results(vis);
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 300,
            color: _cBg,
            child: _filterPanel(setState),
          ),
          const VerticalDivider(width: 1, color: _cDivider),
          Expanded(child: results),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              OutlinedButton.icon(
                style: _outlineStyle(),
                onPressed: _openFilterSheet,
                icon: const Icon(Icons.tune, size: 18),
                label: Text('Filtros (${_filters[_mode]!.length})'),
              ),
              const SizedBox(width: 8),
              Expanded(child: _searchField(setState)),
            ],
          ),
        ),
        Expanded(child: results),
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 13.5, color: _cMuted)),
      );

  Widget _filterPanel(void Function(VoidCallback) set,
      {bool includeSearch = true}) {
    final fs = _filters[_mode]!;
    final accent = _accent;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        if (includeSearch) ...[
          _searchField(set),
          const SizedBox(height: 22),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                _mode == 'long' ? 'Filtros para largos' : 'Filtros para cortos',
                style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w600, color: accent),
              ),
            ),
            _presetMenu(set),
          ],
        ),
        const SizedBox(height: 14),
        if (fs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('Sin filtros: se muestran todas las empresas.',
                style: TextStyle(fontSize: 13, color: _cMuted)),
          ),
        for (var i = 0; i < fs.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: accent.withAlpha(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: accent.withAlpha(150)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final fd = _kFieldMap[fs[i].key];
                  if (fd == null) return;
                  final res = await _editFilter(fd, fs[i]);
                  if (res is _Filter) {
                    set(() => fs[i] = res);
                    _save();
                  } else if (res == 'remove') {
                    set(() => fs.removeAt(i));
                    _save();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 2, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_filterLabel(fs[i]),
                            style: const TextStyle(fontSize: 14)),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Quitar',
                        icon: Icon(Icons.close, size: 18, color: accent),
                        onPressed: () {
                          set(() => fs.removeAt(i));
                          _save();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        _DashedButton(
          label: 'Añadir filtro',
          onTap: () async {
            final fd = await _pickField();
            if (fd == null) return;
            final res = await _editFilter(fd, null);
            if (res is _Filter) {
              set(() {
                fs.removeWhere((f) => f.key == res.key);
                fs.add(res);
              });
              _save();
            }
          },
        ),
        if (fs.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: _cMuted),
              onPressed: () {
                set(() => fs.clear());
                _save();
              },
              child: const Text('Limpiar filtros'),
            ),
          ),
        const SizedBox(height: 20),
        const Divider(color: _cDivider, height: 1),
        const SizedBox(height: 22),
        const Text('Tamaño de posición',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        _label('Riesgo máximo por operación (\$)'),
        TextField(
          controller: _riskCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 16),
          onChanged: (v) {
            final d = _parse(v);
            if (d != null && d > 0) {
              setState(() {
                _risk = d;
                _computePlans();
              });
              _save();
            }
          },
        ),
        const SizedBox(height: 16),
        _label('Posición máxima (\$)'),
        TextField(
          controller: _maxCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 16),
          onChanged: (v) {
            final d = _parse(v);
            if (d != null && d > 0) {
              setState(() {
                _maxPos = d;
                _computePlans();
              });
              _save();
            }
          },
        ),
        const SizedBox(height: 10),
        const Text(
          'Acciones = riesgo ÷ distancia al stop, con tope de posición máxima '
          'y redondeo a múltiplos de 5.',
          style: TextStyle(fontSize: 12, color: _cMuted),
        ),
      ],
    );
  }

  Widget _presetMenu(void Function(VoidCallback) set) {
    final bi = _builtInPresets().where((p) => p.mode == _mode).toList();
    final us = _userPresets.where((p) => p.mode == _mode).toList();
    return PopupMenuButton<String>(
      tooltip: 'Presets',
      color: _cPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _cBorder),
      ),
      onSelected: (v) async {
        if (v == '__save') {
          final name = await _askText('Guardar preset', 'Nombre');
          if (name == null || name.trim().isEmpty) return;
          final nm = name.trim();
          set(() {
            _userPresets.removeWhere((p) => p.mode == _mode && p.name == nm);
            _userPresets.add(_Preset(
              nm,
              _mode,
              _filters[_mode]!.map((e) => e.copy()).toList(),
              sortKey: _sortKey[_mode],
              sortAsc: _sortAsc[_mode],
            ));
          });
          _save();
          _toast('Preset "$nm" guardado');
          return;
        }
        if (v == '__del') {
          await _deletePresetDialog(set);
          return;
        }
        final idx = int.tryParse(v.substring(2)) ?? 0;
        final p = v.startsWith('b:') ? bi[idx] : us[idx];
        _applyPreset(p, set);
      },
      itemBuilder: (ctx) => <PopupMenuEntry<String>>[
        for (var i = 0; i < bi.length; i++)
          PopupMenuItem<String>(value: 'b:$i', child: Text(bi[i].name)),
        if (us.isNotEmpty) const PopupMenuDivider(),
        for (var i = 0; i < us.length; i++)
          PopupMenuItem<String>(
            value: 'u:$i',
            child: Row(
              children: [
                Icon(Icons.star_outline, size: 16, color: _accent),
                const SizedBox(width: 8),
                Expanded(child: Text(us[i].name)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
            value: '__save',
            child: Text('Guardar filtros actuales como preset…')),
        if (us.isNotEmpty)
          const PopupMenuItem<String>(
              value: '__del', child: Text('Borrar un preset…')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: _cBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Presets', style: TextStyle(fontSize: 13.5)),
            SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 18, color: _cMuted),
          ],
        ),
      ),
    );
  }

  Widget _regimeBar() {
    if (_regime.isEmpty) return const SizedBox.shrink();
    final us = _regime['us'] as Map?;
    final eu = _regime['eu'] as Map?;
    String p(dynamic v) {
      final d = _d(v);
      return d == null ? '–' : '${d > 0 ? '+' : ''}${_num(d, 1)} %';
    }

    String n0(dynamic v) {
      final d = _d(v);
      return d == null ? '–' : _num(d, 0);
    }

    String label(String st) =>
        st == 'verde' ? 'VERDE' : (st == 'rojo' ? 'ROJO' : 'ÁMBAR');

    Widget chip(String title, Map? m, String detail) {
      final st = (m?['status'] ?? 'ambar').toString();
      final col = st == 'verde' ? _kGreen : (st == 'rojo' ? _kRed : _kAmber);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: col.withAlpha(20),
          border: Border.all(color: col.withAlpha(150)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text.rich(TextSpan(children: [
          TextSpan(
              text: '$title  ',
              style: const TextStyle(fontSize: 13, color: _cMuted)),
          TextSpan(
              text: label(st),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: col)),
          TextSpan(
              text: '   $detail',
              style: const TextStyle(fontSize: 12.5, color: _cText)),
        ])),
      );
    }

    final redUs = us?['status'] == 'rojo';
    final redEu = eu?['status'] == 'rojo';
    final children = <Widget>[
      chip(
          'EE. UU.',
          us,
          'SPY ${p(us?['spy_ema20'])} s/EMA20 · ${p(us?['spy_ema50'])} s/EMA50 · '
              'VIX ${_d(us?['vix']) == null ? '–' : _num(_d(us?['vix'])!, 1)} · '
              '${n0(us?['breadth'])} % del S&P > EMA50'),
      chip(
          'Europa',
          eu,
          'IBEX ${p(eu?['ibex_ema20'])} · DAX ${p(eu?['dax_ema20'])} s/EMA20 · '
              '${n0(eu?['breadth'])} % > EMA50'),
    ];
    if (_mode == 'long' && (redUs || redEu)) {
      final where = [if (redUs) 'EE. UU.', if (redEu) 'Europa'].join(' y ');
      children.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, color: _kRed, size: 20),
          const SizedBox(width: 6),
          Text(
              _showRed
                  ? 'Mercado en rojo en $where: se muestran igualmente (puntuación ×0,5)'
                  : 'Mercado en rojo en $where: largos ocultos',
              style: const TextStyle(color: _kRed, fontSize: 13)),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _cText),
            onPressed: () => setState(() => _showRed = !_showRed),
            child: Text(_showRed ? 'Ocultar' : 'Mostrar igualmente'),
          ),
        ],
      ));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }

  Widget _results(List<Map<String, dynamic>> vis) {
    final keys = _cols[_mode]!.where(_kFieldMap.containsKey).toList();
    final widths = _colW[_mode]!;
    final gcols = [
      for (final k in keys)
        k == 'ticker'
            ? _tickerCol(widths[k])
            : _GridCol.forField(_kFieldMap[k]!, width: widths[k])
    ];
    final onlyFav = _onlyFav[_mode]!;
    final nFav = _favs[_mode]!.length;
    final sk = _sortKey[_mode]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _regimeBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
          child: Row(
            children: [
              Text('${vis.length} empresas',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  onlyFav
                      ? 'Solo favoritos (los filtros no se aplican)'
                      : 'Orden: ${_kFieldMap[sk]?.label ?? sk} '
                          '${_sortAsc[_mode]! ? '↑' : '↓'}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: _cMuted),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() => _onlyFav[_mode] = !onlyFav);
                  _save();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: onlyFav ? _kStar.withAlpha(30) : Colors.transparent,
                    border: Border.all(color: onlyFav ? _kStar : _cBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(onlyFav ? Icons.star : Icons.star_border,
                          size: 18, color: _kStar),
                      const SizedBox(width: 6),
                      Text('Favoritos ($nFav)',
                          style: TextStyle(
                              color: onlyFav ? _kStar : _cText,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: _cText),
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('Enviar'),
                onPressed: nFav == 0 ? null : _shareFavs,
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: _cText),
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Copiar'),
                onPressed: vis.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(
                            text: vis.map((r) => r['ticker']).join(',')));
                        _toast('${vis.length} tickers copiados');
                      },
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: _cText),
                icon: const Icon(Icons.view_column_outlined, size: 18),
                label: const Text('Columnas'),
                onPressed: _pickColumns,
              ),
            ],
          ),
        ),
        Expanded(
          child: vis.isEmpty
              ? Center(
                  child: Text(
                      onlyFav
                          ? 'Aún no tienes favoritos en ${_mode == 'long' ? 'largos' : 'cortos'}. '
                              'Márcalos con la estrella ☆ junto al ticker.'
                          : 'Ninguna empresa cumple los filtros.',
                      style: const TextStyle(color: _cMuted)))
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _Grid(
                    cols: gcols,
                    rows: vis,
                    sortKey: sk,
                    sortAsc: _sortAsc[_mode]!,
                    selected: _selected,
                    accent: _accent,
                    onSort: (k) {
                      setState(() {
                        if (_sortKey[_mode] == k) {
                          _sortAsc[_mode] = !_sortAsc[_mode]!;
                        } else {
                          _sortKey[_mode] = k;
                          final kind = _kFieldMap[k]?.kind;
                          _sortAsc[_mode] =
                              kind == _Kind.text || kind == _Kind.choice;
                        }
                      });
                      _save();
                    },
                    onTap: _openDetail,
                    onMove: _moveCol,
                    onResize: (k, w) =>
                        setState(() => widths[k] = w.clamp(48.0, 600.0)),
                    onResizeEnd: _save,
                    onResetWidth: (k) {
                      setState(() => widths.remove(k));
                      _save();
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _sectorsView() {
    List<Map<String, dynamic>> mk(Map<String, dynamic> src, bool keyIsName) {
      final out = <Map<String, dynamic>>[];
      src.forEach((k, v) {
        final m = Map<String, dynamic>.from(v as Map);
        m['_id'] = k;
        m['_name'] = keyIsName ? k : (m['name'] ?? k).toString();
        m['_etf'] = (m['etf'] ?? k).toString();
        out.add(m);
      });
      out.sort((a, b) => _cmp(a['r_3m'], b['r_3m'], false));
      return out;
    }

    final secs = mk(_sectors, true);
    final secsEu =
        mk(_sectorsEu, true).where((m) => (m['count'] ?? 0) != 0).toList();
    final inds = mk(_industries, false);
    final bench = mk(_bench, false);

    _GridCol pctCol(String k, String l) => _GridCol(
          key: k,
          label: l,
          width: 84,
          right: true,
          text: (r) {
            final d = _d(r[k]);
            if (d == null) return '–';
            return '${d > 0 ? '+' : ''}${_num(d, 1)}';
          },
          color: (r) {
            final d = _d(r[k]);
            if (d == null || d == 0) return null;
            return d > 0 ? _kGreen : _kRed;
          },
        );
    _GridCol numCol(String k, String l, {int dec = 1, double w = 80}) =>
        _GridCol(
          key: k,
          label: l,
          width: w,
          right: true,
          text: (r) {
            final d = _d(r[k]);
            return d == null ? '–' : _num(d, dec);
          },
        );
    final base = <_GridCol>[
      _GridCol(
          key: '_name',
          label: 'Nombre',
          width: 190,
          bold: true,
          text: (r) => r['_name'].toString()),
      _GridCol(
          key: '_etf',
          label: 'ETF',
          width: 60,
          text: (r) => r['_etf'].toString()),
      pctCol('r_1w', '1 semana %'),
      pctCol('r_1m', '1 mes %'),
      pctCol('r_3m', '3 meses %'),
      pctCol('r_6m', '6 meses %'),
      pctCol('r_ytd', 'En el año %'),
      pctCol('d_ema50', '% sobre EMA50'),
      pctCol('d_ema200', '% sobre EMA200'),
      numCol('rsi_d', 'RSI diario', dec: 0, w: 70),
      _GridCol(
        key: 'trend',
        label: 'Tendencia',
        width: 84,
        text: (r) => (r['trend'] ?? '–').toString(),
        color: (r) => r['trend'] == 'alcista'
            ? _kGreen
            : (r['trend'] == 'bajista' ? _kRed : null),
      ),
    ];
    final pe = <_GridCol>[
      numCol('count', 'Empresas', dec: 0),
      numCol('pe_agg', 'PER agregado'),
      numCol('pe_med', 'PER mediano'),
      numCol('fpe_agg', 'PER fwd agregado'),
      numCol('etf_pe', 'PER del ETF'),
    ];
    const h = TextStyle(fontSize: 19, fontWeight: FontWeight.w600);
    const sub = TextStyle(fontSize: 13, color: _cMuted);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        const Text('Índices', style: h),
        const SizedBox(height: 10),
        _Grid(cols: base, rows: bench, shrink: true, accent: _accent),
        const SizedBox(height: 30),
        const Text('Sectores EE. UU.', style: h),
        const SizedBox(height: 4),
        const Text('Toca un sector para filtrar el screener por él.',
            style: sub),
        const SizedBox(height: 10),
        _Grid(
          cols: [...base, ...pe],
          rows: secs,
          shrink: true,
          accent: _accent,
          onTap: (m) => _applyGroupFilter('sector', m['_id'].toString(),
              markets: {'EE. UU.'}),
        ),
        const SizedBox(height: 30),
        const Text('Sectores Europa (IBEX 35 + DAX 40)', style: h),
        const SizedBox(height: 4),
        const Text(
            'Referencia: ETFs iShares STOXX Europe 600 de cada sector. '
            'Toca un sector para filtrar los valores españoles y alemanes.',
            style: sub),
        const SizedBox(height: 10),
        _Grid(
          cols: [...base, ...pe],
          rows: secsEu,
          shrink: true,
          accent: _accent,
          onTap: (m) => _applyGroupFilter('sector', m['_id'].toString(),
              markets: {'España', 'Alemania'}),
        ),
        const SizedBox(height: 30),
        const Text('Industrias EE. UU.', style: h),
        const SizedBox(height: 4),
        const Text(
            'PER agregado = suma de capitalizaciones ÷ suma de beneficios de las '
            'empresas del universo (solo PER positivos). Toca para filtrar.',
            style: sub),
        const SizedBox(height: 10),
        _Grid(
          cols: [...base, ...pe],
          rows: inds,
          shrink: true,
          accent: _accent,
          onTap: (m) => _applyGroupFilter('ind_name', m['_name'].toString()),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- botón discontinuo

class _DashedButton extends StatelessWidget {
  const _DashedButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: CustomPaint(
        painter: _DashedPainter(_cMuted.withAlpha(150)),
        child: SizedBox(
          height: 46,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, size: 18, color: _cText),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 14.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rect = (Offset.zero & size).deflate(0.5);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    for (final m in path.computeMetrics()) {
      double dist = 0;
      while (dist < m.length) {
        canvas.drawPath(
            m.extractPath(dist, math.min(dist + 5, m.length)), paint);
        dist += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ----------------------------------------------------------------- tabla

class _GridCol {
  const _GridCol({
    required this.key,
    required this.label,
    required this.width,
    required this.text,
    this.color,
    this.leading,
    this.trailing,
    this.right = false,
    this.bold = false,
  });

  final Widget Function(Map<String, dynamic> r)? leading;
  final Widget Function(Map<String, dynamic> r)? trailing;
  final String key;
  final String label;
  final double width;
  final String Function(Map<String, dynamic> r) text;
  final Color? Function(Map<String, dynamic> r)? color;
  final bool right;
  final bool bold;

  static _GridCol forField(_Field f, {double? width}) => _GridCol(
        key: f.key,
        label: f.header,
        width: width ?? f.width,
        right: f.kind == _Kind.number,
        bold: f.key == 'ticker' || f.key == 'hb_rr' || f.key == 'hs_rr',
        text: _kMoneyKeys.contains(f.key)
            ? (r) => r[f.key] == null ? '–' : '${_fmt(f, r[f.key])} ${_cur(r)}'
            : (r) => _fmt(f, r[f.key]),
        color: (r) => _colorFor(f, r[f.key]),
        leading: f.key == 'ticker'
            ? (r) => r['has_logo'] == true
                ? _Logo(ticker: r['ticker'].toString(), size: 18)
                : const SizedBox(width: 18, height: 18)
            : null,
      );
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.cols,
    required this.rows,
    required this.accent,
    this.sortKey,
    this.sortAsc = false,
    this.onSort,
    this.onTap,
    this.selected,
    this.shrink = false,
    this.onMove,
    this.onResize,
    this.onResizeEnd,
    this.onResetWidth,
  });

  final void Function(String from, String to)? onMove;
  final void Function(String key, double width)? onResize;
  final VoidCallback? onResizeEnd;
  final void Function(String key)? onResetWidth;
  final List<_GridCol> cols;
  final List<Map<String, dynamic>> rows;
  final Color accent;
  final String? sortKey;
  final bool sortAsc;
  final void Function(String key)? onSort;
  final void Function(Map<String, dynamic> r)? onTap;
  final String? selected;
  final bool shrink;

  static const double _rowH = 32;
  static const double _hdrH = 48;

  Widget _headerLabel(_GridCol c, {bool dragging = false}) {
    return SizedBox(
      width: c.width,
      height: _hdrH,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisAlignment:
              c.right ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                c.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: c.right ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: (sortKey == c.key || dragging) ? _cText : _cMuted),
              ),
            ),
            if (sortKey == c.key && !dragging)
              Icon(sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12, color: _cText),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(_GridCol c) {
    final cell = _headerCellInner(c);
    if (onResize == null) return cell;
    final handle = MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onResize!(c.key, c.width + d.delta.dx),
        onHorizontalDragEnd: (_) => onResizeEnd?.call(),
        onDoubleTap: () => onResetWidth?.call(c.key),
        child: Center(
          child: Container(width: 1.5, height: 22, color: _cBorder),
        ),
      ),
    );
    return SizedBox(
      width: c.width,
      height: _hdrH,
      child: Stack(
        children: [
          Positioned.fill(right: 8, child: cell),
          Positioned(right: 0, top: 0, bottom: 0, width: 14, child: handle),
        ],
      ),
    );
  }

  Widget _headerCellInner(_GridCol c) {
    final tap = InkWell(
      onTap: onSort == null ? null : () => onSort!(c.key),
      child: _headerLabel(c),
    );
    if (onMove == null) return tap;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != c.key,
      onAcceptWithDetails: (d) => onMove!(d.data, c.key),
      builder: (ctx, cand, rej) => Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
                color: cand.isNotEmpty ? accent : Colors.transparent, width: 2),
          ),
        ),
        child: LongPressDraggable<String>(
          data: c.key,
          delay: const Duration(milliseconds: 250),
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: _cSurface,
                border: Border.all(color: accent),
                borderRadius: BorderRadius.circular(6),
              ),
              child: _headerLabel(c, dragging: true),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: _headerLabel(c)),
          child: tap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = cols.fold<double>(0, (a, c) => a + c.width) + 8;

    final header = Container(
      height: _hdrH,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _cBorder)),
      ),
      child: Row(
        children: [
          for (final c in cols) _headerCell(c),
        ],
      ),
    );

    return _layout(header, total);
  }

  Widget _cellContent(_GridCol c, Map<String, dynamic> r) {
    final txt = Text(
      c.text(r),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: c.right ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        fontSize: 13,
        color: c.color?.call(r) ?? _cText,
        fontWeight: c.bold ? FontWeight.w700 : FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    if (c.leading == null && c.trailing == null) return txt;
    return Row(
      children: [
        if (c.leading != null) ...[c.leading!(r), const SizedBox(width: 8)],
        Expanded(child: txt),
        if (c.trailing != null) c.trailing!(r),
      ],
    );
  }

  Widget _rowAt(int i) {
    final r = rows[i];
    final sel = selected != null && r['ticker']?.toString() == selected;
    return InkWell(
      onTap: onTap == null ? null : () => onTap!(r),
      hoverColor: Colors.white.withAlpha(8),
      child: Container(
        height: _rowH,
        decoration: BoxDecoration(
          color: sel ? accent.withAlpha(26) : null,
          border: const Border(bottom: BorderSide(color: _cDivider)),
        ),
        child: Row(
          children: [
            for (final c in cols)
              SizedBox(
                width: c.width,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _cellContent(c, r),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _layout(Widget header, double total) {
    Widget rowAt(int i) => _rowAt(i);
    return LayoutBuilder(builder: (context, cons) {
      final avail = cons.hasBoundedWidth ? cons.maxWidth : total;
      final w = math.max(total, avail);
      Widget body;
      if (shrink) {
        body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            for (var i = 0; i < rows.length; i++) rowAt(i),
          ],
        );
      } else {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemExtent: _rowH,
                itemBuilder: (ctx, i) => rowAt(i),
              ),
            ),
          ],
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: w, child: body),
      );
    });
  }
}

// ----------------------------------------------------------------- selector de criterio

class _FieldPicker extends StatefulWidget {
  const _FieldPicker({required this.accent});
  final Color accent;

  @override
  State<_FieldPicker> createState() => _FieldPickerState();
}

class _FieldPickerState extends State<_FieldPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = _kFields
        .where((f) =>
            f.kind != _Kind.text &&
            f.kind != _Kind.date &&
            f.key != 'score' &&
            (_q.isEmpty ||
                f.label.toLowerCase().contains(_q) ||
                f.cat.toLowerCase().contains(_q)))
        .toList();
    final items = <Widget>[];
    String? last;
    for (final f in list) {
      if (f.cat != last) {
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Text(f.cat,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: widget.accent)),
        ));
        last = f.cat;
      }
      items.add(ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(f.label, style: const TextStyle(fontSize: 14)),
        onTap: () => Navigator.pop(context, f),
      ));
    }
    final size = MediaQuery.of(context).size;
    return AlertDialog(
      backgroundColor: _cPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _cBorder),
      ),
      title: const Text('Añadir filtro'),
      contentPadding: const EdgeInsets.only(top: 12),
      content: SizedBox(
        width: math.min(480, size.width - 48),
        height: math.min(580, size.height - 220),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Buscar criterio (RSI, EMA, PER, resultados…)',
                  prefixIcon: Icon(Icons.search, color: _cMuted),
                ),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: ListView(children: items)),
          ],
        ),
      ),
      actions: [
        TextButton(
            style: TextButton.styleFrom(foregroundColor: _cMuted),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
      ],
    );
  }
}

// ----------------------------------------------------------------- editor de filtro

class _FilterEditor extends StatefulWidget {
  const _FilterEditor({
    required this.field,
    required this.initial,
    required this.rows,
    required this.accent,
  });

  final _Field field;
  final _Filter? initial;
  final List<Map<String, dynamic>> rows;
  final Color accent;

  @override
  State<_FilterEditor> createState() => _FilterEditorState();
}

class _FilterEditorState extends State<_FilterEditor> {
  late final TextEditingController _min =
      TextEditingController(text: _plain(widget.initial?.min));
  late final TextEditingController _max =
      TextEditingController(text: _plain(widget.initial?.max));
  late bool _b = widget.initial?.boolVal ?? true;
  late final Set<String> _vals = {...?widget.initial?.values};
  String? _err;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  String? _help() {
    final k = widget.field.key;
    if (_kHelp.containsKey(k)) return _kHelp[k];
    if (RegExp(r'^(xu|xd)\d+$').hasMatch(k) || k == 'gc' || k == 'dc') {
      return 'Sesiones desde el cruce (0 = hoy). Solo se miran las últimas 10 sesiones '
          '(20 en el cruce 50/200). Máximo 3 = el cruce ocurrió en las últimas 4 sesiones.';
    }
    if (RegExp(r'^(hb|hs)\d+$').hasMatch(k)) {
      return 'Sesiones desde la vela (0 = hoy). Máximo 3 = en las últimas 4 velas.';
    }
    if (k.startsWith('rs_')) {
      return 'Diferencia de rentabilidad en puntos: +5 = ha subido 5 puntos más que la referencia.';
    }
    if (k.startsWith('a_ema')) {
      return 'Distancia a la EMA medida en ATRs: compara mejor entre valores con distinta volatilidad.';
    }
    return null;
  }

  void _apply() {
    final f = widget.field;
    switch (f.kind) {
      case _Kind.number:
        final mn = _parse(_min.text);
        final mx = _parse(_max.text);
        if (mn == null && mx == null) {
          setState(() => _err = 'Indica un mínimo, un máximo o ambos.');
          return;
        }
        if (mn != null && mx != null && mn > mx) {
          setState(() => _err = 'El mínimo es mayor que el máximo.');
          return;
        }
        Navigator.pop(context, _Filter(f.key, min: mn, max: mx));
        return;
      case _Kind.boolean:
        Navigator.pop(context, _Filter(f.key, boolVal: _b));
        return;
      case _Kind.choice:
      case _Kind.text:
        if (_vals.isEmpty) {
          setState(() => _err = 'Marca al menos un valor.');
          return;
        }
        Navigator.pop(context, _Filter(f.key, values: Set<String>.of(_vals)));
        return;
      case _Kind.date:
        Navigator.pop(context);
        return;
    }
  }

  Widget _numberBody() {
    final vals = widget.rows
        .map((r) => _d(r[widget.field.key]))
        .whereType<double>()
        .toList()
      ..sort();
    final dec = widget.field.dec;
    final help = _help();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (vals.isNotEmpty)
          Text(
            'En los datos: de ${_num(vals.first, dec)} a ${_num(vals.last, dec)} · '
            'mediana ${_num(vals[vals.length ~/ 2], dec)} · '
            '${vals.length} empresas con dato',
            style: const TextStyle(fontSize: 12.5, color: _cMuted),
          ),
        if (help != null) ...[
          const SizedBox(height: 8),
          Text(help, style: const TextStyle(fontSize: 13)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Mínimo',
                      style: TextStyle(fontSize: 13, color: _cMuted)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _min,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Máximo',
                      style: TextStyle(fontSize: 13, color: _cMuted)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _max,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    onSubmitted: (_) => _apply(),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Deja vacío el lado que no quieras limitar.',
            style: TextStyle(fontSize: 12, color: _cMuted)),
      ],
    );
  }

  Widget _boolBody() {
    Widget opt(bool v, String label) {
      final sel = _b == v;
      return InkWell(
        onTap: () => setState(() => _b = v),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 90,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? widget.accent.withAlpha(30) : Colors.transparent,
            border: Border.all(color: sel ? widget.accent : _cBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: sel ? widget.accent : _cText)),
        ),
      );
    }

    return Row(children: [
      opt(true, 'Sí'),
      const SizedBox(width: 10),
      opt(false, 'No')
    ]);
  }

  Widget _choiceBody() {
    final all = widget.rows
        .map((r) => r[widget.field.key])
        .where((v) => v != null)
        .map((v) => v.toString())
        .toSet()
        .toList()
      ..sort();
    return SizedBox(
      height: math.min(380, MediaQuery.of(context).size.height - 300),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final v in all)
            CheckboxListTile(
              dense: true,
              activeColor: widget.accent,
              value: _vals.contains(v),
              title: Text(v),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (on) => setState(() {
                if (on == true) {
                  _vals.add(v);
                } else {
                  _vals.remove(v);
                }
              }),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    Widget body;
    switch (f.kind) {
      case _Kind.number:
        body = _numberBody();
        break;
      case _Kind.boolean:
        body = _boolBody();
        break;
      case _Kind.choice:
      case _Kind.text:
        body = _choiceBody();
        break;
      case _Kind.date:
        body = const SizedBox.shrink();
        break;
    }
    final size = MediaQuery.of(context).size;
    return AlertDialog(
      backgroundColor: _cPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _cBorder),
      ),
      title: Text(f.label, style: const TextStyle(fontSize: 18)),
      content: SizedBox(
        width: math.min(460, size.width - 48),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              body,
              if (_err != null) ...[
                const SizedBox(height: 10),
                Text(_err!, style: const TextStyle(color: _kRed)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: const Text('Quitar', style: TextStyle(color: _kRed)),
          ),
        TextButton(
            style: TextButton.styleFrom(foregroundColor: _cMuted),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            style:
                _fillStyle(widget.accent == _kGreen ? _kGreenFill : _kRedFill),
            onPressed: _apply,
            child: const Text('Aplicar')),
      ],
    );
  }
}

// ----------------------------------------------------------------- selector de columnas

class _ColumnPicker extends StatefulWidget {
  const _ColumnPicker({
    required this.current,
    required this.defaults,
    required this.accent,
  });

  final List<String> current;
  final List<String> defaults;
  final Color accent;

  @override
  State<_ColumnPicker> createState() => _ColumnPickerState();
}

class _ColumnPickerState extends State<_ColumnPicker> {
  late List<String> _sel = List<String>.of(widget.current);
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final avail = _kFields
        .where((f) =>
            !_sel.contains(f.key) &&
            (_q.isEmpty ||
                f.label.toLowerCase().contains(_q) ||
                f.cat.toLowerCase().contains(_q)))
        .toList();
    final items = <Widget>[];
    String? last;
    for (final f in avail) {
      if (f.cat != last) {
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Text(f.cat,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: widget.accent)),
        ));
        last = f.cat;
      }
      items.add(ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(Icons.add_circle_outline, size: 20, color: widget.accent),
        title: Text(f.label, style: const TextStyle(fontSize: 14)),
        onTap: () => setState(() => _sel.add(f.key)),
      ));
    }
    final size = MediaQuery.of(context).size;
    const sub = TextStyle(fontSize: 12.5, color: _cMuted);
    return AlertDialog(
      backgroundColor: _cPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _cBorder),
      ),
      title: Text('Columnas (${_sel.length})'),
      contentPadding: const EdgeInsets.only(top: 8),
      content: SizedBox(
        width: math.min(520, size.width - 48),
        height: math.min(640, size.height - 200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(
                  'Columnas visibles, en orden. Arrastra desde ⠿ para moverlas.',
                  style: sub),
            ),
            Expanded(
              flex: 5,
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: _sel.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    var to = newIndex;
                    if (to > oldIndex) to -= 1;
                    final k = _sel.removeAt(oldIndex);
                    _sel.insert(to, k);
                  });
                },
                itemBuilder: (ctx, i) {
                  final k = _sel[i];
                  return Material(
                    key: ValueKey(k),
                    color: _cPanel,
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 8, right: 8),
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.drag_indicator, color: _cMuted),
                        ),
                      ),
                      title: Text(_kFieldMap[k]?.label ?? k,
                          style: const TextStyle(fontSize: 14)),
                      trailing: IconButton(
                        tooltip: 'Quitar',
                        icon: const Icon(Icons.remove_circle_outline,
                            size: 20, color: _kRed),
                        onPressed: _sel.length <= 1
                            ? null
                            : () => setState(() => _sel.removeAt(i)),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, color: _cBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Añadir columna (buscar)',
                  prefixIcon: Icon(Icons.search, color: _cMuted),
                ),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            Expanded(flex: 4, child: ListView(children: items)),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: _cMuted),
          onPressed: () =>
              setState(() => _sel = List<String>.of(widget.defaults)),
          child: const Text('Restablecer'),
        ),
        TextButton(
            style: TextButton.styleFrom(foregroundColor: _cMuted),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          style: _fillStyle(widget.accent == _kGreen ? _kGreenFill : _kRedFill),
          onPressed: _sel.isEmpty ? null : () => Navigator.pop(context, _sel),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- enviar favoritos

class _ShareDialog extends StatelessWidget {
  const _ShareDialog({
    required this.title,
    required this.count,
    required this.text,
    required this.accent,
  });

  final String title;
  final int count;
  final String text;
  final Color accent;

  Future<void> _open(Uri u) async {
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final mail = Uri.parse('mailto:?subject=${Uri.encodeComponent(title)}'
        '&body=${Uri.encodeComponent(text)}');
    final wa = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    return AlertDialog(
      backgroundColor: _cPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _cBorder),
      ),
      title: Row(
        children: [
          const Icon(Icons.star, color: _kStar),
          const SizedBox(width: 10),
          Expanded(child: Text('Enviar favoritos ($count)')),
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close, color: _cMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: math.min(620, size.width - 48),
        height: math.min(420, size.height - 260),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cSurface,
            border: Border.all(color: _cBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SingleChildScrollView(
            child: SelectableText(text,
                style: const TextStyle(fontSize: 13.5, height: 1.45)),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'clear'),
          child: const Text('Vaciar lista', style: TextStyle(color: _kRed)),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: _cText),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            Navigator.pop(context, 'copied');
          },
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('Copiar'),
        ),
        FilledButton.icon(
          style: _fillStyle(const Color(0xFF2E5FA8)),
          onPressed: () => _open(mail),
          icon: const Icon(Icons.mail_outline, size: 18),
          label: const Text('Correo'),
        ),
        FilledButton.icon(
          style: _fillStyle(const Color(0xFF1E9E52)),
          onPressed: () => _open(wa),
          icon: const Icon(Icons.chat_outlined, size: 18),
          label: const Text('WhatsApp'),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- pedir texto

class _TextAsk extends StatefulWidget {
  const _TextAsk({required this.title, required this.label});
  final String title;
  final String label;

  @override
  State<_TextAsk> createState() => _TextAskState();
}

class _TextAskState extends State<_TextAsk> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _cPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _cBorder),
      ),
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _c,
          autofocus: true,
          decoration: InputDecoration(hintText: widget.label),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(
            style: TextButton.styleFrom(foregroundColor: _cMuted),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            style: _fillStyle(_kGreenFill),
            onPressed: () => Navigator.pop(context, _c.text),
            child: const Text('Guardar')),
      ],
    );
  }
}

// ----------------------------------------------------------------- ficha de empresa

class _Detail extends StatefulWidget {
  const _Detail({
    super.key,
    required this.onClose,
    required this.isFav,
    required this.onToggleFav,
    required this.row,
    required this.mode,
    required this.risk,
    required this.maxPos,
    required this.fx,
    required this.regime,
    required this.accent,
    required this.accentFill,
  });

  final Map<String, dynamic> row;
  final String mode;
  final double risk;
  final double maxPos;
  final double? fx;
  final String regime;
  final Color accent;
  final Color accentFill;
  final VoidCallback onClose;
  final bool isFav;
  final VoidCallback onToggleFav;

  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  late final TextEditingController _stop;
  late final TextEditingController _entry;
  late final String _stopSrc;

  bool get _long => widget.mode == 'long';
  double get _px => _d(widget.row['price']) ?? 0;
  double get _atrAbs => (_d(widget.row['atr_pct']) ?? 2) * _px / 100;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    final pe = _d(r['p_entry']);
    final ps = _d(r['p_stop']);
    double e;
    double s;
    if (pe != null && ps != null) {
      e = pe;
      s = ps;
      final pat = _long ? _d(r['hb_stop']) : _d(r['hs_stop']);
      final usesPat = pat != null && (pat - ps).abs() < 1e-9;
      _stopSrc = _long
          ? 'Entrada sobre el máx. de la última sesión · stop en '
              '${usesPat ? 'el mínimo del martillo' : 'su mínimo'}'
          : 'Entrada bajo el mín. de la última sesión · stop en '
              '${usesPat ? 'el máximo del martillo' : 'su máximo'}';
    } else {
      e = _px;
      s = _long ? _px - 1.5 * _atrAbs : _px + 1.5 * _atrAbs;
      _stopSrc = 'Entrada al precio · stop a 1,5 ATR';
    }
    _entry =
        TextEditingController(text: e.toStringAsFixed(2).replaceAll('.', ','));
    _stop =
        TextEditingController(text: s.toStringAsFixed(2).replaceAll('.', ','));
  }

  @override
  void dispose() {
    _stop.dispose();
    _entry.dispose();
    super.dispose();
  }

  Future<void> _openChart() =>
      _openTradingView((widget.row['ticker'] ?? '').toString());

  Widget _tile(String k, String v, {Color? color}) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _cSurface,
        border: Border.all(color: _cBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(k, style: const TextStyle(fontSize: 13, color: _cMuted)),
          const SizedBox(height: 2),
          Text(v,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  color: color ?? _cText)),
        ],
      ),
    );
  }

  Widget _chip(String k, String v, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: _cBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(TextSpan(children: [
        TextSpan(
            text: '$k  ', style: const TextStyle(color: _cMuted, fontSize: 13)),
        TextSpan(
            text: v,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: color ?? _cText)),
      ])),
    );
  }

  Widget _kv(String k, String v, {Color? color}) {
    return Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _cSurface,
        border: Border.all(color: _cBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 11.5, color: _cMuted)),
          const SizedBox(height: 3),
          Text(v,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: color ?? _cText)),
        ],
      ),
    );
  }

  Widget _rangeLine(Map<String, dynamic> r) {
    final cs = _cur(r);
    final px = _d(r['price']);
    final hi = _d(r['high52']);
    final lo = _d(r['low52']);
    final dh = _d(r['d_high52']);
    final dl = _d(r['d_low52']);
    String pc(double? d) =>
        d == null ? '' : ' (${d > 0 ? '+' : ''}${_num(d, 1)} %)';
    const k = TextStyle(fontSize: 13.5, color: _cMuted);
    const v =
        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _cText);
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'Precio ', style: k),
        TextSpan(text: px == null ? '–' : '${_num(px, 2)} $cs', style: v),
        const TextSpan(text: '   ·   Máx. 52 sem. ', style: k),
        TextSpan(text: hi == null ? '–' : '${_num(hi, 2)} $cs', style: v),
        TextSpan(
            text: pc(dh),
            style: TextStyle(
                fontSize: 13.5, color: (dh ?? 0) < 0 ? _kRed : _kGreen)),
        const TextSpan(text: '   ·   Mín. 52 sem. ', style: k),
        TextSpan(text: lo == null ? '–' : '${_num(lo, 2)} $cs', style: v),
        TextSpan(
            text: pc(dl),
            style: TextStyle(
                fontSize: 13.5, color: (dl ?? 0) > 0 ? _kGreen : _kRed)),
      ]),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _header() {
    final r = widget.row;
    final ticker = (r['ticker'] ?? '').toString();
    final idx = [
      if (r['in_ndx'] == true) 'Nasdaq-100',
      if (r['in_dow'] == true) 'Dow Jones',
      if (r['in_spx'] == true) 'S&P 500',
      if (r['in_ibex'] == true) 'IBEX 35',
      if (r['in_dax'] == true) 'DAX 40',
    ].join(' · ');
    final tickerBox = Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.accent.withAlpha(28),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(ticker.length > 4 ? ticker.substring(0, 4) : ticker,
          style: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 15, color: widget.accent)),
    );
    final Widget logo = r['has_logo'] == true
        ? _Logo(ticker: ticker, size: 58, fallback: tickerBox)
        : tickerBox;
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: ticker,
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            TextSpan(
                text: '  ·  ${r['name'] ?? ''}',
                style: const TextStyle(fontSize: 18, color: _cMuted)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '${r['ind_name'] ?? r['sector'] ?? ''}'
          '${idx.isEmpty ? '' : '   |   $idx'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, color: _cMuted),
        ),
        const SizedBox(height: 6),
        _rangeLine(r),
      ],
    );
    final entry = Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: widget.accent.withAlpha(20),
        border: Border.all(color: widget.accent.withAlpha(170)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_long ? Icons.trending_up : Icons.trending_down,
              color: widget.accent, size: 26),
          const SizedBox(width: 14),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_long ? 'Entrada en largo' : 'Entrada en corto',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: widget.accent)),
                const SizedBox(height: 2),
                Text(_stopSrc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: _cMuted)),
              ],
            ),
          ),
        ],
      ),
    );
    Widget field(String label, TextEditingController c) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 15, color: _cMuted)),
            const SizedBox(width: 10),
            SizedBox(
              width: 112,
              child: TextField(
                controller: c,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 17),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        );
    final cs = _cur(r);
    final stop = Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(
        color: _cSurface,
        border: Border.all(color: _cBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          field('Entrada ($cs)', _entry),
          const SizedBox(width: 16),
          field('Stop', _stop),
        ],
      ),
    );
    final closeBtn = IconButton(
      tooltip: 'Cerrar',
      icon: const Icon(Icons.close, color: _cText),
      onPressed: widget.onClose,
    );
    final close = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: widget.isFav
              ? 'Quitar de favoritos'
              : 'Añadir a favoritos de ${_long ? 'largos' : 'cortos'}',
          icon: Icon(widget.isFav ? Icons.star : Icons.star_border,
              color: widget.isFav ? _kStar : _cText),
          onPressed: widget.onToggleFav,
        ),
        closeBtn,
      ],
    );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 1050) {
        return Row(
          children: [
            logo,
            const SizedBox(width: 16),
            Expanded(child: name),
            const SizedBox(width: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 300, maxWidth: 400),
              child: entry,
            ),
            const SizedBox(width: 16),
            stop,
            const SizedBox(width: 8),
            close,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              logo,
              const SizedBox(width: 16),
              Expanded(child: name),
              close,
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 300, maxWidth: 400),
                child: entry,
              ),
              stop,
            ],
          ),
        ],
      );
    });
  }

  Widget _calc() {
    final r = widget.row;
    final px = _parse(_entry.text) ?? 0;
    final stop = _parse(_stop.text);
    String? err;
    if (stop == null || px <= 0) {
      err = 'Indica una entrada y un stop válidos.';
    } else if ((_long ? px - stop : stop - px) <= 0) {
      err = _long
          ? 'En largo el stop debe estar por debajo de la entrada.'
          : 'En corto el stop debe estar por encima de la entrada.';
    }
    final chartBtn = SizedBox(
      width: 200,
      height: 68,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: _cText,
          backgroundColor: widget.accentFill.withAlpha(60),
          side: BorderSide(color: widget.accent.withAlpha(170)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: _openChart,
        icon: const Icon(Icons.candlestick_chart_outlined, size: 22),
        label: const Text('Ver gráfico',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
    if (err != null) {
      return Row(
        children: [
          Expanded(child: Text(err, style: const TextStyle(color: _kRed))),
          const SizedBox(width: 16),
          chartBtn,
        ],
      );
    }
    final dist = _long ? px - stop! : stop! - px;
    final eur = r['currency'] == 'EUR';
    final fx = (eur && widget.fx != null && widget.fx! > 0) ? widget.fx! : 1.0;
    final cs = _cur(r);
    final risk = widget.risk / fx;
    final maxPos = widget.maxPos / fx;
    final byRisk = risk / dist;
    final byCap = maxPos / px;
    final shares = (math.min(byRisk, byCap) / 5).floor() * 5;
    final capital = shares * px;
    final realRisk = shares * dist;
    final chips = <Widget>[];
    final tgt = _long ? _d(r['tgt_l']) : _d(r['tgt_s']);
    if (tgt != null && (_long ? tgt > px : tgt < px)) {
      final run = (tgt - px).abs();
      final rr = run / dist;
      chips.add(_chip('Objetivo',
          '${_num(tgt, 2)} $cs (${_long ? '+' : '−'}${_num(run / px * 100, 1)} %)'));
      chips.add(_chip('B/R real', _num(rr, 2),
          color: rr < 1.2 ? _kRed : (rr >= 1.5 ? _kGreen : null)));
    } else {
      chips.add(_chip('Objetivo',
          _long ? 'sin resistencia: en máximos' : 'sin soporte: en mínimos'));
    }
    final satr = _atrAbs > 0 ? dist / _atrAbs : null;
    if (satr != null) {
      chips.add(_chip('Stop a', '${_num(satr, 2)} ATR',
          color: satr < 1 ? _kRed : (satr >= 1.5 ? _kGreen : null)));
    }
    final d20 = _d(r['d_ema20']);
    if (d20 != null && _px > 0) {
      final ema20 = _px / (1 + d20 / 100);
      if (_long && px < ema20) {
        chips.add(_chip('Atención', 'entrada bajo la EMA20 (${_num(ema20, 2)})',
            color: _kRed));
      }
      if (!_long && px > ema20) {
        chips.add(_chip(
            'Atención', 'entrada sobre la EMA20 (${_num(ema20, 2)})',
            color: _kRed));
      }
    }
    if (widget.regime != 'verde') {
      chips.add(_chip('Mercado', widget.regime == 'rojo' ? 'ROJO' : 'ÁMBAR',
          color: widget.regime == 'rojo' ? _kRed : _kAmber));
    }
    if (byCap < byRisk) chips.add(_chip('Limitado por', 'posición máxima'));
    final bd = r['earn_bd'];
    final de = r['days_to_earn'];
    if (bd != null) {
      chips.add(_chip('Resultados en', '$bd días hábiles',
          color: (bd is num && bd <= 15) ? _kRed : null));
    } else if (de != null) {
      chips.add(_chip('Resultados en', '$de días',
          color: (de is num && de <= 21) ? _kRed : null));
    }
    if (!_long) {
      final dy = _d(r['div_yield']) ?? 0;
      if (dy > 0) {
        chips.add(_chip(
            'Dividendo a pagar (año)', '${_num(capital * dy / 100, 0)} $cs'));
      }
      final dx = r['days_to_exdiv'];
      if (dx != null) chips.add(_chip('Ex-dividendo en', '$dx días'));
      final sf = _d(r['short_float']);
      if (sf != null) chips.add(_chip('Short % float', '${_num(sf, 1)} %'));
      final sp = _d(r['short_pub']);
      if (sp != null) {
        chips.add(_chip(
            'Cortos CNMV',
            sp == 0
                ? 'ninguno ≥ 0,5 %'
                : '${_num(sp, 2)} % · ${r['short_n']} fondos'));
      }
    }
    chips.add(_chip(
        'Riesgo y posición máx.',
        eur
            ? '${_num(risk, 0)} € · ${_num(maxPos, 0)} € (EUR/USD ${_num(fx, 4)})'
            : '\$${_num(widget.risk, 0)} · \$${_num(widget.maxPos, 0)}'));
    final tiles = [
      _tile('Acciones', '$shares'),
      _tile('Importe', '${_num(capital, 0)} $cs'),
      _tile('Riesgo real', '${_num(realRisk, 0)} $cs'),
      _tile('Distancia al stop',
          '${_num(dist / px * 100, 1)} %${_atrAbs > 0 ? ' · ${_num(dist / _atrAbs, 1)} ATR' : ''}'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= 900) {
            return Row(
              children: [
                for (final t in tiles) ...[
                  Expanded(child: t),
                  const SizedBox(width: 14),
                ],
                chartBtn,
              ],
            );
          }
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final t in tiles) SizedBox(width: 190, child: t),
              chartBtn,
            ],
          );
        }),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final sections = <Widget>[];
    for (final cat in _kCatOrder) {
      if (cat == _cId) continue;
      final tiles = <Widget>[];
      for (final f in _kFields.where((f) => f.cat == cat)) {
        final v = r[f.key];
        if (v == null) continue;
        final txt = _kMoneyKeys.contains(f.key)
            ? '${_fmt(f, v)} ${_cur(r)}'
            : _fmt(f, v);
        tiles.add(_kv(f.label, txt, color: _colorFor(f, v)));
      }
      if (tiles.isEmpty) continue;
      sections.add(Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Text(cat,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ));
      sections.add(Wrap(spacing: 8, runSpacing: 8, children: tiles));
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.42,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (ctx, sc) => Container(
        decoration: const BoxDecoration(
          color: _cPanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          border: Border(top: BorderSide(color: _cBorder)),
        ),
        child: ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(28, 10, 28, 32),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _cMuted.withAlpha(110),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _header(),
            const SizedBox(height: 18),
            _calc(),
            const SizedBox(height: 6),
            const Text('Desliza hacia arriba para ver todos los datos.',
                style: TextStyle(fontSize: 12, color: _cMuted)),
            ...sections,
          ],
        ),
      ),
    );
  }
}
