// Copyright (C) 2026 kererleon
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

// Photos of the teachers, taken from the public staff page of the school's
// website and matched by name. The page is found automatically from the
// address of the school's Digitales Register, or entered in the settings.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dr/data.dart';
import 'package:dr/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Staff pages that are known to work, by the school's register subdomain.
const _knownStaffPages = {
  "fallmerayer": "https://www.fallmerayer.it/schule/personen/",
  "tfo-bruneck": "https://www.tfo-bruneck.it/mitarbeiter/",
};

/// Websites of schools whose address differs from the register subdomain.
/// For all others the website is guessed ("osz-schlanders" -> osz-schlanders.it).
const _schoolWebsites = {
  "cademia": "https://www.cademia.it/de/",
  "cusanus-gymnasium": "https://www.cusanus-gymnasium.it/",
  "fs-dietenheim": "https://www.fachschule-dietenheim.it/",
  "fstisens": "https://www.fachschule-tisens.it/",
  "fs-fuerstenburg": "https://www.fachschule-fuerstenburg.it/",
  "fs-kortsch": "https://www.fachschule-kortsch.it/",
  "fslaimburg": "https://www.fachschule-laimburg.it/de",
  "fachschule-neumarkt": "https://www.fachschule-neumarkt.it/",
  "fo-brixen": "https://fo-brixen.it/",
  "fos-meran": "https://fos-meran.it/",
  "franziskanergymnasium": "https://www.franziskanergymnasium.it/",
  "sowikunstgym-bruneck": "https://www.sowikunstgymbruneck.it/",
  "gymme": "https://www.gymme.it/",
  "vogelweide": "https://www.gymnasium.bz.it/",
  "gymnasiumbrixen": "https://www.gymnasiumbrixen.it/",
  "herzjesu-institut": "https://herzjesu-institut.it/",
  "ite-raetia": "https://www.iteraetia.it/",
  "kaiserhof": "https://www.kaiserhof.berufsschule.it/de/",
  "lbs-schlanders": "https://www.schlanders.berufsschule.it/",
  "lbszuegg": "https://www.zuegg.berufsschule.it/de",
  "lhfsbruneck": "https://www.lhfs-bruneck.berufsschule.it/de/home",
  "mariengarten": "https://www.mariengarten.it/internatsschule/",
  "mhg": "https://www.mhgym.it/",
  "osz-sterzing": "https://www.oberschulzentrum-sterzing.eu/",
  "oflauer": "https://ofl-auer.it/",
  "wfoauer": "https://wfo-auer.it/",
  "rg-fob": "https://www.campusfagen.com/",
  "rgtfo-me": "https://www.rg-me.it/",
  "sogym-fotour": "https://www.sogym.bz.it/",
  "sz-sand": "https://www.sz-sandintaufers.it/",
  "tfobz": "https://www.tfobz.it/",
  "ursulinen": "https://www.ursulinen.it/",
  "vinzentinum": "https://www.vinzentinum.it/",
  "wfobz": "https://www.wfo.bz.it/",
  "wfo-bruneck": "https://www.wfo-bruneck.info/",
  "wfokafka": "https://www.wfokafka.it/",
  "wob": "https://wob.education/",
  "bbz": "https://www.bruneck.berufsschule.it/de/",
};

/// Words in links that lead to a staff page (German and Italian).
const _staffWords = [
  "mitarbeiter",
  "personen",
  "lehrpersonen",
  "lehrer",
  "kollegium",
  "personal",
  "team",
  "docenti",
  "insegnanti",
  "personale",
  "collegio",
  "staff",
];

/// Tried directly when the homepage links to nothing helpful.
const _commonPaths = [
  "mitarbeiter/",
  "personen/",
  "schule/personen/",
  "lehrpersonen/",
  "kollegium/",
  "team/",
  "personale/",
  "docenti/",
];

const _cachePrefix = "teacherPhotos_";
const _showKey = "showTeacherPhotos";
// Followed by the register host: every school has its own page.
const _customPageKey = "customStaffPage_";
const _maxAge = Duration(days: 7);
// When no page was found, look again sooner, but not on every start.
const _maxAgeNotFound = Duration(days: 3);

/// Name on the staff page -> photo URL. Null until loaded.
final teacherPhotos = ValueNotifier<Map<String, String>?>(null);

/// Whether the calendar shows the photos (a setting).
final showTeacherPhotos = ValueNotifier(true);

/// A staff page entered in the settings for the current school; replaces
/// the automatic search.
final customStaffPage = ValueNotifier<String?>(null);

/// The staff page the photos come from, or null if none was found.
final staffPageInUse = ValueNotifier<String?>(null);

/// Host of the school's Digitales Register, e.g. "tfo-bruneck.digitalesregister.it".
String? _schoolHost;

Future<void> loadTeacherPhotoSetting() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    showTeacherPhotos.value = prefs.getBool(_showKey) ?? true;
    await _migrateCustomStaffPage(prefs);
    final custom = prefs.getString(_customKey);
    if (custom != null) {
      customTeacherImages.value =
          Map<String, String>.from(jsonDecode(custom) as Map);
    }
    // The old cache only held the Fallmerayer photos.
    unawaited(prefs.remove("teacherPhotos"));
    unawaited(prefs.remove("teacherPhotosTime"));
  } on Object {
    // Keep the default.
  }
}

/// The page entered by hand used to apply to every school. Give it to the
/// school it was entered for (the one whose cache used it) and drop it.
Future<void> _migrateCustomStaffPage(SharedPreferences prefs) async {
  const oldKey = "customStaffPage";
  final old = prefs.getString(oldKey);
  if (old == null) return;
  String? owner;
  int? ownerTime;
  for (final key in prefs.getKeys()) {
    if (!key.startsWith(_cachePrefix)) continue;
    try {
      final cache = jsonDecode(prefs.getString(key)!) as Map;
      final time = cache["time"] as int;
      // The first school that used it is the one it was entered for.
      if (cache["custom"] == old && (ownerTime == null || time < ownerTime)) {
        owner = key.substring(_cachePrefix.length);
        ownerTime = time;
      }
    } on Object {
      continue;
    }
  }
  if (owner != null) await prefs.setString("$_customPageKey$owner", old);
  await prefs.remove(oldKey);
}

Future<void> setShowTeacherPhotos(bool value) async {
  showTeacherPhotos.value = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_showKey, value);
  if (value) await ensureTeacherPhotos();
}

/// Sets (or with null clears) the staff page entered by hand and reloads.
Future<void> setCustomStaffPage(String? url) async {
  final host = _schoolHost;
  if (host == null) return;
  var page = url?.trim();
  if (page != null && page.isEmpty) page = null;
  if (page != null && !page.startsWith("http")) page = "https://$page";
  customStaffPage.value = page;
  final prefs = await SharedPreferences.getInstance();
  if (page == null) {
    await prefs.remove("$_customPageKey$host");
  } else {
    await prefs.setString("$_customPageKey$host", page);
  }
  await reloadTeacherPhotos();
}

/// Forgets the cached photos of this school and loads them again.
Future<void> reloadTeacherPhotos() async {
  final host = _schoolHost;
  if (host == null) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove("$_cachePrefix$host");
  teacherPhotos.value = null;
  await ensureTeacherPhotos();
}

var _loading = false;

/// Loads the photos from the cache, or from the school's staff page when the
/// cache is missing or old. [schoolUrl] is the address of the register.
Future<void> ensureTeacherPhotos([String? schoolUrl]) async {
  final host = schoolUrl == null ? null : Uri.tryParse(schoolUrl)?.host;
  if (host != null && host.isNotEmpty && host != _schoolHost) {
    _schoolHost = host;
    teacherPhotos.value = null;
    staffPageInUse.value = null;
    customStaffPage.value = null;
  }
  final school = _schoolHost;
  if (teacherPhotos.value != null ||
      _loading ||
      !showTeacherPhotos.value ||
      school == null) {
    return;
  }
  _loading = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = "$_cachePrefix$school";
    Map? cached;
    try {
      cached = jsonDecode(prefs.getString(cacheKey) ?? "null") as Map?;
    } on Object {
      cached = null;
    }
    final custom = prefs.getString("$_customPageKey$school");
    customStaffPage.value = custom;
    if (cached != null && cached["custom"] == custom) {
      final photos = Map<String, String>.from(cached["photos"] as Map);
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(cached["time"] as int),
      );
      if (age < (photos.isEmpty ? _maxAgeNotFound : _maxAge)) {
        staffPageInUse.value = cached["page"] as String?;
        teacherPhotos.value = photos;
        return;
      }
    }
    final client = http.Client();
    _gotAnswer = false;
    String? page;
    var photos = <String, String>{};
    try {
      if (custom != null) {
        page = custom;
        final html = await _fetch(client, Uri.parse(custom));
        if (html != null) photos = parseStaffPage(html, custom);
      } else {
        final found = await findStaffPage(school, client: client);
        if (found != null) (page, photos) = found;
      }
    } finally {
      client.close();
    }
    // Offline: keep showing what we had.
    if (photos.isEmpty && cached != null && cached["custom"] == custom) {
      final old = Map<String, String>.from(cached["photos"] as Map);
      if (old.isNotEmpty) {
        staffPageInUse.value = cached["page"] as String?;
        teacherPhotos.value = old;
        return;
      }
    }
    staffPageInUse.value = photos.isEmpty ? null : page;
    teacherPhotos.value = photos;
    if (photos.isEmpty && !_gotAnswer) return; // offline: try again next time
    await prefs.setString(
      cacheKey,
      jsonEncode({
        "time": DateTime.now().millisecondsSinceEpoch,
        "page": page,
        "custom": custom,
        "photos": photos,
      }),
    );
  } on Object catch (e) {
    log("Could not load teacher photos", error: e);
  } finally {
    _loading = false;
  }
}

/// Whether any website answered during the current search. Without that
/// the phone was offline, and "nothing found" must not be remembered.
var _gotAnswer = false;

Future<String?> _fetch(http.Client client, Uri url) async {
  try {
    final response = await client
        .get(url, headers: {"User-Agent": "Mozilla/5.0 (Register-App)"})
        .timeout(const Duration(seconds: 10));
    _gotAnswer = true;
    if (response.statusCode != 200) return null;
    final type = response.headers["content-type"] ?? "text/html";
    if (!type.contains("html")) return null;
    // Real staff pages are far smaller; this keeps memory use low.
    if (response.bodyBytes.length > 4 * 1024 * 1024) return null;
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  } on Object {
    return null;
  }
}

String _bareHost(String host) =>
    host.startsWith("www.") ? host.substring(4) : host;

/// Searches the school's website for its staff page: the homepage comes from
/// a list or is guessed from the register's subdomain, then links
/// that sound like a staff page are tried. Returns the page with the most
/// photos, or null.
@visibleForTesting
Future<(String, Map<String, String>)?> findStaffPage(
  String registerHost, {
  required http.Client client,
}) async {
  final school = registerHost.split(".").first.toLowerCase();
  final known = _knownStaffPages[school];
  if (known != null) {
    final html = await _fetch(client, Uri.parse(known));
    if (html != null) {
      final photos = parseStaffPage(html, known);
      if (photos.isNotEmpty) return (known, photos);
    }
  }
  final homes = {
    if (_schoolWebsites[school] case final website?) website,
    "https://www.$school.it/",
    "https://$school.it/",
    if (school.contains("-")) "https://www.${school.replaceAll("-", "")}.it/",
  };
  for (final home in homes) {
    final homeUrl = Uri.parse(home);
    final html = await _fetch(client, homeUrl);
    if (html == null) continue;
    final candidates = <String>{
      ..._staffLinks(html, homeUrl),
      for (final path in _commonPaths) homeUrl.resolve(path).toString(),
    };
    String? best;
    var bestPhotos = <String, String>{};
    // A handful of pages at most, so the search stays light.
    for (final candidate in candidates.take(12)) {
      final page = await _fetch(client, Uri.parse(candidate));
      if (page == null) continue;
      final photos = parseStaffPage(page, candidate);
      if (photos.length > bestPhotos.length) {
        best = candidate;
        bestPhotos = photos;
      }
      if (bestPhotos.length >= 20) break;
    }
    if (best != null && bestPhotos.length >= 3) return (best, bestPhotos);
  }
  return null;
}

/// Links on [html] that lead to a staff page of the same website.
List<String> _staffLinks(String html, Uri base) {
  final link = RegExp(
    r'<a\b[^>]*href="([^"#]+)"[^>]*>(.*?)</a>',
    caseSensitive: false,
    dotAll: true,
  );
  final scored = <String, int>{};
  for (final m in link.allMatches(html)) {
    final Uri url;
    try {
      url = base.resolve(_decodeEntities(m.group(1)!.trim()));
    } on FormatException {
      continue;
    }
    if (!url.scheme.startsWith("http") ||
        _bareHost(url.host) != _bareHost(base.host)) {
      continue;
    }
    final text =
        "${url.path} ${m.group(2)!.replaceAll(RegExp("<[^>]*>"), " ")}"
            .toLowerCase();
    final score = _staffWords.where(text.contains).length;
    if (score == 0) continue;
    final clean = Uri(
      scheme: url.scheme,
      host: url.host,
      port: url.port,
      path: url.path,
    ).toString();
    scored[clean] = (scored[clean] ?? 0) + score;
  }
  return (scored.entries.toList()..sort((a, b) => b.value - a.value))
      .map((e) => e.key)
      .toList();
}

final _imgTag = RegExp(r"<img\b[^>]*>", caseSensitive: false);
final _photoPath = RegExp(r"\.(jpe?g|png|webp)$", caseSensitive: false);

final _attrPatterns = <String, RegExp>{};

String? _attr(String tag, String name) => _attrPatterns
    .putIfAbsent(
      name,
      () => RegExp(
        '\\s$name\\s*=\\s*["\']([^"\']*)["\']',
        caseSensitive: false,
      ),
    )
    .firstMatch(tag)
    ?.group(1);

/// Reads "name -> photo URL" from a staff page. Works with most layouts:
/// every photo is paired with the first text after it that looks like a
/// name, or else its alt text or file name. Images used many times (empty
/// placeholders) and icons are skipped.
@visibleForTesting
Map<String, String> parseStaffPage(String html, String pageUrl) {
  final base = Uri.parse(pageUrl);
  final photos = <({int start, int end, String? url, String alt})>[];
  final uses = <String, int>{};
  for (final m in _imgTag.allMatches(html)) {
    final tag = m.group(0)!;
    // Lazy loading keeps the real address in a data attribute.
    final src = [
      _attr(tag, "data-src"),
      _attr(tag, "data-lazy-src"),
      _attr(tag, "data-original"),
      _attr(tag, "src"),
    ].firstWhere(
      (s) => s != null && s.isNotEmpty && !s.startsWith("data:"),
      orElse: () => null,
    );
    if (src == null) continue;
    final Uri url;
    try {
      url = base.resolve(_decodeEntities(src.trim()));
    } on FormatException {
      continue;
    }
    if (!_photoPath.hasMatch(url.path)) continue; // icons, logos as SVG, …
    final address = url.toString();
    uses[address] = (uses[address] ?? 0) + 1;
    photos.add((
      start: m.start,
      end: m.end,
      url: address,
      alt: _decodeEntities(_attr(tag, "alt") ?? "").trim(),
    ));
  }
  final result = <String, String>{};
  for (var i = 0; i < photos.length; i++) {
    final photo = photos[i];
    if (uses[photo.url]! > 2) continue; // a placeholder
    final next = i + 1 < photos.length ? photos[i + 1].start : html.length;
    final between = html.substring(
      photo.end,
      next.clamp(photo.end, photo.end + 3000),
    );
    final name = between
            .split(RegExp(r"<[^>]*>"))
            .map((t) => _decodeEntities(t).replaceAll(RegExp(r"\s+"), " "))
            .map((t) => t.trim())
            .firstWhere(_looksLikeName, orElse: () => "");
    if (name.isNotEmpty) {
      result[name] = photo.url!;
    } else if (_looksLikeName(photo.alt)) {
      result[photo.alt] = photo.url!;
    } else {
      final file = Uri.decodeComponent(photo.url!.split("/").last)
          .replaceAll(_photoPath, "")
          .replaceAll(RegExp(r"-?\d+x\d+$"), "")
          .replaceAll(RegExp(r"[-_]+\d*$"), "")
          .replaceAll(RegExp(r"[-_]+"), " ")
          .trim();
      if (_looksLikeName(file, fromFile: true)) result[file] = photo.url!;
    }
  }
  return result;
}

const _nameParticles = {"von", "van", "der", "de", "di", "da", "del", "dal"};

bool _looksLikeName(String text, {bool fromFile = false}) {
  if (text.length < 4 || text.length > 60) return false;
  if (RegExp(r"[\d@:/|©]").hasMatch(text)) return false;
  final words = text.split(" ").where((w) => w.isNotEmpty).toList();
  if (words.length < 2 || words.length > 5) return false;
  return words.every(
    (w) =>
        _nameParticles.contains(w.toLowerCase()) ||
        RegExp(r"^[A-ZÄÖÜÀ-Ý][\p{L}'’.-]*$", unicode: true).hasMatch(w) ||
        (fromFile && RegExp(r"^[\p{L}'’.-]+$", unicode: true).hasMatch(w)),
  );
}

String _decodeEntities(String s) => s
    .replaceAll("&amp;", "&")
    .replaceAll("&#8217;", "’")
    .replaceAll("&#039;", "'")
    .replaceAll("&#39;", "'")
    .replaceAll("&quot;", '"')
    .replaceAll("&nbsp;", " ")
    .replaceAll("&auml;", "ä")
    .replaceAll("&ouml;", "ö")
    .replaceAll("&uuml;", "ü")
    .replaceAll("&szlig;", "ß");

const _plain = {
  "ä": "a",
  "ö": "o",
  "ü": "u",
  "ß": "ss",
  "à": "a",
  "á": "a",
  "è": "e",
  "é": "e",
  "ì": "i",
  "í": "i",
  "ò": "o",
  "ó": "o",
  "ù": "u",
  "ú": "u",
};

/// Lower-case name parts without accents and initials like "M.".
Set<String> _nameParts(String name) {
  var n = name.toLowerCase();
  _plain.forEach((k, v) => n = n.replaceAll(k, v));
  return n.split(RegExp(r"[^a-z]+")).where((part) => part.length > 1).toSet();
}

/// Like [_nameParts], but "oe" and "ö" are the same, as in file names.
Set<String> _matchParts(String name) => _nameParts(name)
    .map((p) =>
        p.replaceAll("ae", "a").replaceAll("oe", "o").replaceAll("ue", "u"))
    .toSet();

/// The photo of [teacher], matched by last and first name. Names on the
/// staff page come in either order, so both are compared as sets of parts.
String? photoForTeacher(Map<String, String> photos, Teacher teacher) {
  final last = _matchParts(teacher.lastName);
  final first = _matchParts(teacher.firstName);
  if (last.isEmpty) return null;
  String? lastOnlyMatch;
  var lastOnlyCount = 0;
  for (final entry in photos.entries) {
    final parts = _matchParts(entry.key);
    if (!parts.containsAll(last)) continue;
    if (first.isNotEmpty && first.any(parts.contains)) return entry.value;
    // Another first name on the page: a relative, not this teacher.
    if (first.isNotEmpty && parts.difference(last).isNotEmpty) continue;
    lastOnlyMatch = entry.value;
    lastOnlyCount++;
  }
  // Without a matching first name, only trust a unique last name.
  return lastOnlyCount == 1 ? lastOnlyMatch : null;
}

// --- Own pictures (brainrot style) ---

const _customKey = "customTeacherImages";

/// Pictures the user chose for teachers, keyed by [teacherKey], as paths of
/// copies in the app's own folder. Only used in the brainrot style.
final customTeacherImages = ValueNotifier<Map<String, String>>({});

String teacherKey(Teacher teacher) =>
    (_nameParts(teacher.lastName).toList()..sort()).join("-") +
    "_" +
    (_nameParts(teacher.firstName).toList()..sort()).join("-");

Future<void> _saveCustomImages(Map<String, String> images) async {
  customTeacherImages.value = images;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_customKey, jsonEncode(images));
}

/// Lets the user pick a picture for [teacher]. Returns whether one was set.
Future<bool> pickCustomTeacherImage(Teacher teacher) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1400,
    imageQuality: 85,
  );
  if (picked == null) return false;
  final dir = Directory(
    "${(await getApplicationSupportDirectory()).path}/teacher_images",
  );
  await dir.create(recursive: true);
  final key = teacherKey(teacher);
  // A new file name each time, so that the image cache shows the new one.
  final target = File(
    "${dir.path}/${key}_${DateTime.now().millisecondsSinceEpoch}.jpg",
  );
  await File(picked.path).copy(target.path);
  final images = Map.of(customTeacherImages.value);
  final old = images[key];
  images[key] = target.path;
  await _saveCustomImages(images);
  if (old != null) await _deleteQuietly(old);
  return true;
}

Future<void> removeCustomTeacherImage(Teacher teacher) async {
  final images = Map.of(customTeacherImages.value);
  final old = images.remove(teacherKey(teacher));
  await _saveCustomImages(images);
  if (old != null) await _deleteQuietly(old);
}

Future<void> _deleteQuietly(String path) async {
  try {
    await File(path).delete();
  } on Object {
    // Already gone.
  }
}

bool hasCustomTeacherImage(Teacher teacher) =>
    isBrainrot && customTeacherImages.value.containsKey(teacherKey(teacher));

/// What to show for [teacher]: the own picture in the brainrot style, else
/// the photo from the staff page (if enabled and found).
ImageProvider? teacherImage(Teacher teacher) {
  if (isBrainrot) {
    final custom = customTeacherImages.value[teacherKey(teacher)];
    if (custom != null && File(custom).existsSync()) {
      return FileImage(File(custom));
    }
  }
  final photos = teacherPhotos.value;
  if (!showTeacherPhotos.value || photos == null) return null;
  final url = photoForTeacher(photos, teacher);
  return url == null ? null : NetworkImage(url);
}

/// Everything that changes which picture a teacher has.
final teacherImageChanges = Listenable.merge(
  [teacherPhotos, showTeacherPhotos, customTeacherImages, appStyle],
);
