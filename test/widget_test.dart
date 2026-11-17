import 'package:flutter_test/flutter_test.dart';
import 'package:munazir/data.dart';

void main() {
  test('normalisation arabe', () {
    expect(norm('ٱلرَّحْمَٰنِ'), norm('الرحمن'));
    expect(norm('الصَّلَاةَ'), norm('الصلاه'));
    expect(norm('إِيَّاكَ'), norm('اياك'));
  });

  test('chargement des données', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppData.load();
    final d = AppData.I;
    expect(d.surahs.length, 114);
    expect(d.surahs.fold<int>(0, (a, s) => a + s.ayat.length), 6236);
    for (final o in d.objections) {
      for (final r in o.refs) {
        expect(d.validRef(r), isTrue);
      }
    }
    for (final h in d.hadiths) {
      for (final r in h.refs) {
        expect(d.validRef(r), isTrue);
      }
    }
    expect(d.parseRefQuery('2:255')?.ayah, 255);
    expect(d.parseRefQuery('البقرة 255')?.surah, 2);
    expect(d.searchQuran('اتخذوا هذا القرآن مهجورا').first.surah, 25);
  });
}
