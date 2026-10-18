import 'package:flutter_test/flutter_test.dart';

import 'package:sclip/ui/home_page.dart';

void main() {
  test('onay metni: filtre aktifken tüm geçmişin sileneceğini söyler', () {
    final message = HomePage.clearAllMessage(total: 27, visible: 3);
    expect(
      message,
      contains('Filtre aktif: görünen 3 değil, tümü (27) silinecek'),
    );
    expect(message, contains('Emin misin?'));
  });

  test('onay metni: filtre yokken eski metin korunur', () {
    expect(
      HomePage.clearAllMessage(total: 27, visible: 27),
      'Tüm pano geçmişi silinecek. Emin misin?',
    );
    expect(
      HomePage.clearAllMessage(total: 0, visible: 0),
      'Tüm pano geçmişi silinecek. Emin misin?',
    );
  });

  test('onay metni: her şeyi eşleyen sorgu filtre sayılmaz', () {
    // A query that happens to match every entry is not a discrepancy the
    // user needs warning about.
    expect(
      HomePage.clearAllMessage(total: 5, visible: 5),
      'Tüm pano geçmişi silinecek. Emin misin?',
    );
  });
}
