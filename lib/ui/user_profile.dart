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

import 'package:dr/ui/holo.dart';
import 'package:dr/ui/theme.dart';
import 'package:flutter/material.dart';

class UserProfile extends StatelessWidget {
  final String name, username, role;

  const UserProfile({
    super.key,
    required this.name,
    required this.username,
    required this.role,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlowCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.accentGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.violet.withValues(alpha: 0.5),
                  blurRadius: 28,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: theme.colorScheme.surfaceContainer,
              child: GradientText(
                _initials(name),
                style: theme.textTheme.headlineMedium,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          HudLabel("$username · $role"),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r"\s+")).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return "?";
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first)
      .toUpperCase();
}
