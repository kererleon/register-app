// Copyright (C) 2021 Michael Debertol
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    as secure_storage;
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// This file contains wrappers to make initial desktop compatibility easier.

bool isDesktop() {
  return Platform.isMacOS || Platform.isLinux || Platform.isWindows;
}

secure_storage.FlutterSecureStorage getFlutterSecureStorage() {
  if (isDesktop() && !Platform.isWindows) {
    return DesktopSecureStorage();
  } else {
    return const secure_storage.FlutterSecureStorage(
      aOptions: secure_storage.AndroidOptions(
        encryptedSharedPreferences: true,
      ),
      iOptions: _iosOptions,
    );
  }
}

/// Readable after the first unlock since the iPhone was started, so the
/// background check works while the phone is locked. Still encrypted.
const _iosOptions = secure_storage.IOSOptions(
  accessibility: secure_storage.KeychainAccessibility.first_unlock,
);

/// Moves keychain items saved with the old "only while unlocked" setting to
/// [_iosOptions]. Runs once.
Future<void> migrateIosKeychain() async {
  if (!Platform.isIOS) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool("keychainMigrated") ?? false) return;
  try {
    const old = secure_storage.FlutterSecureStorage();
    const updated = secure_storage.FlutterSecureStorage(iOptions: _iosOptions);
    final items = await old.readAll();
    for (final entry in items.entries) {
      await old.delete(key: entry.key);
      await updated.write(key: entry.key, value: entry.value);
    }
    await prefs.setBool("keychainMigrated", true);
  } on Object {
    // Try again on the next start.
  }
}

// Uses a different implementation to work on desktop. We cannot switch to
// this impl for every platform because that would break backwards compatibility.
class DesktopSecureStorage implements secure_storage.FlutterSecureStorage {
  Future<Box<String>> hiveBox = getEncryptedBox();
  DesktopSecureStorage();

  // Newer versions of FlutterSecureStorage added listeners and platform checks
  // that the app does not use; they are not supported on the desktop.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  static Future<Box<String>> getEncryptedBox() async {
    final applicationDocumentDirectory = await getApplicationSupportDirectory();
    final homeDirectory =
        Directory("${applicationDocumentDirectory.path}/RegisterDB");
    if (!await homeDirectory.exists()) {
      await homeDirectory.create();
    }
    Hive.init(homeDirectory.path);
    final biometricStorage = await BiometricStorage().getStorage(
      "",
      options: StorageFileInitOptions(
        authenticationRequired: false,
      ),
    );
    var key = await biometricStorage.read();
    if (key == null) {
      key = base64UrlEncode(Hive.generateSecureKey());
      await biometricStorage.write(key);
    }
    return Hive.openBox('database',
        encryptionCipher: HiveAesCipher(base64Decode(key)));
  }

  @override
  Future<void> delete({
    required String key,
    secure_storage.IOSOptions? iOptions,
    secure_storage.AndroidOptions? aOptions,
    secure_storage.LinuxOptions? lOptions,
    secure_storage.MacOsOptions? mOptions,
    secure_storage.WindowsOptions? wOptions,
    secure_storage.WebOptions? webOptions,
  }) async {
    await (await hiveBox).delete(key);
  }

  @override
  Future<void> deleteAll({
    secure_storage.IOSOptions? iOptions,
    secure_storage.AndroidOptions? aOptions,
    secure_storage.LinuxOptions? lOptions,
    secure_storage.MacOsOptions? mOptions,
    secure_storage.WindowsOptions? wOptions,
    secure_storage.WebOptions? webOptions,
  }) async {
    await (await hiveBox).clear();
  }

  @override
  Future<String?> read({
    required String key,
    secure_storage.IOSOptions? iOptions,
    secure_storage.AndroidOptions? aOptions,
    secure_storage.LinuxOptions? lOptions,
    secure_storage.MacOsOptions? mOptions,
    secure_storage.WindowsOptions? wOptions,
    secure_storage.WebOptions? webOptions,
  }) async {
    return (await hiveBox).get(key);
  }

  @override
  Future<Map<String, String>> readAll({
    secure_storage.IOSOptions? iOptions,
    secure_storage.AndroidOptions? aOptions,
    secure_storage.LinuxOptions? lOptions,
    secure_storage.MacOsOptions? mOptions,
    secure_storage.WindowsOptions? wOptions,
    secure_storage.WebOptions? webOptions,
  }) async {
    return (await hiveBox).toMap() as Map<String, String>;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    secure_storage.IOSOptions? iOptions,
    secure_storage.AndroidOptions? aOptions,
    secure_storage.LinuxOptions? lOptions,
    secure_storage.MacOsOptions? mOptions,
    secure_storage.WindowsOptions? wOptions,
    secure_storage.WebOptions? webOptions,
  }) async {
    return (await hiveBox).put(key, value!);
  }

  @override
  Future<bool> containsKey({
    required String key,
    secure_storage.IOSOptions? iOptions,
    secure_storage.AndroidOptions? aOptions,
    secure_storage.LinuxOptions? lOptions,
    secure_storage.MacOsOptions? mOptions,
    secure_storage.WindowsOptions? wOptions,
    secure_storage.WebOptions? webOptions,
  }) async {
    return (await hiveBox).containsKey(key);
  }

  @override
  secure_storage.AndroidOptions get aOptions => throw UnimplementedError();

  @override
  secure_storage.IOSOptions get iOptions => throw UnimplementedError();

  @override
  secure_storage.LinuxOptions get lOptions => throw UnimplementedError();

  @override
  secure_storage.MacOsOptions get mOptions => throw UnimplementedError();

  @override
  secure_storage.WindowsOptions get wOptions => throw UnimplementedError();

  @override
  secure_storage.WebOptions get webOptions => throw UnimplementedError();
}
