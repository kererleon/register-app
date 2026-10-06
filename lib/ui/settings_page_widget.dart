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

import 'dart:io';

import 'package:deleteable_tile/deleteable_tile.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/ui/autocomplete_options.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/network_protocol_page.dart';
import 'package:dr/util.dart';
import 'package:dynamic_theme/dynamic_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:dr/custom_background.dart';
import 'package:dr/teacher_photos.dart';
import 'package:dr/ui/holo.dart';
import 'package:dr/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:url_launcher/url_launcher.dart';

enum _Theme {
  light,
  dark,
  followDevice,
}

class SettingsPageWidget extends StatefulWidget {
  final OnSettingChanged<bool> onSetNoPassSaving;
  final OnSettingChanged<bool> onSetNoDataSaving;
  final OnSettingChanged<bool> onSetAskWhenDelete;
  final OnSettingChanged<bool> onSetDeleteDataOnLogout;
  final OnSettingChanged<bool> onSetShowCalendarEditNicksBar;
  final OnSettingChanged<bool> onSetShowGradesDiagram;
  final OnSettingChanged<bool> onSetShowAllSubjectsAverage;
  final OnSettingChanged<bool> onSetDashboardMarkNewOrChangedEntries;
  final OnSettingChanged<bool> onSetDashboardDeduplicateEntries;
  final OnSettingChanged<bool> onSetDarkMode;
  final OnSettingChanged<bool> onSetFollowDeviceDarkMode;
  final OnSettingChanged<bool> onSetPlatformOverride;
  final OnSettingChanged<bool> onSetDashboardColorBorders;
  final OnSettingChanged<bool> onSetCalenderColorBackground;
  final OnSettingChanged<bool> onSetDashboardColorTestsInRed;
  final OnSettingChanged<MapEntry<String, SubjectTheme>> onSetSubjectTheme;
  final OnSettingChanged<Map<String, String>> onSetSubjectNicks;
  final OnSettingChanged<List<String>> onSetIgnoreForGradesAverage;
  final VoidCallback onShowProfile;
  final SettingsViewModel vm;

  const SettingsPageWidget({
    super.key,
    required this.onSetNoPassSaving,
    required this.onSetNoDataSaving,
    required this.onSetAskWhenDelete,
    required this.onSetDeleteDataOnLogout,
    required this.onSetShowCalendarEditNicksBar,
    required this.onSetShowGradesDiagram,
    required this.onSetShowAllSubjectsAverage,
    required this.onSetDashboardMarkNewOrChangedEntries,
    required this.onSetDashboardDeduplicateEntries,
    required this.onSetDarkMode,
    required this.onSetSubjectNicks,
    required this.vm,
    required this.onSetPlatformOverride,
    required this.onSetFollowDeviceDarkMode,
    required this.onShowProfile,
    required this.onSetIgnoreForGradesAverage,
    required this.onSetDashboardColorBorders,
    required this.onSetCalenderColorBackground,
    required this.onSetSubjectTheme,
    required this.onSetDashboardColorTestsInRed,
  });

  @override
  _SettingsPageWidgetState createState() => _SettingsPageWidgetState();
}

class _SettingsPageWidgetState extends State<SettingsPageWidget> {
  final controller = AutoScrollController(suggestedRowHeight: 250);

  List<String> get subjectsWithoutNick => widget.vm.allSubjects
      .where((element) => !widget.vm.subjectNicks.keys.contains(element))
      .toList();
  List<String> get notYetIgnoredForAverageSubjects => widget.vm.allSubjects
      .where((element) => !widget.vm.ignoreForGradesAverage.contains(element))
      .toList();

  @override
  void initState() {
    if (widget.vm.showSubjectNicks) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await controller.scrollToIndex(4,
            preferPosition: AutoScrollPosition.begin);
        if (!mounted) return;
        final newValue =
            await showEditSubjectNick(context, "", "", subjectsWithoutNick);
        if (newValue != null) {
          widget.onSetSubjectNicks(
            Map.fromEntries(
                widget.vm.subjectNicks.entries.toList()..insert(0, newValue)),
          );
        }
      });
    }
    if (widget.vm.showGradesSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.scrollToIndex(3, preferPosition: AutoScrollPosition.begin);
      });
    }
    super.initState();
  }

  void _selectTheme(_Theme? theme) {
    setState(() {
      switch (theme!) {
        case _Theme.light:
          widget.onSetFollowDeviceDarkMode(false);
          widget.onSetDarkMode(false);
          break;
        case _Theme.dark:
          widget.onSetFollowDeviceDarkMode(false);
          widget.onSetDarkMode(true);
          break;
        case _Theme.followDevice:
          widget.onSetFollowDeviceDarkMode(true);
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vm.showSubjectNicks) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await controller.scrollToIndex(4,
            preferPosition: AutoScrollPosition.begin);
      });
    }
    final currentTheme = DynamicTheme.of(context)!.followDevice
        ? _Theme.followDevice
        : DynamicTheme.of(context)!.customBrightness == Brightness.dark
            ? _Theme.dark
            : _Theme.light;
    return Scaffold(
      appBar: const ResponsiveAppBar(
        title: Text("Einstellungen"),
      ),
      body: ListView(
        // Readable width on wide windows.
        padding: readablePadding(
          MediaQuery.sizeOf(context).width - (isWideLayout(context) ? 260 : 0),
        ),
        controller: controller,
        children: <Widget>[
          if (!widget.vm.demoMode) ...[
            const SizedBox(height: 8),
            HoloPanel(
              onTap: widget.onShowProfile,
              child: Row(
                children: [
                  SubjectGlyph(name: "P", color: AppColors.violet),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Profil",
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          "Email, Passwort und Benachrichtigungen",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ],
          AutoScrollTag(
            controller: controller,
            index: 0,
            key: const ObjectKey(0),
            child:
                _SettingsHeader("Anmeldung", icon: Icons.lock_outline_rounded),
          ),
          SwitchListTile.adaptive(
            title: const Text("Angemeldet bleiben"),
            subtitle: const Text("Deine Zugangsdaten werden lokal gespeichert"),
            onChanged: (bool value) {
              widget.onSetNoPassSaving(!value);
            },
            value: !widget.vm.noPassSaving,
          ),
          SwitchListTile.adaptive(
            title: const Text("Daten lokal speichern"),
            subtitle: const Text('Sehen, wann etwas eingetragen wurde'),
            onChanged: (bool value) {
              widget.onSetNoDataSaving(!value);
            },
            value: !widget.vm.noDataSaving,
          ),
          SwitchListTile.adaptive(
            title: const Text("Daten beim Ausloggen löschen"),
            onChanged: !widget.vm.noPassSaving && !widget.vm.noDataSaving
                ? (bool value) {
                    widget.onSetDeleteDataOnLogout(value);
                  }
                : null,
            value: widget.vm.deleteDataOnLogout,
          ),
          const SizedBox(height: 8),
          AutoScrollTag(
            controller: controller,
            index: 1,
            key: const ObjectKey(1),
            child: _SettingsHeader("Aussehen", icon: Icons.palette_outlined),
          ),
          const _StylePicker(),
          RadioListTile(
            value: _Theme.followDevice,
            groupValue: currentTheme,
            onChanged: _selectTheme,
            title: const Text("Geräte-Theme folgen"),
          ),
          RadioListTile(
            value: _Theme.light,
            groupValue: currentTheme,
            onChanged: _selectTheme,
            title: const Text("Hell"),
          ),
          RadioListTile(
            value: _Theme.dark,
            groupValue: currentTheme,
            onChanged: _selectTheme,
            title: const Text("Dunkel"),
          ),
          const SizedBox(height: 4),
          ExpansionTile(
            title: const Text("Fächerfarben"),
            children: [
              for (final theme in widget.vm.subjectThemes.entries)
                ListTile(
                  onTap: () async {
                    final Color? color = await showDialog(
                      context: context,
                      builder: (context) => _ColorPicker(
                        initialColor: Color(theme.value.color),
                      ),
                    );
                    if (color != null) {
                      widget.onSetSubjectTheme(
                        MapEntry(
                          theme.key,
                          theme.value.rebuild(
                            (b) => b.color = color.value,
                          ),
                        ),
                      );
                    }
                  },
                  title: Text(theme.key),
                  trailing: Container(
                    width: 50,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Color(theme.value.color),
                      //  border: Border.all(),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
            ],
          ),
          SwitchListTile.adaptive(
            title: const Text(
              "Hausaufgaben mit diesen Farben umrahmen",
            ),
            value: widget.vm.dashboardColorBorders,
            onChanged: widget.onSetDashboardColorBorders,
          ),
          SwitchListTile.adaptive(
            title: const Text(
              "Stunden im Kalender mit diesen Farben färben",
            ),
            value: widget.vm.calendarColorBackground,
            onChanged: widget.onSetCalenderColorBackground,
          ),
          SwitchListTile.adaptive(
            title: const Text(
              "Tests immer rot umrahmen",
            ),
            value: widget.vm.dashboardColorTestsInRed,
            onChanged: widget.onSetDashboardColorTestsInRed,
          ),
          const SizedBox(height: 8),
          AutoScrollTag(
            controller: controller,
            index: 2,
            key: const ObjectKey(2),
            child: _SettingsHeader("Merkheft", icon: Icons.dashboard_outlined),
          ),
          SwitchListTile.adaptive(
            title: const Text("Neue oder geänderte Einträge markieren"),
            onChanged: (bool value) {
              widget.onSetDashboardMarkNewOrChangedEntries(value);
            },
            value: widget.vm.dashboardMarkNewOrChangedEntries,
          ),
          SwitchListTile.adaptive(
            title: const Text("Doppelte Einträge ignorieren"),
            onChanged: (bool value) {
              widget.onSetDashboardDeduplicateEntries(value);
            },
            value: widget.vm.dashboardDeduplicateEntries,
          ),
          SwitchListTile.adaptive(
            title: const Text("Beim Löschen von Erinnerungen fragen"),
            onChanged: (bool value) {
              widget.onSetAskWhenDelete(value);
            },
            value: widget.vm.askWhenDelete,
          ),
          const SizedBox(height: 8),
          AutoScrollTag(
            controller: controller,
            index: 3,
            key: const ObjectKey(3),
            child: _SettingsHeader("Noten", icon: Icons.insights_rounded),
          ),
          SwitchListTile.adaptive(
            title: const Text("Noten in einem Diagramm darstellen"),
            onChanged: (bool value) {
              widget.onSetShowGradesDiagram(value);
            },
            value: widget.vm.showGradesDiagram,
          ),
          SwitchListTile.adaptive(
            title: const Text('Durchschnitt aller Fächer anzeigen'),
            onChanged: (bool value) {
              widget.onSetShowAllSubjectsAverage(value);
            },
            value: widget.vm.showAllSubjectsAverage,
          ),
          ListTile(
            title: const Text("Fächer aus dem Notendurchschnitt ausschließen"),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                final newSubject = await showDialog<String>(
                  context: context,
                  builder: (context) => AddSubject(
                    availableSubjects: notYetIgnoredForAverageSubjects,
                  ),
                );
                if (newSubject != null) {
                  widget.onSetIgnoreForGradesAverage(
                      widget.vm.ignoreForGradesAverage..add(newSubject));
                }
              },
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: widget.vm.ignoreForGradesAverage.isEmpty
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: const Padding(
              padding: EdgeInsets.only(left: 16),
              child: ListTile(
                title: Text(
                  "Kein Fach ausgeschlossen",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
            secondChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final subject in widget.vm.ignoreForGradesAverage)
                  Deleteable(
                    // don't show an animation if this is the only item
                    // in that case, the AnimatedCrossFade will do a different animation
                    showExitAnimation:
                        widget.vm.ignoreForGradesAverage.length != 1,
                    showEntryAnimation:
                        widget.vm.ignoreForGradesAverage.length != 1,
                    key: ValueKey(subject),
                    builder: (context, delete) => Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: ListTile(
                        title: Text(subject),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.close,
                          ),
                          onPressed: () async {
                            await delete();
                            widget.onSetIgnoreForGradesAverage(
                              widget.vm.ignoreForGradesAverage..remove(subject),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AutoScrollTag(
            controller: controller,
            index: 4,
            key: const ObjectKey(4),
            child: _SettingsHeader("Kalender",
                icon: Icons.calendar_month_outlined),
          ),
          ValueListenableBuilder(
            valueListenable: showTeacherPhotos,
            builder: (context, bool show, _) => SwitchListTile.adaptive(
              title: const Text("Fotos der Lehrpersonen"),
              subtitle: const Text(
                "Profilbilder in der Stunden-Detailkarte (im Brainrot-Stil auch als Hintergrund), von der Personen-Seite des Fallmerayer",
              ),
              value: show,
              onChanged: setShowTeacherPhotos,
            ),
          ),
          ExpansionTile(
            initiallyExpanded: widget.vm.showSubjectNicks,
            title: const Text("Fächerkürzel"),
            children: List.generate(
              widget.vm.subjectNicks.length + 1,
              (i) {
                if (i == 0) {
                  return ListTile(
                    trailing: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        final newValue = await showEditSubjectNick(
                          context,
                          "",
                          "",
                          subjectsWithoutNick,
                        );
                        if (newValue != null) {
                          widget.onSetSubjectNicks(
                            Map.fromEntries(
                                widget.vm.subjectNicks.entries.toList()
                                  ..insert(0, newValue)),
                          );
                        }
                      },
                    ),
                  );
                }
                i -= 1;
                final key = widget.vm.subjectNicks.entries.toList()[i].key;
                final value = widget.vm.subjectNicks[key];
                return Deleteable(
                  key: ValueKey(key),
                  builder: (context, delete) => ListTile(
                    title: Text(key),
                    subtitle: Text(value!),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () async {
                            await delete();
                            widget.onSetSubjectNicks(
                              Map.of(widget.vm.subjectNicks)..remove(key),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final newValue = await showEditSubjectNick(
                              context,
                              key,
                              value,
                              subjectsWithoutNick..add(key),
                            );
                            if (newValue != null) {
                              widget.onSetSubjectNicks(
                                Map.fromEntries(
                                  List.of(widget.vm.subjectNicks.entries)
                                    ..[i] = newValue,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SwitchListTile.adaptive(
            title: const Text("Hinweis zum Bearbeiten von Kürzeln"),
            subtitle: const Text(
                "Wird angezeigt, wenn für ein Fach kein Kürzel vorhanden ist"),
            onChanged: (bool value) {
              widget.onSetShowCalendarEditNicksBar(value);
            },
            value: widget.vm.showCalendarEditNicksBar,
          ),
          const SizedBox(height: 8),
          AutoScrollTag(
            controller: controller,
            index: 5,
            key: const ObjectKey(5),
            child: _SettingsHeader("Erweitert", icon: Icons.tune_rounded),
          ),
          if (Platform.isAndroid)
            SwitchListTile.adaptive(
              title: const Text("iOS Mode"),
              subtitle: const Text(
                  "Imitiere das Aussehen einer iOS-App (ein bisschen)"),
              onChanged: (bool value) {
                widget.onSetPlatformOverride(value);
              },
              value: DynamicTheme.of(context)!.platformOverride,
            ),
          ListTile(
            title: const Text("Netzwerkprotokoll"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (context) {
                    return NetworkProtocolPage();
                  },
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.code),
            trailing: const Icon(Icons.open_in_new),
            title: const Text("Quellcode & Downloads"),
            subtitle: const Text("github.com/kererleon/register-app"),
            onTap: () => launchUrl(
              Uri.parse("https://github.com/kererleon/register-app"),
            ),
          ),
          AboutListTile(
            icon: const Icon(Icons.info_outline),
            applicationIcon: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                "assets/icon/register_icon.png",
                width: 72,
                height: 72,
              ),
            ),
            applicationLegalese:
                "Copyright Michael Debertol und Simon Wachtler 2019-2022",
            applicationName: "Register",
            applicationVersion: appVersion,
            aboutBoxChildren: [
              const Text(
                "Eine inoffizielle App für das Digitale Register. "
                "Basiert auf digitales_register von Michael Debertol.",
              ),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: "Entwickelt von "),
                  TextSpan(
                    text: "Michael Debertol",
                    style: TextStyle(color: AppColors.cyan),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launchUrl(
                          Uri.parse("https://blog.debertol.com"),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                  ),
                  const TextSpan(text: " @ "),
                  TextSpan(
                    text: "evvvolution.com",
                    style: TextStyle(color: AppColors.cyan),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launchUrl(
                          Uri.parse("https://evvvolution.com"),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                  ),
                ]),
              ),
              const SizedBox(
                height: 8,
              ),
              const Text(
                "This is free software, and you are welcome to redistribute it under certain conditions.\n"
                "This program comes with ABSOLUTELY NO WARRANTY.",
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  child: Text(
                    "See the GNU General Public License for more details.",
                    style: TextStyle(color: AppColors.cyan),
                  ),
                  onTap: () {
                    launchUrl(
                      Uri.parse("https://www.gnu.org/licenses/gpl-3.0.html"),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
              )
            ],
            child: const Text("Über diese App"),
          ),
        ],
      ),
    );
  }

  Future<MapEntry<String, String>?> showEditSubjectNick(BuildContext context,
      String key, String? value, List<String> suggestions) async {
    return showDialog(
      context: context,
      builder: (context) => EditSubjectsNicks(
        subjectName: key,
        subjectNick: value,
        suggestions: suggestions,
      ),
    );
  }
}

class EditSubjectsNicks extends StatefulWidget {
  final String? subjectName;
  final String? subjectNick;
  final List<String>? suggestions;

  const EditSubjectsNicks(
      {super.key, this.subjectName, this.subjectNick, this.suggestions});
  @override
  _EditSubjectsNicksState createState() => _EditSubjectsNicksState();
}

class _EditSubjectsNicksState extends State<EditSubjectsNicks> {
  late TextEditingController nickController;
  late TextEditingController subjectNameController;
  late FocusNode nickFocusNode, nameFocusNode;
  late bool forNewNick;

  @override
  void initState() {
    forNewNick = widget.subjectName!.isEmpty;
    nickController = TextEditingController(text: widget.subjectNick);
    subjectNameController = TextEditingController(text: widget.subjectName)
      ..addListener(
        () {
          setState(() {});
        },
      );
    nickFocusNode = FocusNode();
    nameFocusNode = FocusNode();
    super.initState();
  }

  @override
  void dispose() {
    nickController.dispose();
    subjectNameController.dispose();
    nickFocusNode.dispose();
    nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InfoDialog(
      title: Text("Kürzel ${forNewNick ? "hinzufügen" : "bearbeiten"}"),
      content: Row(
        children: [
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Fach"),
              SizedBox(
                height: 27,
              ),
              Text("Kürzel"),
            ],
          ),
          const SizedBox(
            width: 16,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                RawAutocomplete<String>(
                  focusNode: nameFocusNode,
                  textEditingController: subjectNameController,
                  optionsBuilder: (textEditingValue) {
                    return widget.suggestions!.where((suggestion) => suggestion
                        .toLowerCase()
                        .contains(textEditingValue.text.toLowerCase()));
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return AutocompleteOptions(
                      displayStringForOption:
                          RawAutocomplete.defaultStringForOption,
                      onSelected: onSelected,
                      options: options,
                      maxOptionsHeight: 200,
                      // We can't use a LayoutBuilder to get the size inside an AlertDialog,
                      // so we hardcode it here.
                      // TODO: Remove once https://github.com/flutter/flutter/issues/78746 is fixed.
                      width: 170,
                    );
                  },
                  fieldViewBuilder: (context, textEditingController, focusNode,
                      onFieldSubmitted) {
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      onFieldSubmitted: (String value) {
                        onFieldSubmitted();
                      },
                      autofocus: subjectNameController.text.isEmpty,
                    );
                  },
                  onSelected: (_) {
                    nameFocusNode.unfocus();
                  },
                ),
                TextField(
                  controller: nickController,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  focusNode: nickFocusNode,
                  onSubmitted: (_) {
                    if (subjectNameController.text != "" &&
                        nickController.text != "") {
                      Navigator.of(context).pop(
                        MapEntry(
                          subjectNameController.text,
                          nickController.text,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text("Abbrechen"),
        ),
        ElevatedButton(
          onPressed:
              subjectNameController.text != "" && nickController.text != ""
                  ? () {
                      Navigator.of(context).pop(
                        MapEntry(
                          subjectNameController.text,
                          nickController.text,
                        ),
                      );
                    }
                  : null,
          child: const Text("Fertig"),
        ),
      ],
    );
  }
}

class AddSubject extends StatefulWidget {
  final List<String>? availableSubjects;

  const AddSubject({super.key, this.availableSubjects});
  @override
  _AddSubjectState createState() => _AddSubjectState();
}

class _AddSubjectState extends State<AddSubject> {
  late TextEditingController subjectNameController;
  late FocusNode focusNode;

  @override
  void initState() {
    super.initState();
    focusNode = FocusNode();
    subjectNameController = TextEditingController()
      ..addListener(
        () {
          setState(() {});
        },
      );
  }

  @override
  void dispose() {
    subjectNameController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InfoDialog(
      title: const Text("Fach hinzufügen"),
      content: RawAutocomplete<String>(
        focusNode: focusNode,
        textEditingController: subjectNameController,
        optionsBuilder: (textEditingValue) {
          return widget.availableSubjects!.where(
            (suggestion) => suggestion
                .toLowerCase()
                .contains(textEditingValue.text.toLowerCase()),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return AutocompleteOptions(
            displayStringForOption: RawAutocomplete.defaultStringForOption,
            onSelected: onSelected,
            options: options,
            maxOptionsHeight: 200,
            // We can't use a LayoutBuilder to get the size inside an AlertDialog,
            // so we hardcode it here.
            // TODO: Remove once https://github.com/flutter/flutter/issues/78746 is fixed.
            width: 233,
          );
        },
        fieldViewBuilder:
            (context, textEditingController, focusNode, onFieldSubmitted) {
          return TextFormField(
            controller: textEditingController,
            focusNode: focusNode,
            onFieldSubmitted: (String value) {
              onFieldSubmitted();
            },
            autofocus: subjectNameController.text.isEmpty,
          );
        },
        onSelected: (_) {
          focusNode.unfocus();
        },
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text("Abbrechen"),
        ),
        ElevatedButton(
          onPressed: subjectNameController.text != ""
              ? () {
                  Navigator.of(context).pop(subjectNameController.text);
                }
              : null,
          child: const Text("Fertig"),
        ),
      ],
    );
  }
}

class _ColorPicker extends StatefulWidget {
  final Color? initialColor;

  const _ColorPicker({this.initialColor});
  @override
  _ColorPickerState createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  Color? color;
  @override
  void initState() {
    color = widget.initialColor;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return InfoDialog(
      title: const Text("Farbe auswählen"),
      content: SingleChildScrollView(
        child: MaterialPicker(
          pickerColor: color!,
          onColorChanged: (pickedColor) {
            setState(() {
              color = pickedColor;
            });
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text("Abbrechen"),
        ),
        ElevatedButton(
          onPressed: color != widget.initialColor
              ? () {
                  Navigator.pop(context, color);
                }
              : null,
          child: const Text("Auswählen"),
        ),
      ],
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SettingsHeader(this.title, {required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.violet.withValues(alpha: 0.45),
                  blurRadius: 14,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.violet.withValues(alpha: 0.6),
                    AppColors.cyan.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Big preview cards to switch the look of the whole app.
class _StylePicker extends StatelessWidget {
  const _StylePicker();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HudLabel("Stil der App"),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              // Three cards in a row when there is room, else two per row.
              final perRow = constraints.maxWidth >= 540 ? 3 : 2;
              const gap = 12.0;
              final width =
                  (constraints.maxWidth - gap * (perRow - 1)) / perRow;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: width,
                    child: const _StyleCard(
                      style: AppStyle.holo,
                      title: "Holo",
                      subtitle: "Futuristisch, clean, leuchtend",
                      colors: [
                        Color(0xFF0A0E1A),
                        Color(0xFF7C5CFF),
                        Color(0xFF22D3EE),
                      ],
                      emoji: "✦",
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: const _StyleCard(
                      style: AppStyle.brainrot,
                      title: "Brainrot",
                      subtitle: "Skibidi, sigma, no cap",
                      colors: [
                        Color(0xFF14001F),
                        Color(0xFFFF2E93),
                        Color(0xFFB6FF00),
                      ],
                      emoji: "💀",
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: const _StyleCard(
                      style: AppStyle.israel,
                      title: "Israel",
                      subtitle: "Shalom, Sababa, Yalla",
                      colors: [
                        Color(0xFF06102E),
                        Color(0xFF0038B8),
                        Color(0xFFFFFFFF),
                      ],
                      emoji: "🇮🇱",
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: const _StyleCard(
                      style: AppStyle.clean,
                      title: "Clean",
                      subtitle: "Ruhig, modern, eine Akzentfarbe",
                      colors: [
                        Color(0xFF18181B),
                        Color(0xFF2563EB),
                        Color(0xFFE4E4E7),
                      ],
                      emoji: "○",
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: const _StyleCard(
                      style: AppStyle.glass,
                      title: "Liquid Glass",
                      subtitle: "Glas, Licht und weiche Farben",
                      colors: [
                        Color(0xFF1C2A4A),
                        Color(0xFF0A84FF),
                        Color(0xFFBF5AF2),
                      ],
                      emoji: "◐",
                    ),
                  ),
                ],
              );
            },
          ),
          if (isClean) ...[
            const SizedBox(height: 16),
            const HudLabel("Akzentfarbe"),
            const SizedBox(height: 10),
            const _AccentPicker(),
          ],
          const SizedBox(height: 20),
          const HudLabel("Eigenes Hintergrundbild"),
          const SizedBox(height: 10),
          const _BackgroundPicker(),
        ],
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  final AppStyle style;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final String emoji;

  const _StyleCard({
    required this.style,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    final selected = appStyle.value == style;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: selected ? null : () => setAppStyle(style),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient:
              selected ? LinearGradient(colors: [colors[1], colors[2]]) : null,
          border: selected
              ? null
              : Border.all(color: theme.colorScheme.outlineVariant, width: 1.5),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors[0],
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(emoji, style: TextStyle(fontSize: 22, color: colors[2])),
                  const Spacer(),
                  if (selected)
                    Icon(Icons.check_circle_rounded,
                        color: colors[2], size: 20),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final c in colors.skip(1))
                    Container(
                      width: 26,
                      height: 8,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: style == AppStyle.israel
                    ? GoogleFonts.rubik(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      )
                    : style == AppStyle.brainrot
                        ? GoogleFonts.bangers(
                            fontSize: 22,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          )
                        : GoogleFonts.sora(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The accent color of the clean look: presets and a custom color.
class _AccentPicker extends StatelessWidget {
  const _AccentPicker();

  static const _presets = [
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFDC2626),
    Color(0xFFEA580C),
    Color(0xFFCA8A04),
    Color(0xFF16A34A),
    Color(0xFF0D9488),
    Color(0xFF0891B2),
    Color(0xFF52525B),
  ];

  @override
  Widget build(BuildContext context) {
    final current = cleanAccent.value;
    final isPreset = _presets.any((c) => c.toARGB32() == current.toARGB32());
    Widget swatch(Color color, {Widget? child, VoidCallback? onTap}) {
      final selected = color.toARGB32() == current.toARGB32();
      return Semantics(
        button: true,
        selected: selected,
        child: InkResponse(
          onTap: onTap ?? () => setCleanAccent(color),
          radius: 24,
          child: Container(
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final color in _presets) swatch(color),
        swatch(
          isPreset
              ? Theme.of(context).colorScheme.surfaceContainerHigh
              : current,
          child: Icon(
            isPreset ? Icons.add_rounded : Icons.colorize_rounded,
            size: 18,
            color: isPreset
                ? Theme.of(context).colorScheme.onSurface
                : Colors.white,
          ),
          onTap: () async {
            final picked = await showDialog<Color>(
              context: context,
              builder: (context) => _ColorPicker(initialColor: current),
            );
            if (picked != null) await setCleanAccent(picked);
          },
        ),
      ],
    );
  }
}

/// Choose, darken or remove an own background picture.
class _BackgroundPicker extends StatelessWidget {
  const _BackgroundPicker();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([customBackground, customBackgroundDim]),
      builder: (context, _) {
        final path = customBackground.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (path != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image(
                        image: ResizeImage.resizeIfNeeded(
                          160,
                          null,
                          FileImage(File(path)),
                        ),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    try {
                      await pickCustomBackground();
                    } on Exception {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Das Bild konnte nicht geladen werden. Prüfe, ob Register auf deine Fotos zugreifen darf.",
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.wallpaper_rounded, size: 18),
                  label: Text(path == null ? "Bild wählen" : "Anderes Bild"),
                ),
                if (path != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: removeCustomBackground,
                    child: const Text("Entfernen"),
                  ),
                ],
              ],
            ),
            if (path != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text("Abdunkeln", style: theme.textTheme.bodyMedium),
                  Expanded(
                    child: Slider(
                      value: customBackgroundDim.value,
                      min: 0.2,
                      max: 0.9,
                      divisions: 7,
                      label: "${(customBackgroundDim.value * 100).round()} %",
                      onChanged: (v) => customBackgroundDim.value = v,
                      onChangeEnd: setCustomBackgroundDim,
                    ),
                  ),
                ],
              ),
            ] else
              Text(
                "Das Bild bleibt nur auf diesem Gerät.",
                style: theme.textTheme.bodySmall,
              ),
          ],
        );
      },
    );
  }
}
