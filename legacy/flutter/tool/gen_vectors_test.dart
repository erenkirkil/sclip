// sclip v2 test-vektörü kahini (oracle).
//
// Çalıştırma (repo kökünden):
//   cd legacy/flutter && SCLIP_GEN_VECTORS=1 flutter test --no-pub tool/gen_vectors_test.dart
//
// SCLIP_GEN_VECTORS=1 yoksa test hiçbir şey yapmadan geçer (CI'da no-op).
//
// Ne üretir: spec/vectors/{detect,hash,svg_sanitize,search,history}.json.
// classify.json elle yazılır (Dart sınıflandırıcısı super_clipboard okuyucularına bağlı).
// Şema: spec/vectors/README.md.
//
// Sapma kuralı (tasarım §9): `deviation` etiketli vakalarda beklenti elle verilen YENİ
// kuraldır (source: manual). Dart çıktısı yeni beklentiye eşitse sapma uygulanmamış demektir:
// `WARN deviation not applied: <dosya>/<ad>` basılır. Etiketsiz vakalarda beklenti Dart
// çıktısıdır (source: oracle); bağımsız sözleşme hesabı (hash, url, svg) Dart'tan farklı çıkarsa
// etiket eksik demektir ve test ERROR ile düşer (dosya yazılmaz).
//
// history.json notları:
// - Etiketsiz vakalar HistoryProvider'ı sözleşme sınırlarıyla koşar (görsel 25 MiB, bütçe
//   `budgetBytes` ?? 150 MiB). Aynı vaka Flutter varsayılanlarıyla (görsel 5 MiB) farklı
//   çıkarsa etiketsiz olamaz → ERROR.
// - E20 / E25 vakaları iki kez koşar: eski yol (Flutter varsayılanı 5 MiB + eski servis
//   kapısı: `clear` → resetBaseline → sonraki ilk kopya temel çizgi olarak yutulur) WARN
//   karşılaştırması için; sözleşme yolu elle verilen beklentiyle tutarlılık kontrolü için.
// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sclip/models/clipboard_entry.dart';
import 'package:sclip/providers/history_provider.dart';
import 'package:sclip/services/search_text.dart';
import 'package:sclip/services/svg_sanitizer.dart';

typedef J = Map<String, Object?>;

const int _mib = 1024 * 1024;
const String _vectorsPath = '../../spec/vectors';

final List<String> _warnings = <String>[];
final List<String> _errors = <String>[];

void main() {
  test('generate spec/vectors (SCLIP_GEN_VECTORS=1)', () {
    if (Platform.environment['SCLIP_GEN_VECTORS'] != '1') return;
    if (!File('../../spec/behavior.md').existsSync()) {
      fail('spec/behavior.md bulunamadı; legacy/flutter içinden çalıştırın');
    }
    final outputs = <String, Object>{
      'detect.json': _detect(),
      'hash.json': _hash(),
      'svg_sanitize.json': _svg(),
      'search.json': _search(),
      'history.json': _history(),
    };
    for (final w in _warnings) {
      print(w);
    }
    if (_errors.isNotEmpty) {
      for (final e in _errors) {
        print('ERROR $e');
      }
      fail('${_errors.length} hata; dosyalar yazılmadı');
    }
    const encoder = JsonEncoder.withIndent('  ');
    outputs.forEach((file, data) {
      File('$_vectorsPath/$file')
          .writeAsStringSync('${encoder.convert(data)}\n');
      final count = data is List
          ? data.length
          : (data as J).values.fold<int>(0, (s, v) => s + (v! as List).length);
      print('wrote spec/vectors/$file ($count cases)');
    });
    print('warnings: ${_warnings.length}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

// ---------------------------------------------------------------------------
// Ortak yardımcılar

J _utf8(String s) => {'utf8': s};
J _b64(List<int> b) => {'b64': base64Encode(b)};
J _fixture(String p) => {'fixture': 'fixtures/$p'};
J _gen(int size, int seed) => {
  'gen': {'size': size, 'seed': seed},
};
J _concat(List<J> parts) => {'concat': parts};
J _repeat(String unit, int count) => {'repeat': unit, 'count': count};

Uint8List _genBytes(int size, int seed) {
  final out = Uint8List(size);
  final base = seed * 31;
  for (var i = 0; i < size; i++) {
    out[i] = (base + i) & 0xFF;
  }
  return out;
}

Uint8List _resolve(J input) {
  if (input['utf8'] case final String s) return utf8.encode(s);
  if (input['b64'] case final String s) return base64Decode(s);
  if (input['fixture'] case final String p) {
    return File('$_vectorsPath/$p').readAsBytesSync();
  }
  if (input['gen'] case final Map<String, Object?> g) {
    return _genBytes(g['size']! as int, g['seed']! as int);
  }
  if (input['concat'] case final List<Object?> parts) {
    final b = BytesBuilder(copy: false);
    for (final p in parts) {
      b.add(_resolve(p! as J));
    }
    return b.toBytes();
  }
  if (input['repeat'] case final String unit) {
    return utf8.encode(unit * (input['count']! as int));
  }
  throw ArgumentError('bilinmeyen bayt girdisi: $input');
}

J _case(
  String name,
  Object? input,
  Object? expect, {
  String? rule,
  String? deviation,
}) => {
  'name': name,
  'input': input,
  'expect': expect,
  'deviation': ?deviation,
  'source': deviation == null ? 'oracle' : 'manual',
  'rule': ?rule,
};

void _checkDeviation(String file, String name, Object? dart, Object? expect) {
  if (jsonEncode(dart) == jsonEncode(expect)) {
    _warnings.add('WARN deviation not applied: $file/$name');
  }
}

String _sha16(List<int> bytes) =>
    sha256.convert(bytes).toString().substring(0, 16);

/// Sözleşme hash'i (B-8.1.5–B-8.1.7, E35 tam SHA-256). Dart'tan bağımsız hesap.
String _contractHash(J input) {
  final prefix = input['prefix']! as String;
  String text(String v) => '$prefix:${_sha16(utf8.encode('$prefix:$v'))}';
  switch (prefix) {
    case 't' || 'u' || 's' || 'c' || 'r':
      return text(input['text']! as String);
    case 'f':
      return text((input['uris']! as List<Object?>).cast<String>().join('|'));
    case 'i' || 'p':
      final b = _resolve(input['bytes']! as J);
      return '$prefix:${b.length}:${_sha16(b)}';
    case 'is':
      final items = (input['items']! as List<Object?>)
          .map((e) => _resolve(e! as J))
          .toList();
      final parts = items.map((b) => '${b.length}:${_sha16(b)}').join('|');
      return 'is:${items.length}:${_sha16(utf8.encode(parts))}';
  }
  throw ArgumentError(prefix);
}

String _argbHex(int v) =>
    '0x${v.toRadixString(16).padLeft(8, '0').toUpperCase()}';

// ---------------------------------------------------------------------------
// detect.json

class _D {
  const _D(this.name, this.input, this.rule, {this.dev, this.expect});
  final String name;
  final String input;
  final String rule;
  final String? dev;
  final J? expect;
}

const J _none = {'kind': 'none'};

/// B-8.2.1 (S8.2): kendi URL sözdizimimiz, Dart'tan bağımsız.
final RegExp _urlRe = RegExp(
  r'^(?:(?:https?|ftp)://|mailto:).',
  caseSensitive: false,
  dotAll: true,
);

/// B-6.4.5 daraltma kümesi (ECMAScript `\s`).
bool _isCollapseWs(int c) =>
    (c >= 0x09 && c <= 0x0D) ||
    c == 0x20 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF;

bool _contractIsUrl(String trimmed) =>
    _urlRe.hasMatch(trimmed) && !trimmed.runes.any(_isCollapseWs);

J _dartDetect(String raw) {
  final t = raw.trim();
  if (ClipboardEntry.looksLikeUrl(raw)) {
    return {'kind': 'url', 'uri': Uri.parse(t).toString()};
  }
  if (ClipboardEntry.looksLikeColor(raw)) {
    final e = ClipboardEntry.color(raw);
    final argb = e.toArgb32();
    return {
      'kind': 'color',
      'normalized': e.text,
      'argb': argb == null ? null : _argbHex(argb),
    };
  }
  if (ClipboardEntry.looksLikeEmail(raw)) {
    return {'kind': 'email', 'uri': Uri.parse('mailto:$t').toString()};
  }
  if (ClipboardEntry.looksLikePhone(raw)) {
    final tel = 'tel:${ClipboardEntry.normalizePhone(t)}';
    return {'kind': 'phone', 'uri': Uri.parse(tel).toString()};
  }
  if (SvgSanitizer.looksLikeSvgMarkup(raw)) return {'kind': 'svg'};
  return {'kind': 'none'};
}

List<J> _detect() {
  const url = 'B-8.2.1';
  const hex = 'B-8.2.2';
  const rgb = 'B-8.2.3';
  const hsl = 'B-8.2.4';
  const mail = 'B-8.2.6';
  const tel = 'B-8.2.7';
  const svg = 'B-8.2.8';
  final longComment = 'a' * 600;
  final specs = <_D>[
    const _D('url_https_simple', 'https://example.com', url),
    const _D('url_query', 'https://x.com/a?b=1', url),
    const _D('url_http_single_label_host', 'http://x', url),
    const _D('url_ftp', 'ftp://files.example.org/pub/a.txt', url),
    const _D('url_mailto', 'mailto:a@b.c', url),
    const _D('url_port_fragment', 'https://example.com:8080/a#frag', url),
    const _D('url_percent_encoded', 'https://example.com/a%20b', url),
    const _D('url_trimmed_spaces', '  https://example.com/path  ', url),
    const _D('url_trailing_newline_trimmed', 'https://example.com\n', url),
    const _D('url_trim_nbsp', '\u00A0https://example.com\u00A0', url),
    const _D('url_trim_bom', '\uFEFFhttps://example.com', url),
    const _D('url_trim_nel', '\u0085https://example.com', url),
    const _D('url_trim_ideographic_space', '\u3000https://example.com', url),
    const _D('url_internal_newline_rejected', 'line1\nhttps://x.com', url),
    // S8.2: URL sözdizimi kendi kuralımız (B-8.2.1); Dart Uri'nin esnekliği alınmaz.
    const _D(
      'url_internal_cr_rejected',
      'https://x.com/\rfoo',
      url,
      dev: 'S8.2',
      expect: _none,
    ),
    const _D(
      'url_empty_host_rejected',
      'http://',
      url,
      dev: 'S8.2',
      expect: _none,
    ),
    const _D(
      'url_scheme_only_rejected',
      'https:',
      url,
      dev: 'S8.2',
      expect: _none,
    ),
    const _D(
      'url_internal_space_rejected',
      'https://x.com/a b',
      url,
      dev: 'S8.2',
      expect: _none,
    ),
    const _D(
      'url_internal_tab_rejected',
      'https://x.com/a\tb',
      url,
      dev: 'S8.2',
      expect: _none,
    ),
    const _D(
      'url_internal_nbsp_rejected',
      'https://x.com/a\u00A0b',
      url,
      dev: 'S8.2',
      expect: _none,
    ),
    const _D(
      'url_scheme_then_words_rejected',
      'http: hello world',
      url,
      dev: 'S8.2',
      expect: _none,
    ),
    const _D(
      'url_space_in_host_rejected',
      'https://exa mple.com',
      url,
      dev: 'S8.2',
      expect: _none,
    ),
    const _D(
      'url_unclosed_ipv6_bracket_accepted',
      'https://[::1',
      url,
      dev: 'S8.2',
      expect: {'kind': 'url', 'uri': 'https://[::1'},
    ),
    const _D(
      'url_turkish_path_original_kept',
      'https://x.com/\u015F',
      url,
      dev: 'E21',
      expect: {'kind': 'url', 'uri': 'https://x.com/\u015F'},
    ),
    const _D(
      'url_all_caps_original_kept',
      'HTTPS://X.COM',
      url,
      dev: 'E21',
      expect: {'kind': 'url', 'uri': 'HTTPS://X.COM'},
    ),
    const _D('url_javascript_rejected', 'javascript:alert(1)', url),
    const _D('url_file_scheme_rejected', 'file:///etc/hosts', url),
    const _D('url_no_scheme_rejected', 'www.example.com', url),
    const _D('url_ws_scheme_rejected', 'ws://x.com', url),
    const _D(
      'url_uppercase_scheme_original_kept',
      'HTTPS://Example.COM/Path',
      url,
      dev: 'E21',
      expect: {'kind': 'url', 'uri': 'HTTPS://Example.COM/Path'},
    ),
    const _D(
      'url_mailto_uppercase_original_kept',
      'MAILTO:A@B.COM',
      url,
      dev: 'E21',
      expect: {'kind': 'url', 'uri': 'MAILTO:A@B.COM'},
    ),
    const _D('color_hex6', '#ff0000', hex),
    const _D('color_hex6_upper', '#FF0000', hex),
    const _D('color_hex3', '#f00', hex),
    const _D('color_hex4_alpha_last', '#f008', hex),
    const _D('color_hex8_alpha_last', '#00ff0080', hex),
    const _D('color_hex_trimmed', ' #ABC ', hex),
    const _D('color_hex5_rejected', '#12345', hex),
    const _D('color_hex_invalid_digit', '#ggg', hex),
    const _D('color_bare_hex4_text', 'beef', hex),
    const _D('color_arabic_digits_rejected', '#\u0661\u0662\u0663', hex),
    const _D(
      'color_bare_hex6_is_text',
      'ff0000',
      hex,
      dev: 'E22',
      expect: {'kind': 'none'},
    ),
    const _D(
      'color_bare_digits_is_text',
      '123456',
      hex,
      dev: 'E22',
      expect: {'kind': 'none'},
    ),
    const _D(
      'color_bare_word_decade_is_text',
      'decade',
      hex,
      dev: 'E22',
      expect: {'kind': 'none'},
    ),
    const _D(
      'color_bare_hex3_is_text',
      'abc',
      hex,
      dev: 'E22',
      expect: {'kind': 'none'},
    ),
    const _D(
      'color_bare_hex8_is_text',
      'deadbeef',
      hex,
      dev: 'E22',
      expect: {'kind': 'none'},
    ),
    const _D('color_rgb_spaces', 'rgb(255, 0, 0)', rgb),
    const _D('color_rgb_compact', 'rgb(0,0,255)', rgb),
    const _D('color_rgb_upper', 'RGB(10, 20, 30)', rgb),
    const _D('color_rgb_clamped', 'rgb(300, 0, 999)', rgb),
    const _D('color_rgba_leading_dot_alpha', 'rgba(255,0,0,.5)', rgb),
    const _D('color_rgba_alpha_one', 'rgba(0,128,0,1)', rgb),
    const _D('color_rgba_alpha_zero', 'rgba(0,0,0,0)', rgb),
    const _D('color_rgba_alpha_two_rejected', 'rgba(1,2,3,2)', rgb),
    const _D('color_rgb_space_syntax_rejected', 'rgb(1 2 3)', rgb),
    const _D(
      'color_rgba_zero_point_five',
      'rgba(255,0,0,0.5)',
      rgb,
      dev: 'E23',
      expect: {
        'kind': 'color',
        'normalized': 'rgba(255,0,0,0.5)',
        'argb': '0x80FF0000',
      },
    ),
    const _D(
      'color_rgba_zero_point_two_five',
      'rgba(0, 0, 255, 0.25)',
      rgb,
      dev: 'E23',
      expect: {
        'kind': 'color',
        'normalized': 'rgba(0, 0, 255, 0.25)',
        'argb': '0x400000FF',
      },
    ),
    const _D('color_hsl_green', 'hsl(120, 100%, 50%)', hsl),
    const _D('color_hsl_grey', 'hsl(0, 0%, 50%)', hsl),
    const _D('color_hsla_alpha', 'hsla(240, 100%, 50%, 0.5)', hsl),
    const _D('color_hsl_deg', 'hsl(120deg, 100%, 25%)', hsl),
    const _D('color_hsl_missing_percent_rejected', 'hsl(120, 50, 50)', hsl),
    const _D('color_hsl_space_syntax_rejected', 'hsl(120 100% 50%)', hsl),
    const _D('color_named_rejected', 'red', hsl),
    const _D('email_simple', 'a@b.com', mail),
    const _D('email_plus_tag', 'user.name+tag@sub.domain.org', mail),
    const _D('email_trimmed', '  ayse@ornek.com\n', mail),
    const _D('email_uppercase', 'A@B.COM', mail),
    const _D('email_no_tld_rejected', 'a@b', mail),
    const _D('email_trailing_word_rejected', 'a@b.com extra', mail),
    const _D('email_non_ascii_local_rejected', 'ay\u015Fe@ornek.com', mail),
    const _D('phone_tr', '+90 532 123 45 67', tel),
    const _D('phone_us_parens', '+1 (555) 010-9999', tel),
    const _D('phone_dots', '+44.20.7946.0958', tel),
    const _D('phone_eight_digits_min', '+12345678', tel),
    const _D('phone_seven_digits_rejected', '+1234567', tel),
    const _D('phone_fifteen_digits_max', '+123456789012345', tel),
    const _D('phone_sixteen_digits_rejected', '+1234567890123456', tel),
    const _D('phone_no_plus_rejected', '0532 123 45 67', tel),
    const _D('phone_too_short_rejected', '+90 123', tel),
    const _D('phone_zero_country_rejected', '+0 532 123 45 67', tel),
    const _D(
      'phone_arabic_digits_rejected',
      '+\u0669\u0660\u0665\u0663\u0662\u0661\u0662\u0663\u0664\u0665',
      tel,
    ),
    const _D(
      'svg_simple',
      '<svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg>',
      svg,
    ),
    const _D(
      'svg_xml_prolog',
      '<?xml version="1.0"?>\n<svg><rect/></svg>',
      svg,
    ),
    const _D('svg_leading_whitespace', '\n  <svg></svg>', svg),
    const _D('svg_uppercase_tags', '<SVG></SVG>', svg),
    const _D('svg_self_closing_rejected', '<svg/>', svg),
    const _D('svg_inside_html_rejected', '<div><svg></svg></div>', svg),
    _D(
      'svg_prolog_svg_beyond_512_rejected',
      '<?xml version="1.0"?><!--$longComment--><svg></svg>',
      svg,
    ),
    _D(
      'svg_heuristic_ignores_doctype',
      File('$_vectorsPath/fixtures/malicious_svg/billion_laughs.svg')
          .readAsStringSync(),
      svg,
    ),
    const _D('none_plain_text', 'just some text', url),
    const _D('none_empty', '', url),
    const _D('none_whitespace_only', '   \n\t', url),
    const _D('none_year_number', '2024', tel),
  ];
  final out = <J>[];
  for (final s in specs) {
    final dart = _dartDetect(s.input);
    if (s.dev != null) {
      _checkDeviation('detect', s.name, dart, s.expect);
      final t = s.input.trim();
      final isUrl = s.expect!['kind'] == 'url';
      if (_contractIsUrl(t) != isUrl || (isUrl && s.expect!['uri'] != t)) {
        _errors.add('detect/${s.name}: elle beklenti B-8.2.1 ile çelişiyor');
      }
      out.add(_case(s.name, s.input, s.expect, rule: s.rule, deviation: s.dev));
      continue;
    }
    final t = s.input.trim();
    final kind = dart['kind'];
    if (_contractIsUrl(t) != (kind == 'url')) {
      _errors.add(
        'detect/${s.name}: Dart url kararı B-8.2.1 ile çelişiyor; S8.2 etiketi gerekli',
      );
    }
    if (kind == 'url' && dart['uri'] != t) {
      _errors.add(
        'detect/${s.name}: Dart uri "${dart['uri']}" ≠ kırpılmış metin; E21 etiketi gerekli',
      );
    }
    if (kind == 'email' && dart['uri'] != 'mailto:$t') {
      _errors.add('detect/${s.name}: mailto uri normalize edildi');
    }
    if (kind == 'color' && dart['argb'] == null) {
      _errors.add('detect/${s.name}: renk ayrıştırılamadı');
    }
    out.add(_case(s.name, s.input, dart, rule: s.rule));
  }
  return out;
}

// ---------------------------------------------------------------------------
// hash.json

class _H {
  const _H(this.name, this.input, this.rule, {this.dev, this.dart});
  final String name;
  final J input;
  final String rule;
  final String? dev;

  /// Eski (Flutter) yolun hash'i; null → önekten türetilir.
  final String Function()? dart;
}

String _dartHash(J input) {
  final prefix = input['prefix']! as String;
  final text = input['text'] as String?;
  switch (prefix) {
    case 't':
      return ClipboardEntry.text(text!).contentHash;
    case 'u':
      return ClipboardEntry.url(Uri.parse(text!)).contentHash;
    case 's':
      return ClipboardEntry.svg(text!).contentHash;
    case 'c':
      return ClipboardEntry.color(text!).contentHash;
    case 'r':
      final cut = text!.indexOf('\u0000');
      return ClipboardEntry.richText(
        plainText: text.substring(0, cut),
        html: text.substring(cut + 1),
      ).contentHash;
    case 'f':
      final uris = (input['uris']! as List<Object?>).cast<String>();
      for (final u in uris) {
        if (Uri.parse(u).toString() != u) {
          _errors.add('hash: file URI "$u" Dart tarafından normalize edildi');
        }
      }
      return ClipboardEntry.files(uris.map(Uri.parse).toList()).contentHash;
    case 'i':
      return ClipboardEntry.image(_resolve(input['bytes']! as J)).contentHash;
    case 'p':
      return ClipboardEntry.pdf(_resolve(input['bytes']! as J)).contentHash;
    case 'is':
      final items = (input['items']! as List<Object?>)
          .map((e) => _resolve(e! as J))
          .toList();
      return ClipboardEntry.imageSet(items).contentHash;
  }
  throw ArgumentError(prefix);
}

List<J> _hash() {
  const th = 'B-8.1.5';
  const bh = 'B-8.1.6';
  const ish = 'B-8.1.7';
  J t(String p, String v) => {'prefix': p, 'text': v};
  J b(String p, J bytes) => {'prefix': p, 'bytes': bytes};
  J items(List<J> list) => {'prefix': 'is', 'items': list};
  final iconXml = File('$_vectorsPath/fixtures/malicious_svg/simple_icon.svg')
      .readAsStringSync();
  // E35: aynı uzunluk, aynı ilk ve son 64 KiB, farklı orta.
  const edge = 64 * 1024;
  const mid = 2 * _mib - 2 * edge;
  J collide(int midSeed) =>
      _concat([_gen(edge, 1), _gen(mid, midSeed), _gen(edge, 3)]);
  final specs = <_H>[
    _H('t_ascii', t('t', 'hello'), th),
    _H('t_empty', t('t', ''), th),
    _H('t_turkish_emoji', t('t', 'Gözlük 🎉'), th),
    _H('t_untrimmed_kept', t('t', '  padded  \n'), th),
    _H('t_embedded_nul', t('t', 'a\u0000b'), th),
    _H('u_https', t('u', 'https://example.com'), th),
    _H('u_mailto', t('u', 'mailto:a@b.com'), th),
    _H('u_tel', t('u', 'tel:+905321234567'), th),
    _H(
      'u_uppercase_original_text',
      t('u', 'HTTPS://Example.COM/Path'),
      th,
      dev: 'E21',
    ),
    _H(
      'u_bare_email_original_text',
      t('u', 'ayse@ornek.com'),
      th,
      dev: 'E21',
      dart: () => ClipboardEntry.url(
        Uri.parse('mailto:ayse@ornek.com'),
        displayText: 'ayse@ornek.com',
      ).contentHash,
    ),
    _H(
      'u_bare_phone_original_text',
      t('u', '+90 532 123 45 67'),
      th,
      dev: 'E21',
      dart: () => ClipboardEntry.url(
        Uri.parse('tel:+905321234567'),
        displayText: '+90 532 123 45 67',
      ).contentHash,
    ),
    _H('s_simple_icon_fixture', t('s', iconXml), th),
    _H('s_inline_markup', t('s', '<svg></svg>'), th),
    _H('c_hex', t('c', '#ff0000'), th),
    _H('c_rgb_normalized', t('c', 'rgb(255, 0, 0)'), th),
    _H('c_hsla_normalized', t('c', 'hsla(240, 100%, 50%, 0.5)'), th),
    _H('r_plain_nul_html', t('r', 'hi\u0000<b>hi</b>'), th),
    _H('r_turkish', t('r', 'Şubat raporu\u0000<p>Şubat <b>raporu</b></p>'), th),
    _H('f_single', {
      'prefix': 'f',
      'uris': ['file:///tmp/sclip/a.png'],
    }, th),
    _H('f_multi_percent_encoded', {
      'prefix': 'f',
      'uris': ['file:///tmp/a.png', 'file:///tmp/b%20c.pdf'],
    }, th),
    _H('f_windows_drive', {
      'prefix': 'f',
      'uris': ['file:///C:/Users/foo/bar.txt'],
    }, th),
    _H('i_four_bytes', b('i', _b64([1, 2, 3, 4])), bh),
    _H('i_empty', b('i', _b64(<int>[])), bh),
    _H('i_png_fixture', b('i', _fixture('tiny.png')), bh),
    _H('i_exactly_1mib', b('i', _gen(_mib, 1)), bh),
    _H('i_1mib_plus_one_full_sha', b('i', _gen(_mib + 1, 1)), bh, dev: 'E35'),
    _H('i_2mib_full_sha', b('i', _gen(2 * _mib, 5)), bh, dev: 'E35'),
    _H('p_small', b('p', _b64(utf8.encode('%PDF-1.4\n%%EOF\n'))), bh),
    _H('p_edges_equal_middle_a', b('p', collide(2)), bh, dev: 'E35'),
    _H('p_edges_equal_middle_b', b('p', collide(4)), bh, dev: 'E35'),
    _H(
      'is_two_small',
      items([
        _b64([1, 2, 3, 4]),
        _b64([5, 6, 7, 8]),
      ]),
      ish,
    ),
    _H(
      'is_two_small_swapped',
      items([
        _b64([5, 6, 7, 8]),
        _b64([1, 2, 3, 4]),
      ]),
      ish,
    ),
    _H(
      'is_same_bytes_twice',
      items([
        _b64([1, 2, 3, 4]),
        _b64([1, 2, 3, 4]),
      ]),
      ish,
    ),
    _H(
      'is_three_fixtures',
      items([_fixture('tiny.png'), _fixture('tiny.jpg'), _fixture('tiny.gif')]),
      ish,
    ),
    _H(
      'is_large_item_full_sha',
      items([
        _gen(_mib + 7, 2),
        _b64([9]),
      ]),
      ish,
      dev: 'E35',
    ),
  ];
  final out = <J>[];
  final byName = <String, String>{};
  for (final s in specs) {
    final dart = s.dart?.call() ?? _dartHash(s.input);
    final contract = _contractHash(s.input);
    if (s.dev != null) {
      _checkDeviation('hash', s.name, dart, contract);
      out.add(_case(s.name, s.input, contract, rule: s.rule, deviation: s.dev));
    } else {
      if (dart != contract) {
        _errors.add(
          'hash/${s.name}: Dart "$dart" ≠ sözleşme "$contract"; sapma etiketi gerekli',
        );
      }
      out.add(_case(s.name, s.input, dart, rule: s.rule));
    }
    byName[s.name] = contract;
  }
  if (byName['p_edges_equal_middle_a'] == byName['p_edges_equal_middle_b']) {
    _errors.add('hash: E35 çifti aynı hash verdi');
  }
  return out;
}

// ---------------------------------------------------------------------------
// svg_sanitize.json

class _S {
  const _S(this.name, this.input, this.rule, {this.dev, this.safe});
  final String name;
  final J input;
  final String rule;
  final String? dev;
  final bool? safe;
}

// `href` adı: öncesi ad karakteri değilse ya da `:` ise (B-8.10.3). Değer ayrıca `_hrefValue` ile okunur;
// eşleşme sıfır genişlikli değer başlangıcında biter, böylece her geçiş bağımsız denetlenir.
final RegExp _hrefRe = RegExp(
  '(?<![a-z0-9_.\\-:\\u0080-\\uffff])(?:[a-z0-9_.\\-:\\u0080-\\uffff]*:)?href'
  '[ \\t\\n\\r]*=[ \\t\\n\\r]*',
);
final RegExp _prefixedActiveRe = RegExp(
  '<[^ \\t\\n\\r/><]*:(?:script|foreignobject)',
);
final RegExp _cssUrlRe = RegExp('url\\([ \\t\\n\\r]*[\'"]?[ \\t\\n\\r]*');

String _hrefValue(String body, int pos) {
  final c = pos < body.length ? body[pos] : '';
  if (c == '"' || c == "'") {
    final end = body.indexOf(c, pos + 1);
    // Kapanış tırnağı yoksa değer tırnakla başlar (reddedilir).
    return end < 0 ? body.substring(pos) : body.substring(pos + 1, end);
  }
  var end = pos;
  while (end < body.length && !' \t\n\r>'.contains(body[end])) {
    end++;
  }
  return body.substring(pos, end);
}

final RegExp _xmlDeclRe = RegExp('^<\\?xml[ \\t\\n\\r]');
final RegExp _encodingRe = RegExp(
  'encoding[ \\t\\n\\r]*=[ \\t\\n\\r]*(?:"([^"]*)"|\'([^\']*)\')',
);

/// B-8.10.6: ilk bayt (BOM + XML boşluğundan sonra) `<`; XML bildirimi varsa encoding utf-8 / ascii.
bool _contractEncodingSafe(String body) {
  final m = _xmlDeclRe.firstMatch(body);
  if (m == null) return true;
  final end = body.indexOf('?>');
  if (end < 0) return false;
  final decl = body.substring(0, end);
  if ('encoding'.allMatches(decl).length !=
      _encodingRe.allMatches(decl).length) {
    return false;
  }
  for (final e in _encodingRe.allMatches(decl)) {
    final v = e.group(1) ?? e.group(2)!;
    if (v != 'utf-8' && v != 'us-ascii' && v != 'ascii') return false;
  }
  return true;
}

/// Sözleşme sanitizer'ı (B-8.10.1–B-8.10.6): Flutter kuralları + S8.10 eki. Dart'tan bağımsız
/// hesap; her svg vakası buna karşı da denetlenir.
bool _contractSvgSafe(Uint8List b) {
  if (b.length > SvgSanitizer.maxSvgBytes) return false;
  if (b.contains(0)) return false;
  for (var i = 0; i + 1 < b.length; i++) {
    if ((b[i] == 0xFF && b[i + 1] == 0xFE) ||
        (b[i] == 0xFE && b[i + 1] == 0xFF)) {
      return false;
    }
  }
  // B-8.10.6 (a)(b): katı UTF-8; BOM + XML boşluğundan sonra ilk bayt `<`.
  var off = 0;
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) off = 3;
  while (off < b.length &&
      (b[off] == 0x20 || b[off] == 0x09 || b[off] == 0x0D || b[off] == 0x0A)) {
    off++;
  }
  if (off < b.length && b[off] != 0x3C) return false;
  final String body;
  try {
    body = utf8.decode(b.sublist(off)).toLowerCase();
  } on FormatException {
    return false;
  }
  if (!_contractEncodingSafe(body)) return false;
  const banned = [
    '<!doctype',
    '<!entity',
    '<!attlist',
    'xmlns:xi=',
    'xinclude',
    '<script',
    '<foreignobject',
    '@import',
  ];
  if (banned.any(body.contains)) return false;
  if (_prefixedActiveRe.hasMatch(body)) return false;
  for (final m in _cssUrlRe.allMatches(body)) {
    if (!body.startsWith('#', m.end) && !body.startsWith('data:', m.end)) {
      return false;
    }
  }
  for (final m in _hrefRe.allMatches(body)) {
    final value = _xmlTrim(_hrefValue(body, m.end));
    if (value.isEmpty) return false;
    if (!value.startsWith('#') && !value.startsWith('data:')) return false;
  }
  return true;
}

/// B-8.10.3: yalnız XML boşlukları (U+0020, U+0009, U+000D, U+000A) kırpılır.
String _xmlTrim(String v) {
  bool ws(int c) => c == 0x20 || c == 0x09 || c == 0x0D || c == 0x0A;
  var a = 0;
  var b = v.length;
  while (a < b && ws(v.codeUnitAt(a))) {
    a++;
  }
  while (b > a && ws(v.codeUnitAt(b - 1))) {
    b--;
  }
  return v.substring(a, b);
}

List<int> _utf16(String s, {required bool bigEndian, bool bom = false}) {
  final out = <int>[];
  void unit(int u) => bigEndian
      ? out.addAll([u >> 8, u & 0xFF])
      : out.addAll([u & 0xFF, u >> 8]);
  if (bom) unit(0xFEFF);
  s.codeUnits.forEach(unit);
  return out;
}

List<J> _svg() {
  const cap = 'B-8.10.1';
  const xxe = 'B-8.10.2';
  const ext = 'B-8.10.3';
  const enc = 'B-8.10.5';
  final comment = 'a' * 5000;
  const capBytes = 20 * _mib;
  J padded(int size) =>
      _concat([_utf8('<svg>'), _repeat(' ', size - 11), _utf8('</svg>')]);
  _S unsafe(String name, String xml, [String rule = ext]) =>
      _S(name, _utf8(xml), rule, dev: 'S8.10', safe: false);
  _S unsafeBytes(String name, J input, String rule) =>
      _S(name, input, rule, dev: 'S8.10', safe: false);
  _S safe(String name, String xml) => _S(name, _utf8(xml), ext);
  const doctype = '<!DOCTYPE svg><svg></svg>';
  final specs = <_S>[
    _S(
      'fixture_billion_laughs',
      _fixture('malicious_svg/billion_laughs.svg'),
      xxe,
    ),
    _S(
      'fixture_external_entity',
      _fixture('malicious_svg/external_entity.svg'),
      xxe,
    ),
    _S('fixture_xinclude', _fixture('malicious_svg/xinclude.svg'), xxe),
    _S('fixture_simple_icon', _fixture('malicious_svg/simple_icon.svg'), xxe),
    _S('fixture_figma_like', _fixture('malicious_svg/figma_like.svg'), xxe),
    _S(
      'attlist_declaration',
      _utf8('<?xml version="1.0"?>\n<!ATTLIST foo bar CDATA #IMPLIED>\n<svg/>'),
      xxe,
    ),
    _S('doctype_lowercase', _utf8('<!doctype svg><svg></svg>'), xxe),
    _S('entity_without_doctype', _utf8("<!ENTITY x 'y'><svg></svg>"), xxe),
    _S(
      'xmlns_xi_only',
      _utf8('<svg xmlns:xi="http://www.w3.org/2001/XInclude"></svg>'),
      xxe,
    ),
    _S(
      'xinclude_mixed_case_text',
      _utf8('<svg><desc>XInclude</desc></svg>'),
      xxe,
    ),
    _S(
      'doctype_after_long_comment',
      _utf8('<!--$comment--><!DOCTYPE svg><svg></svg>'),
      xxe,
    ),
    _S('empty_payload', _utf8(''), xxe),
    _S(
      'invalid_utf8_then_doctype',
      _concat([
        _b64([0xFF, 0xC3]),
        _utf8(doctype),
      ]),
      xxe,
    ),
    unsafeBytes(
      'invalid_utf8_rejected',
      _b64([0x3C, 0x73, 0x76, 0x67, 0x80, 0x81, 0xC3]),
      enc,
    ),
    _S(
      'utf8_bom_svg_safe',
      _concat([
        _b64([0xEF, 0xBB, 0xBF]),
        _utf8('<svg></svg>'),
      ]),
      enc,
    ),
    _S('at_20mib_cap_accepted', padded(capBytes), cap),
    _S('over_20mib_cap_rejected', padded(capBytes + 1), cap),
    unsafeBytes(
      'svg_invalid_utf8',
      _b64([0xFF, 0xFE, 0x00, 0x00, 0x80, 0x81]),
      enc,
    ),
    unsafeBytes(
      'utf16le_bom_doctype',
      _b64(_utf16(doctype, bigEndian: false, bom: true)),
      enc,
    ),
    unsafeBytes(
      'utf16be_no_bom_doctype',
      _b64(_utf16(doctype, bigEndian: true)),
      enc,
    ),
    unsafeBytes(
      'nul_byte',
      _concat([
        _utf8('<svg>'),
        _b64([0]),
        _utf8('</svg>'),
      ]),
      enc,
    ),
    unsafeBytes(
      'utf16_bom_without_nul',
      _concat([
        _b64([0xFF, 0xFE]),
        _utf8('<svg></svg>'),
      ]),
      enc,
    ),
    unsafeBytes(
      'utf16be_bom_mid_payload',
      _concat([
        _utf8('<svg>'),
        _b64([0xFE, 0xFF]),
        _utf8('</svg>'),
      ]),
      enc,
    ),
    unsafeBytes('gen_bytes_contain_nul', _gen(1024, 7), enc),
    safe('href_fragment_safe', '<svg><use href="#a"/></svg>'),
    safe(
      'xlink_href_fragment_safe',
      '<svg xmlns:xlink="http://www.w3.org/1999/xlink"><use xlink:href="#icon"/></svg>',
    ),
    safe(
      'href_data_uri_safe',
      '<svg><image href="data:image/png;base64,iVBORw0KGgo="/></svg>',
    ),
    safe(
      'xmlns_url_is_not_href',
      '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>',
    ),
    safe('fill_url_fragment_safe', '<svg><rect fill="url(#g)"/></svg>'),
    safe(
      'href_leading_space_fragment_trimmed_safe',
      '<svg><use href=" #a"/></svg>',
    ),
    safe(
      'xlink_href_leading_space_data_safe',
      "<svg><image xlink:href=' data:image/png;base64,AA=='/></svg>",
    ),
    safe('href_spaces_around_equals_safe', '<svg><use href = "#a"/></svg>'),
    safe('href_unquoted_fragment_safe', '<svg><use href=#a /></svg>'),
    safe(
      'data_href_attribute_not_matched',
      '<svg><g data-href="https://x.example/"/></svg>',
    ),
    safe(
      'declared_utf8_double_quoted_safe',
      '<?xml version="1.0" encoding="UTF-8"?><svg/>',
    ),
    safe(
      'declared_utf8_single_quoted_safe',
      "<?xml version='1.0' encoding='utf-8'?><svg/>",
    ),
    safe(
      'declared_us_ascii_safe',
      '<?xml version="1.0" encoding="US-ASCII"?><svg/>',
    ),
    safe(
      'xml_declaration_without_encoding_safe',
      '<?xml version="1.0"?><svg/>',
    ),
    safe(
      'xml_stylesheet_pi_is_not_declaration_safe',
      '<?xml-stylesheet href="#s"?><svg/>',
    ),
    safe('whitespace_only_payload_safe', ' \n\t'),
    _S(
      'bom_whitespace_then_svg_safe',
      _concat([
        _b64([0xEF, 0xBB, 0xBF]),
        _utf8('\r\n\t <svg></svg>'),
      ]),
      enc,
    ),
    safe(
      'valid_non_ascii_utf8_safe',
      '<svg><text>çğış \u{FFFD} 😀</text></svg>',
    ),
    safe('xhref_not_matched', '<svg><g xhref="https://x.example/"/></svg>'),
    safe('custom_ns_href_fragment_safe', '<svg><image x:href="#a"/></svg>'),
    safe(
      'prefixed_svg_elements_safe',
      '<svg:svg xmlns:svg="http://www.w3.org/2000/svg"><svg:rect/></svg:svg>',
    ),
    safe(
      'css_url_fragment_forms_safe',
      '<svg><rect fill="url(#g)" style="fill:url( \'#g\' )"/></svg>',
    ),
    safe(
      'css_url_data_safe',
      '<svg><rect style="fill:url(data:image/png;base64,AA==)"/></svg>',
    ),
    safe('event_handler_accepted_risk', '<svg onload="alert(1)"><rect/></svg>'),
    safe(
      'real_href_after_fragment_safe',
      '<svg><g title="a"/><use href="#a"/><use href="#b"/></svg>',
    ),
    unsafe('script_tag', '<svg><script>alert(1)</script></svg>'),
    unsafe('script_tag_uppercase', '<svg><SCRIPT>alert(1)</SCRIPT></svg>'),
    unsafe(
      'foreign_object',
      '<svg><foreignObject><div>x</div></foreignObject></svg>',
    ),
    unsafe(
      'href_https',
      '<svg><a href="https://evil.example/"><text>x</text></a></svg>',
    ),
    unsafe(
      'href_single_quoted_http',
      "<svg><use href='http://x.example/y.svg#a'/></svg>",
    ),
    unsafe('href_javascript', '<svg><a href="javascript:alert(1)">x</a></svg>'),
    unsafe(
      'xlink_href_file',
      '<svg xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="file:///etc/passwd"/></svg>',
    ),
    unsafe(
      'href_uppercase_attr_https',
      '<svg><a HREF="HTTPS://evil.example/">x</a></svg>',
    ),
    unsafe(
      'href_unquoted_https',
      '<svg><a href= https://x.example/>x</a></svg>',
    ),
    unsafe('href_empty', '<svg><use href=""/></svg>'),
    unsafe('href_nbsp_not_trimmed', '<svg><use href="\u00A0#a"/></svg>'),
    unsafe('href_whitespace_only', '<svg><use href="  "/></svg>'),
    unsafe(
      'href_after_newline',
      '<svg><use\nhref="https://x.example/"/></svg>',
    ),
    unsafe(
      'prefixed_ns_href_https',
      '<svg><g ns1:href="https://x.example/"/></svg>',
    ),
    unsafe(
      'custom_ns_alias_href_https',
      '<svg xmlns:x="http://www.w3.org/1999/xlink"><image x:href="http://evil.example/"/></svg>',
    ),
    unsafe(
      'href_slash_separator',
      '<svg><a/href="http://evil.example/">x</a></svg>',
    ),
    unsafe(
      'href_quote_separator',
      '<svg><a title="a"href="http://evil.example/">x</a></svg>',
    ),
    unsafe(
      'href_bypass_fake_in_comment',
      '<svg><!-- <a href="#x --><image href="http://evil"/></svg>',
    ),
    unsafe(
      'href_bypass_fake_in_text',
      '<svg><desc> href="#</desc><image href="http://evil"/></svg>',
    ),
    unsafe(
      'href_bypass_fake_in_attribute',
      '<svg><g title=\' href="#x\'/><image href="http://evil"/></svg>',
    ),
    unsafe(
      'href_bypass_fake_unquoted',
      '<svg><g a=href=#x b=1/><image href="http://evil"/></svg>',
    ),
    unsafe('href_unterminated_quote', '<svg><use href="#a'),
    unsafe(
      'utf7_doctype_entity_payload',
      '+ADw-!DOCTYPE svg [+ADw-!ENTITY x "y"+AD4-]+AD4-+ADw-svg/+AD4-',
      enc,
    ),
    unsafe(
      'utf7_declared_href_payload',
      '<?xml version="1.0" encoding="UTF-7"?>+ADw-svg+AD4-+ADw-image href+AD0-+ACI-http://evil+ACI-/+AD4-',
      enc,
    ),
    unsafe(
      'utf7_script_no_declaration',
      '+ADw-svg+AD4-+ADw-script+AD4-alert(1)+ADw-/script+AD4-',
      enc,
    ),
    unsafeBytes(
      'ebcdic_payload',
      _b64([0x4C, 0xA2, 0xA5, 0x87, 0x6E, 0x4C, 0x61, 0xA2, 0xA5, 0x87, 0x6E]),
      enc,
    ),
    unsafe(
      'declared_utf16_on_ascii_bytes',
      '<?xml version="1.0" encoding="UTF-16"?><svg/>',
      enc,
    ),
    unsafe(
      'declared_iso_8859_1',
      '<?xml version="1.0" encoding="ISO-8859-1"?><svg/>',
      enc,
    ),
    unsafe(
      'declared_encoding_unquoted',
      '<?xml version="1.0" encoding=utf-7?><svg/>',
      enc,
    ),
    unsafe(
      'declared_unterminated_declaration',
      '<?xml version="1.0" encoding="utf-8"',
      enc,
    ),
    unsafe(
      'declared_fake_utf8_then_utf7',
      '<?xml version="encoding=\'utf-8\'" encoding="utf-7"?><svg/>',
      enc,
    ),
    unsafe('leading_garbage_before_tag', 'x<svg/>', enc),
    unsafe('leading_text_before_tag', 'abc <svg></svg>', enc),
    unsafeBytes(
      'ff_byte_before_href',
      _concat([
        _utf8('<svg><use '),
        _b64([0xFF]),
        _utf8('href="http://e"/></svg>'),
      ]),
      enc,
    ),
    unsafe(
      'prefixed_script_tag',
      '<svg:svg xmlns:svg="http://www.w3.org/2000/svg"><svg:script>alert(1)</svg:script></svg:svg>',
    ),
    unsafe(
      'prefixed_foreign_object_mixed_case',
      '<svg><x:ForeignObject><div>x</div></x:ForeignObject></svg>',
    ),
    unsafe(
      'css_import_rule',
      "<svg><style>@import 'https://evil.example/x.css';</style></svg>",
    ),
    unsafe(
      'css_url_http_attribute',
      '<svg><rect fill="url(http://evil.example/g)"/></svg>',
    ),
    unsafe(
      'css_url_quoted_style',
      '<svg><rect style="background:url(\'http://evil.example/\')"/></svg>',
    ),
    unsafe(
      'css_url_double_quoted_spaced',
      '<svg><rect style=\'fill:URL( "http://evil.example/" )\'/></svg>',
    ),
    unsafe('css_url_empty', '<svg><rect fill="url()"/></svg>'),
    unsafe(
      'css_url_second_occurrence_external',
      '<svg><rect fill="url(#a)" stroke="url(http://evil.example/)"/></svg>',
    ),
  ];
  final out = <J>[];
  for (final s in specs) {
    final bytes = _resolve(s.input);
    final legacy = {'safe': SvgSanitizer.isSafePayload(bytes)};
    final contract = {'safe': _contractSvgSafe(bytes)};
    if (s.dev != null) {
      final expect = {'safe': s.safe};
      _checkDeviation('svg_sanitize', s.name, legacy, expect);
      if (jsonEncode(contract) != jsonEncode(expect)) {
        _errors.add(
          'svg_sanitize/${s.name}: sözleşme $contract ≠ elle beklenti $expect',
        );
      }
      out.add(_case(s.name, s.input, expect, rule: s.rule, deviation: s.dev));
    } else {
      if (jsonEncode(contract) != jsonEncode(legacy)) {
        _errors.add(
          'svg_sanitize/${s.name}: Dart $legacy ≠ sözleşme $contract; S8.10 etiketi gerekli',
        );
      }
      out.add(_case(s.name, s.input, legacy, rule: s.rule));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// search.json

J _clip(Map<String, J> formats) => {
  'items': [
    {'formats': formats},
  ],
};
J _clipItems(List<Map<String, J>> items) => {
  'items': [
    for (final f in items) {'formats': f},
  ],
};
J _clipFiles(List<String> fixtures) => {
  'items': <Object?>[],
  'files': [for (final f in fixtures) 'fixtures/$f'],
};

Uri _fixtureUri(String name) =>
    Uri.file(File('$_vectorsPath/fixtures/$name').absolute.path);
Uint8List _fx(String name) =>
    File('$_vectorsPath/fixtures/$name').readAsBytesSync();

J _search() {
  const normalizeInputs = <String>[
    'IŞIK', 'ışık', 'Işık', 'İSTANBUL', 'ISTANBUL', 'istanbul', //
    'Gözlük', 'GÖZLÜK', 'ÇAĞRI', 'çağrı', 'ŞEHİR', 'KÂĞIT', 'Kîm Ûmut',
    '  çok   satırlı\nmetin\t', 'a b', '', '   ', '\n\t ',
    'Hello World', '🎉 Şenlik', '  İki   KELİME\tÖĞÜŞÇ  ',
    'a\u000Bb', 'a\u000Cb', 'a\r\nb', '\u00A0x\u00A0y\u00A0',
    'a\u2003b', 'a\u3000b', 'ΟΔΟΣ', 'ÀÉÎ', 'STRASSE ß',
  ];
  final normalize = [
    for (final s in normalizeInputs)
      {'in': s, 'out': normalizeForSearch(s), 'source': 'oracle'},
  ];
  // Ayırt edici: ilk 8192 birimde uzun boşluk dizisi var; önce kesip sonra normalize
  // etmek "x c" verir, önce normalize edip sonra kesmek "x cilingir" verirdi.
  final cut = 'x${' ' * 8190}ÇILINGIR';
  if (normalizeForSearch(cut) == normalizeForSearch(cut.substring(0, 8192))) {
    _errors.add('search/text_cut_8192_before_normalize: ayırt edici değil');
  }
  final html = '<p>Şubat <strong>raporu</strong></p>';
  final iconXml = utf8.decode(_fx('malicious_svg/simple_icon.svg'));
  final specs = <(String, J, ClipboardEntry)>[
    (
      'text_turkish_folded',
      _clip({'text/plain': _utf8('IŞIK ve Gözlük')}),
      ClipboardEntry.text('IŞIK ve Gözlük'),
    ),
    (
      'text_whitespace_collapsed',
      _clip({'text/plain': _utf8('  çok   satırlı\nmetin\t')}),
      ClipboardEntry.text('  çok   satırlı\nmetin\t'),
    ),
    (
      'text_cut_8192_before_normalize',
      _clip({'text/plain': _utf8(cut)}),
      ClipboardEntry.text(cut),
    ),
    (
      'rich_text_plain_only',
      _clip({'text/plain': _utf8('Şubat raporu'), 'text/html': _utf8(html)}),
      ClipboardEntry.richText(plainText: 'Şubat raporu', html: html),
    ),
    (
      'rich_text_html_only_stripped',
      _clip({'text/html': _utf8(html)}),
      ClipboardEntry.richText(plainText: 'Şubat raporu', html: html),
    ),
    (
      'url_display_equals_uri',
      _clip({'text/plain': _utf8('https://example.com/Yol')}),
      ClipboardEntry.url(Uri.parse('https://example.com/Yol')),
    ),
    (
      'url_email_display_and_uri',
      _clip({'text/plain': _utf8('ayse@ornek.com')}),
      ClipboardEntry.url(
        Uri.parse('mailto:ayse@ornek.com'),
        displayText: 'ayse@ornek.com',
      ),
    ),
    (
      'url_phone_display_and_uri',
      _clip({'text/plain': _utf8('+90 532 123 45 67')}),
      ClipboardEntry.url(
        Uri.parse('tel:+905321234567'),
        displayText: '+90 532 123 45 67',
      ),
    ),
    (
      'color_hex_upper',
      _clip({'text/plain': _utf8('#FF0000')}),
      ClipboardEntry.color('#FF0000'),
    ),
    (
      'color_rgb_upper',
      _clip({'text/plain': _utf8('RGB(1, 2, 3)')}),
      ClipboardEntry.color('RGB(1, 2, 3)'),
    ),
    (
      'image_png',
      _clip({'image/png': _fixture('tiny.png')}),
      ClipboardEntry.image(_fx('tiny.png')),
    ),
    (
      'image_jpeg',
      _clip({'image/jpeg': _fixture('tiny.jpg')}),
      ClipboardEntry.image(_fx('tiny.jpg'), format: ClipboardImageFormat.jpeg),
    ),
    (
      'image_gif',
      _clip({'image/gif': _fixture('tiny.gif')}),
      ClipboardEntry.image(_fx('tiny.gif'), format: ClipboardImageFormat.gif),
    ),
    (
      'image_webp',
      _clip({'image/webp': _fixture('tiny.webp')}),
      ClipboardEntry.image(_fx('tiny.webp'), format: ClipboardImageFormat.webp),
    ),
    (
      'image_set_distinct_formats_in_order',
      _clipItems([
        {'image/png': _fixture('tiny.png')},
        {'image/jpeg': _fixture('tiny.jpg')},
        {'image/png': _fixture('tiny.png')},
      ]),
      ClipboardEntry.imageSet(
        [_fx('tiny.png'), _fx('tiny.jpg'), _fx('tiny.png')],
        formats: const [
          ClipboardImageFormat.png,
          ClipboardImageFormat.jpeg,
          ClipboardImageFormat.png,
        ],
      ),
    ),
    (
      'pdf_tag',
      _clip({'application/pdf': _b64(utf8.encode('%PDF-1.4\n%%EOF\n'))}),
      ClipboardEntry.pdf(Uint8List.fromList(utf8.encode('%PDF-1.4\n%%EOF\n'))),
    ),
    (
      'svg_bytes_tag_only',
      _clip({'image/svg+xml': _fixture('malicious_svg/simple_icon.svg')}),
      ClipboardEntry.svg(iconXml),
    ),
    (
      'svg_markup_text_tag_only',
      _clip({'text/plain': _utf8('<svg><path d="M0 0"/></svg>')}),
      ClipboardEntry.svg('<svg><path d="M0 0"/></svg>'),
    ),
    (
      'files_single_basename',
      _clipFiles(['fake.txt']),
      ClipboardEntry.files([_fixtureUri('fake.txt')]),
    ),
    (
      'files_mixed_all_basenames',
      _clipFiles([
        'tiny.png',
        'fake.txt',
        'malicious_svg/figma_like.svg',
        'tiny.jpg',
      ]),
      ClipboardEntry.files([
        _fixtureUri('tiny.png'),
        _fixtureUri('fake.txt'),
        _fixtureUri('malicious_svg/figma_like.svg'),
        _fixtureUri('tiny.jpg'),
      ]),
    ),
    (
      'files_empty_png_stays_files',
      _clipFiles(['empty.png']),
      ClipboardEntry.files([_fixtureUri('empty.png')]),
    ),
    (
      'files_single_image_becomes_image',
      _clipFiles(['tiny.png']),
      ClipboardEntry.image(_fx('tiny.png')),
    ),
    (
      'files_two_images_become_image_set',
      _clipFiles(['tiny.jpg', 'tiny.gif']),
      ClipboardEntry.imageSet(
        [_fx('tiny.jpg'), _fx('tiny.gif')],
        formats: const [ClipboardImageFormat.jpeg, ClipboardImageFormat.gif],
      ),
    ),
  ];
  final index = [
    for (final (name, entry, e) in specs)
      {
        'name': name,
        'entry': entry,
        'expect': e.searchIndex,
        'source': 'oracle',
        'rule': 'B-6.5.5',
      },
  ];
  // B-6.5.5 (L7): 8192 birimlik kesim vekil çiftini bölerse sarkan yüksek vekil atılır.
  // Dart onu tutar (yalnız yüksek vekil); beklenti elle verilir ve Dart çıktısının
  // tam olarak "beklenti + sarkan vekil" olduğu doğrulanır.
  final split = '${'a' * 8191}\u{1F389} sonrasi';
  final splitExpect = 'a' * 8191;
  final splitDart = ClipboardEntry.text(split).searchIndex;
  if (splitDart != '$splitExpect\uD83C') {
    _errors.add(
      'search/text_cut_drops_dangling_high_surrogate: Dart beklenmeyen çıktı',
    );
  }
  index.add({
    'name': 'text_cut_drops_dangling_high_surrogate',
    'entry': _clip({'text/plain': _utf8(split)}),
    'expect': splitExpect,
    'source': 'manual',
    'rule': 'B-6.5.5',
  });
  return {'normalize': normalize, 'index': index};
}

// ---------------------------------------------------------------------------
// history.json

class _HistoryRun {
  _HistoryRun(this.order, this.evicted, this.results);
  final List<String> order;
  final List<String> evicted;
  final List<String> results;
  J toJson() => {'order': order, 'evicted': evicted, 'results': results};
}

ClipboardEntry _historyEntry(J op) {
  final kind = op['kind']! as String;
  switch (kind) {
    case 'text':
      final text =
          op['text'] as String? ??
          (op['repeat']! as String) * (op['count']! as int);
      return ClipboardEntry.text(text);
    case 'image':
      return ClipboardEntry.image(
        _genBytes(op['size']! as int, op['seed']! as int),
      );
    case 'pdf':
      return ClipboardEntry.pdf(
        _genBytes(op['size']! as int, op['seed']! as int),
      );
  }
  throw ArgumentError(kind);
}

_HistoryRun _runHistory(
  J c, {
  required int maxImageBytes,
  required bool legacyServiceGate,
}) {
  final evicted = <String>[];
  final idToRef = <String, String>{};
  final refToId = <String, String>{};
  final results = <String>[];
  final p = HistoryProvider(
    maxItems: c['maxItems']! as int,
    maxImageBytes: maxImageBytes,
    maxTotalImageBytes: c['budgetBytes'] as int? ?? 150 * _mib,
  );
  p.onEvict = (e) => evicted.add(idToRef[e.id]!);
  var swallowNext = false;
  for (final raw in c['ops']! as List<Object?>) {
    final op = raw! as J;
    final ref = op['ref'] as String?;
    switch (op['op']) {
      case 'add':
        if (legacyServiceGate && swallowNext) {
          swallowNext = false;
          results.add('swallowed');
          continue;
        }
        final entry = _historyEntry(op);
        final headBefore = p.entries.isEmpty
            ? null
            : p.entries.first.contentHash;
        idToRef[entry.id] = ref!;
        p.add(entry);
        if (p.entries.isNotEmpty && identical(p.entries.first, entry)) {
          refToId[ref] = entry.id;
          results.add('added');
        } else {
          results.add(
            headBefore == entry.contentHash ? 'duplicateHead' : 'rejected',
          );
        }
      case 'touch':
        p.touch(refToId[ref] ?? '');
      case 'remove':
        p.removeById(refToId[ref] ?? '');
      case 'clear':
        p.clear();
        if (legacyServiceGate) swallowNext = true;
      case 'setMax':
        p.maxItems = op['n']! as int;
    }
  }
  return _HistoryRun(
    [for (final e in p.entries) idToRef[e.id]!],
    evicted,
    results,
  );
}

J _add(String ref, String text) => {
  'op': 'add',
  'ref': ref,
  'kind': 'text',
  'text': text,
};
J _addBig(String ref, String unit, int count) => {
  'op': 'add',
  'ref': ref,
  'kind': 'text',
  'repeat': unit,
  'count': count,
};
J _addBin(String kind, String ref, int size, int seed) => {
  'op': 'add',
  'ref': ref,
  'kind': kind,
  'size': size,
  'seed': seed,
};
J _op(String op, [String? ref]) => {'op': op, 'ref': ?ref};

List<J> _history() {
  J h(
    String name,
    int maxItems,
    List<J> ops, {
    int? budget,
    required String rule,
    String? dev,
    J? expect,
  }) => {
    'name': name,
    'maxItems': maxItems,
    'budgetBytes': ?budget,
    'ops': ops,
    'rule': rule,
    'deviation': ?dev,
    'expect': ?expect,
  };
  final fill150 = [
    for (var i = 1; i <= 31; i++) _addBin('image', 'img$i', 5 * _mib, i),
  ];
  final cases = <J>[
    h('add_inserts_at_head', 30, [
      _add('a', 'a'),
      _add('b', 'b'),
    ], rule: 'B-8.7.4'),
    h('duplicate_head_is_noop', 30, [
      _add('a', 'same'),
      _add('a', 'same'),
    ], rule: 'B-8.7.1'),
    h('readd_moves_to_head_and_evicts_old', 30, [
      _add('a', 'a'),
      _add('b', 'b'),
      _add('c', 'c'),
      _add('a', 'a'),
    ], rule: 'B-8.7.3'),
    h('fifo_cap_evicts_oldest', 10, [
      for (var i = 1; i <= 11; i++) _add('v$i', '$i'),
    ], rule: 'B-8.7.4'),
    h('remove_fires_evict', 30, [
      _add('a', 'a'),
      _add('b', 'b'),
      _add('c', 'c'),
      _op('remove', 'b'),
    ], rule: 'B-8.7.6'),
    h('clear_evicts_head_first', 30, [
      _add('a', 'a'),
      _add('b', 'b'),
      _op('clear'),
    ], rule: 'B-8.7.6'),
    h('clear_empty_is_noop', 30, [_op('clear')], rule: 'B-8.7.6'),
    h('touch_moves_to_head_without_evict', 30, [
      _add('a', 'a'),
      _add('b', 'b'),
      _add('c', 'c'),
      _op('touch', 'a'),
    ], rule: 'B-8.7.5'),
    h('touch_removed_ref_is_noop', 30, [
      _add('a', 'a'),
      _add('b', 'b'),
      _op('remove', 'a'),
      _op('touch', 'a'),
    ], rule: 'B-8.7.5'),
    h('touched_head_blocks_duplicate', 30, [
      _add('a', 'a'),
      _add('b', 'b'),
      _op('touch', 'a'),
      _add('a', 'a'),
    ], rule: 'B-8.7.1'),
    h('set_max_lower_trims_oldest_first', 30, [
      for (final r in ['a', 'b', 'c', 'd', 'e']) _add(r, r),
      {'op': 'setMax', 'n': 3},
    ], rule: 'B-8.7.7'),
    h('set_max_raise_keeps_all', 10, [
      _add('a', 'a'),
      _add('b', 'b'),
      {'op': 'setMax', 'n': 50},
      _add('c', 'c'),
    ], rule: 'B-8.7.7'),
    h(
      'budget_evicts_oldest_heavy_skips_weightless',
      30,
      [
        _addBin('image', 'img1', _mib, 1),
        _add('t', 'light text'),
        _addBin('image', 'img2', _mib, 2),
        _addBin('image', 'img3', _mib, 3),
        _addBin('image', 'img4', _mib, 4),
      ],
      budget: 3 * _mib,
      rule: 'B-8.7.2',
    ),
    h(
      'budget_exact_fit_then_oversize_rejected',
      30,
      [_addBin('image', 'fit', _mib, 1), _addBin('image', 'big', _mib + 1, 2)],
      budget: _mib,
      rule: 'B-8.6.6',
    ),
    h(
      'budget_projection_discounts_same_hash',
      30,
      [
        _addBin('image', 'img1', _mib, 1),
        _addBin('image', 'img2', _mib, 2),
        _addBin('image', 'img1', _mib, 1),
      ],
      budget: 2 * _mib,
      rule: 'B-8.7.2',
    ),
    h(
      'pdf_counts_in_budget',
      30,
      [
        _addBin('pdf', 'doc', 3 * _mib ~/ 2, 1),
        _addBin('image', 'img', _mib, 2),
      ],
      budget: 2 * _mib,
      rule: 'B-8.6.7',
    ),
    h(
      'text_weight_floor_65536',
      30,
      [
        _addBig('big1', 'a', 65536),
        _addBig('small', 'b', 65535),
        _addBig('big2', 'c', 65536),
      ],
      budget: 100000,
      rule: 'B-8.6.7',
    ),
    h(
      'text_below_floor_never_evicted',
      30,
      [
        _addBig('t1', 'a', 65535),
        _addBig('t2', 'b', 65535),
        _addBig('t3', 'c', 65535),
      ],
      budget: 65536,
      rule: 'B-8.6.7',
    ),
    h('default_budget_150mib_exact_then_evict', 50, fill150, rule: 'B-8.6.6'),
    h('image_over_25mib_cap_rejected', 30, [
      _add('t', 'keep'),
      _addBin('image', 'huge', 25 * _mib + 1, 1),
    ], rule: 'B-8.6.4'),
    h(
      'image_20mib_accepted',
      30,
      [_addBin('image', 'img', 20 * _mib, 1)],
      rule: 'B-8.6.4',
      dev: 'E25',
      expect: {
        'order': ['img'],
        'evicted': <String>[],
        'results': ['added'],
      },
    ),
    h(
      'image_at_25mib_cap_accepted',
      30,
      [_add('t', 'keep'), _addBin('image', 'img', 25 * _mib, 2)],
      rule: 'B-8.6.4',
      dev: 'E25',
      expect: {
        'order': ['img', 't'],
        'evicted': <String>[],
        'results': ['added', 'added'],
      },
    ),
    h(
      'clear_then_readd_same_content_added',
      30,
      [_add('a', 'same'), _op('clear'), _add('a', 'same')],
      rule: 'B-8.8.9',
      dev: 'E20',
      expect: {
        'order': ['a'],
        'evicted': ['a'],
        'results': ['added', 'added'],
      },
    ),
  ];
  final out = <J>[];
  for (final c in cases) {
    final name = c['name']! as String;
    final legacy = _runHistory(
      c,
      maxImageBytes: 5 * _mib,
      legacyServiceGate: true,
    ).toJson();
    final contract = _runHistory(
      c,
      maxImageBytes: 25 * _mib,
      legacyServiceGate: false,
    ).toJson();
    final dev = c['deviation'] as String?;
    if (dev != null) {
      _checkDeviation('history', name, legacy, c['expect']);
      if (jsonEncode(contract) != jsonEncode(c['expect'])) {
        _errors.add(
          'history/$name: sözleşme koşusu $contract ≠ elle beklenti ${c['expect']}',
        );
      }
    } else if (jsonEncode(contract) != jsonEncode(legacy)) {
      _errors.add(
        'history/$name: eski ve sözleşme koşusu farklı; sapma etiketi gerekli',
      );
    }
    out.add({
      'name': name,
      'maxItems': c['maxItems'],
      'budgetBytes': ?c['budgetBytes'],
      'ops': c['ops'],
      'expect': dev != null ? c['expect'] : contract,
      'deviation': ?dev,
      'source': dev == null ? 'oracle' : 'manual',
      'rule': c['rule'],
    });
  }
  return out;
}
