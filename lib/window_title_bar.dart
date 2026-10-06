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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel("register/window");
Color? _lastColor;

/// Colors the Windows title bar like the app's background, so the window
/// looks like one piece (see windows/runner/flutter_window.cpp).
void syncWindowTitleBar(ThemeData theme) {
  if (!Platform.isWindows) return;
  final color = theme.colorScheme.surface;
  if (color == _lastColor) return;
  _lastColor = color;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await _channel.invokeMethod<void>("setTitleBar", {
        "r": (color.r * 255).round(),
        "g": (color.g * 255).round(),
        "b": (color.b * 255).round(),
        "dark": theme.brightness == Brightness.dark ? 1 : 0,
      });
    } on Exception {
      // Older Windows versions cannot color the title bar.
    }
  });
}
