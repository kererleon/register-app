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

// An own background picture, chosen in the settings. It is copied into the
// app's folder and never leaves the device.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pathKey = "customBackground";
const _dimKey = "customBackgroundDim";

/// Path of the copied picture, or null for the style's own background.
final customBackground = ValueNotifier<String?>(null);

/// How much the picture is darkened (or lightened) for readability, 0–0.9.
final customBackgroundDim = ValueNotifier(0.6);

Future<void> loadCustomBackground() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_pathKey);
    if (path != null && File(path).existsSync()) customBackground.value = path;
    customBackgroundDim.value = prefs.getDouble(_dimKey) ?? 0.6;
  } on Object {
    // Keep the style's background.
  }
}

/// Lets the user pick a picture. Returns whether one was set.
Future<bool> pickCustomBackground() async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    // Larger than any screen needs; keeps the copy small.
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 85,
  );
  if (picked == null) return false;
  final dir = await getApplicationSupportDirectory();
  // A new name each time, so the image cache shows the new picture.
  final target = File(
    "${dir.path}/background_${DateTime.now().millisecondsSinceEpoch}.jpg",
  );
  await File(picked.path).copy(target.path);
  final old = customBackground.value;
  customBackground.value = target.path;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_pathKey, target.path);
  if (old != null) await _deleteQuietly(old);
  return true;
}

Future<void> removeCustomBackground() async {
  final old = customBackground.value;
  customBackground.value = null;
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_pathKey);
  if (old != null) await _deleteQuietly(old);
}

Future<void> setCustomBackgroundDim(double value) async {
  customBackgroundDim.value = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(_dimKey, value);
}

Future<void> _deleteQuietly(String path) async {
  try {
    await File(path).delete();
  } on Object {
    // Already gone.
  }
}
