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

// Photos of the teachers, taken from the public staff page of the
// Oberschulen "J. Ph. Fallmerayer" Brixen and matched by name.

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

final _staffPage = Uri.parse("https://www.fallmerayer.it/schule/personen/");
const _cacheKey = "teacherPhotos";
const _cacheTimeKey = "teacherPhotosTime";
const _showKey = "showTeacherPhotos";
const _maxAge = Duration(days: 7);

/// Name on the staff page -> photo URL. Null until loaded.
final teacherPhotos = ValueNotifier<Map<String, String>?>(null);

/// Whether the calendar shows the photos (a setting).
final showTeacherPhotos = ValueNotifier(true);

Future<void> loadTeacherPhotoSetting() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    showTeacherPhotos.value = prefs.getBool(_showKey) ?? true;
    final custom = prefs.getString(_customKey);
    if (custom != null) {
      customTeacherImages.value =
          Map<String, String>.from(jsonDecode(custom) as Map);
    }
  } on Object {
    // Keep the default.
  }
}

Future<void> setShowTeacherPhotos(bool value) async {
  showTeacherPhotos.value = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_showKey, value);
  if (value) await ensureTeacherPhotos();
}

var _loading = false;

/// Loads the photos from the cache, or from the staff page when the cache is
/// missing or older than a week.
Future<void> ensureTeacherPhotos() async {
  if (teacherPhotos.value != null || _loading || !showTeacherPhotos.value) {
    return;
  }
  _loading = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    final time = prefs.getInt(_cacheTimeKey);
    final fresh = time != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(time)) <
            _maxAge;
    if (cached != null && fresh) {
      teacherPhotos.value = Map<String, String>.from(jsonDecode(cached) as Map);
      return;
    }
    final response = await http.get(_staffPage);
    if (response.statusCode != 200) {
      if (cached != null) {
        teacherPhotos.value =
            Map<String, String>.from(jsonDecode(cached) as Map);
      }
      return;
    }
    final photos = parseStaffPage(utf8.decode(response.bodyBytes));
    teacherPhotos.value = photos;
    await prefs.setString(_cacheKey, jsonEncode(photos));
    await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
  } on Object catch (e) {
    log("Could not load teacher photos", error: e);
  } finally {
    _loading = false;
  }
}

/// Reads "name -> photo URL" from the staff page's people lists.
@visibleForTesting
Map<String, String> parseStaffPage(String html) {
  final item = RegExp(
    r'<li class="plist-item">\s*<figure>\s*<img[^>]*src="([^"]+)"[^>]*>'
    r'\s*</figure>\s*<figcaption>\s*<p>([^<]+)</p>',
  );
  return {
    for (final m in item.allMatches(html))
      _decodeEntities(m.group(2)!.trim()):
          _staffPage.resolve(m.group(1)!).toString(),
  };
}

String _decodeEntities(String s) => s
    .replaceAll("&amp;", "&")
    .replaceAll("&#8217;", "’")
    .replaceAll("&#039;", "'")
    .replaceAll("&nbsp;", " ");

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

/// The photo of [teacher], matched by last and first name. Names on the
/// staff page come in either order, so both are compared as sets of parts.
String? photoForTeacher(Map<String, String> photos, Teacher teacher) {
  final last = _nameParts(teacher.lastName);
  final first = _nameParts(teacher.firstName);
  if (last.isEmpty) return null;
  String? lastOnlyMatch;
  var lastOnlyCount = 0;
  for (final entry in photos.entries) {
    final parts = _nameParts(entry.key);
    if (!parts.containsAll(last)) continue;
    if (first.isNotEmpty && first.any(parts.contains)) return entry.value;
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
