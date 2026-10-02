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

import 'package:dr/app_state.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/ui/holo.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/ui/theme.dart';
import 'package:dr/ui/user_profile.dart';
import 'package:flutter/material.dart';

class Profile extends StatelessWidget {
  final ProfileState profileState;
  final bool noInternet;
  final OnSettingChanged<bool> setSendNotificationEmails;
  final VoidCallback changeEmail;
  final VoidCallback changePass;

  const Profile({
    super.key,
    required this.profileState,
    required this.setSendNotificationEmails,
    required this.changeEmail,
    required this.changePass,
    required this.noInternet,
  });
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text("Profil"),
      ),
      body: profileState.name == null
          ? Center(
              child: noInternet
                  ? const NoInternet()
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: <Widget>[
                UserProfile(
                  name: profileState.name!,
                  username: profileState.username!,
                  role: profileState.roleName!,
                ),
                const SectionLabel("Benachrichtigungen"),
                HoloPanel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SwitchListTile.adaptive(
                    secondary: Icon(
                      Icons.mark_email_unread_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: const Text("Emails für Benachrichtigungen senden"),
                    value: profileState.sendNotificationEmails!,
                    onChanged: noInternet ? null : setSendNotificationEmails,
                  ),
                ),
                const SectionLabel("Zugang"),
                HoloPanel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.alternate_email_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: const Text("Email-Adresse ändern"),
                        subtitle: Text(
                          profileState.email!,
                          style: mono(Theme.of(context).textTheme.bodySmall),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: changeEmail,
                        enabled: !noInternet,
                      ),
                      Divider(
                        indent: 16,
                        endIndent: 16,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.key_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: const Text("Passwort ändern"),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: changePass,
                        enabled: !noInternet,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
