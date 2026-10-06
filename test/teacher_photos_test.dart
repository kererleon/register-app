import 'package:dr/data.dart';
import 'package:dr/teacher_photos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the staff page and matches names in either order', () {
    const html = '''
<ul class="plist-container"><li class="plist-item"><figure><img src="../../wp-content/uploads/2020/09/Augschoell-Josef-357x500.jpg" alt=""></figure><figcaption><p>Josef Augschöll</p></figcaption></li><li class="plist-item"><figure><img src="../../wp-content/uploads/2026/10/person-belchr.webp" alt=""></figure><figcaption><p>Belloni M. Cristina</p></figcaption></li></ul>''';
    final photos =
        parseStaffPage(html, "https://www.fallmerayer.it/schule/personen/");
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

  test('reads lazy-loaded photos, skips placeholders and people without one',
      () {
    // Built like the staff page of the TFO Bruneck.
    String card(String img, String name) => '''
<div class="employe-box"><a href="$img" class="employe-img-box">
<img width="400" data-src="$img" alt="" src="data:image/svg+xml;base64,AAAA" class="lazyload"></a>
<a href="mailto:x@schule.suedtirol.it" class="email-box"><img data-src="/wp-content/uploads/mailicon.svg" alt="social"></a>
<h5 class="text-center"> $name</h5></div>''';
    const block = "/wp-content/uploads/2024/10/Block.png";
    final html = [
      card("/wp-content/uploads/2024/09/Kaser-Silvia.jpg", "Kaser Silvia"),
      card(block, "Vizedirektor"),
      card("/wp-content/uploads/2023/10/Egger_Philipp.jpg",
          "Egger Philipp Christoph"),
      card(block, "Lehrerkollegium"),
      '<div class="employe-box"><h5> Abfalterer Annemarie</h5></div>',
      card(block, "Sekretariat"),
      card("/wp-content/uploads/2023/10/Abfalterer_Siegfried-1.jpg",
          "Abfalterer Siegfried"),
    ].join("\n");
    final photos =
        parseStaffPage(html, "https://www.tfo-bruneck.it/mitarbeiter/");
    expect(photos.keys,
        unorderedEquals(["Kaser Silvia", "Egger Philipp Christoph", "Abfalterer Siegfried"]));
    Teacher t(String first, String last) => Teacher(
          (b) => b
            ..firstName = first
            ..lastName = last,
        );
    expect(photoForTeacher(photos, t("Philipp", "Egger")),
        "https://www.tfo-bruneck.it/wp-content/uploads/2023/10/Egger_Philipp.jpg");
    expect(photoForTeacher(photos, t("Annemarie", "Abfalterer")), isNull);
    expect(photoForTeacher(photos, t("Siegfried", "Abfalterer")),
        contains("Siegfried"));
  });

  test('names from file names when the page shows none', () {
    const html = '<img src="/bilder/Augschoell-Josef-357x500.jpg">';
    final photos = parseStaffPage(html, "https://schule.example/team/");
    expect(
      photoForTeacher(
        photos,
        Teacher((b) => b
          ..firstName = "Josef"
          ..lastName = "Augschöll"),
      ),
      isNotNull,
    );
  });
}
