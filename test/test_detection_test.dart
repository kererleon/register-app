import 'package:dr/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes tests in German and Italian', () {
    for (final text in [
      "Test Kapitel 3",
      "Mathematik-Schularbeit",
      "Prüfung über Optik",
      "Verifica di grammatica",
      "Compito in classe",
      "Interrogazione",
      "Tests korrigieren",
    ]) {
      expect(looksLikeTest(text), isTrue, reason: text);
    }
  });

  test('does not mistake homework for tests', () {
    for (final text in [
      "Hausaufgabe: S. 45 Nr. 3",
      "Compiti per casa: esercizi 1-5",
      "Leggere il testo a pagina 12",
      "Testo argomentativo scrivere",
      "Vokabeln lernen",
    ]) {
      expect(looksLikeTest(text), isFalse, reason: text);
    }
    expect(looksLikeHomework("Compiti per casa"), isTrue);
    expect(looksLikeHomework("Hausaufgabe"), isTrue);
  });
}
