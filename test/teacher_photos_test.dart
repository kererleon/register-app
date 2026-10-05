import 'package:dr/data.dart';
import 'package:dr/teacher_photos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the staff page and matches names in either order', () {
    const html = '''
<ul class="plist-container"><li class="plist-item"><figure><img src="../../wp-content/uploads/2020/09/Augschoell-Josef-357x500.jpg" alt=""></figure><figcaption><p>Josef Augschöll</p></figcaption></li><li class="plist-item"><figure><img src="../../wp-content/uploads/2026/10/person-belchr.webp" alt=""></figure><figcaption><p>Belloni M. Cristina</p></figcaption></li></ul>''';
    final photos = parseStaffPage(html);
    expect(photos.length, 2);
    expect(
      photos["Josef Augschöll"],
      "https://www.fallmerayer.it/wp-content/uploads/2020/09/Augschoell-Josef-357x500.jpg",
    );
    Teacher t(String first, String last) => Teacher(
          (b) => b
            ..firstName = first
            ..lastName = last,
        );
    expect(photoForTeacher(photos, t("Josef", "Augschöll")), isNotNull);
    expect(photoForTeacher(photos, t("Cristina", "Belloni")),
        contains("person-belchr"));
    expect(photoForTeacher(photos, t("Anna", "Müller")), isNull);
  });
}
