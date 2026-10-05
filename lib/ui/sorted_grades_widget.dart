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
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/container/sorted_grades_container.dart';
import 'package:dr/data.dart';
import 'package:dr/grade_forecast.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/holo.dart';
import 'package:dr/ui/theme.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

typedef ViewSubjectDetailCallback = void Function(Subject s);
typedef SetBoolCallback = void Function(bool byType);

class SortedGradesWidget extends StatelessWidget {
  final SortedGradesViewModel vm;
  final ViewSubjectDetailCallback viewSubjectDetail;
  final SetBoolCallback sortByTypeCallback, showCancelledCallback;
  final VoidCallback showGradeCalculator;

  const SortedGradesWidget({
    super.key,
    required this.vm,
    required this.viewSubjectDetail,
    required this.sortByTypeCallback,
    required this.showCancelledCallback,
    required this.showGradeCalculator,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey(vm.semester),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                avatar: const Icon(Icons.category_outlined, size: 18),
                label: const Text("Nach Art sortieren"),
                selected: vm.sortByType,
                onSelected: sortByTypeCallback,
              ),
              FilterChip(
                avatar: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text("Gelöschte anzeigen"),
                selected: vm.showCancelled!,
                onSelected: showCancelledCallback,
              ),
            ],
          ),
        ),
        SectionLabel(br("Fächer", "Fächer 📚")),
        for (final s in vm.subjects)
          SubjectWidget(
            subject: s,
            sortByType: vm.sortByType,
            viewSubjectDetail: () => viewSubjectDetail(s),
            showCancelled: vm.showCancelled!,
            semester: vm.semester,
            noInternet: vm.noInternet,
            nextTest: nextTestFor(vm.nextTests.toMap(), s),
            ignoredForAverage: vm.ignoredSubjectsForAverage.any(
              (element) => element.toLowerCase() == s.name.toLowerCase(),
            ),
          ),
        if (vm.subjects.any(
          (s) => vm.ignoredSubjectsForAverage.any(
            (element) => element.toLowerCase() == s.name.toLowerCase(),
          ),
        ))
          const ListTile(
            title: Text(
              "* Du hast dieses Fach aus dem Notendurchschnitt ausgeschlossen",
              style: TextStyle(color: Colors.grey),
            ),
          ),
        const SectionLabel("Werkzeuge"),
        HoloPanel(
          onTap: showGradeCalculator,
          child: Row(
            children: [
              SubjectGlyph(name: "Ø", color: AppColors.cyan),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Notenrechner",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      "Berechne den Durchschnitt von beliebigen Noten",
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
    );
  }
}

class SubjectWidget extends StatefulWidget {
  final bool sortByType, showCancelled, noInternet, ignoredForAverage;
  final Subject subject;
  final Semester semester;
  final VoidCallback viewSubjectDetail;
  final UpcomingTest? nextTest;

  const SubjectWidget(
      {super.key,
      required this.sortByType,
      required this.subject,
      required this.viewSubjectDetail,
      required this.showCancelled,
      required this.semester,
      required this.noInternet,
      required this.ignoredForAverage,
      this.nextTest});

  @override
  _SubjectWidgetState createState() => _SubjectWidgetState();
}

class _SubjectWidgetState extends State<SubjectWidget> {
  bool closed = true;
  @override
  void didUpdateWidget(SubjectWidget oldWidget) {
    if (oldWidget.semester != widget.semester) closed = true;
    super.didUpdateWidget(oldWidget);
  }

  Widget? _lastFetchedMessage() {
    if (closed || !widget.noInternet) {
      return null;
    }
    final formatted = formatTimeAgoPerSemester(
      noInternet: widget.noInternet,
      lastFetched: widget.subject.lastFetchedDetailed,
      semester: widget.semester,
    );
    if (formatted == null) {
      return null;
    }
    return Text(
      "$formatted.",
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.subject.detailEntries(widget.semester);
    final average = widget.subject.average(widget.semester);
    return AbsorbPointer(
      absorbing: widget.noInternet && entries == null,
      child: HoloPanel(
        padding: EdgeInsets.zero,
        accent: average == null ? null : gradeColor(average / 100),
        highlighted: !closed,
        child: ExpansionTile(
          key: ValueKey(widget.subject.id),
          title: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  text: widget.subject.name,
                  children: [
                    if (widget.ignoredForAverage)
                      const TextSpan(
                        text: " *",
                        style: TextStyle(color: Colors.grey),
                      ),
                  ],
                ),
              ),
              if (widget.nextTest != null)
                StatusPill(
                  label:
                      "Test ${DateFormat("EE dd.MM.", "de").format(widget.nextTest!.date)}",
                  color: AppColors.cyan,
                  icon: Icons.bolt_rounded,
                ),
              if (average != null && average / 100 < passMark)
                StatusPill(
                  label: br("unter 6", "Ohio 🌽", "Oy vey · unter 6"),
                  color: AppColors.danger,
                  icon: Icons.warning_amber_rounded,
                ),
            ],
          ),
          subtitle: _lastFetchedMessage(),
          tilePadding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
          leading: NeonRing(
            value: average == null ? null : average / 100,
            label: widget.subject.averageFormatted(widget.semester),
            size: 46,
          ),
          trailing:
              widget.noInternet && entries == null ? const SizedBox() : null,
          onExpansionChanged: (expansion) {
            setState(() {
              closed = !expansion;
              if (expansion) {
                widget.viewSubjectDetail();
              }
            });
          },
          initiallyExpanded: !closed,
          children: [
            if (average != null)
              _ForecastPanel(
                subject: widget.subject,
                semester: widget.semester,
                nextTest: widget.nextTest,
              ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeIn,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (currentChild != null) currentChild,
                      for (final child in previousChildren)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: child,
                        ),
                    ],
                  );
                },
                duration: const Duration(milliseconds: 200),
                child: entries != null
                    ? Column(
                        // we're using a UniqueKey here so that the framework
                        // detects a change on every rebuild. There would be no
                        // animations otherwise, as the Column as the direct child
                        // of the AnimatedSwitcher always stays the same (just different children).
                        key: UniqueKey(),
                        children: [
                          if (widget.sortByType)
                            ...Subject.sortByType(entries).entries.map(
                                  (entry) => GradeTypeWidget(
                                    typeName: entry.key,
                                    entries: entry.value
                                        .where((g) =>
                                            widget.showCancelled ||
                                            !g.cancelled)
                                        .toList(),
                                  ),
                                )
                          else
                            ...entries
                                .where(
                                    (g) => widget.showCancelled || !g.cancelled)
                                .map(
                                  (g) => g is GradeDetail
                                      ? GradeWidget(grade: g)
                                      : ObservationWidget(
                                          observation: g as Observation,
                                        ),
                                )
                        ],
                      )
                    : AnimatedLinearProgressIndicator(show: !widget.noInternet),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const lineThrough = TextStyle(decoration: TextDecoration.lineThrough);

class GradeWidget extends StatelessWidget {
  final GradeDetail grade;

  const GradeWidget({super.key, required this.grade});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        ListTile(
          title: Text(
            grade.name,
            style: grade.cancelled ? lineThrough : null,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!grade.description.isNullOrEmpty)
                Text(
                  grade.description!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              Text(
                "${DateFormat("dd.MM.yy").format(grade.date)}: ${grade.type} - ${grade.weightPercentage}%",
                style: grade.cancelled ? lineThrough : null,
              ),
              Text(
                grade.created,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (!grade.cancelledDescription.isNullOrEmpty)
                Text(
                  grade.cancelledDescription!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          trailing: NeonRing(
            value: parseGradeLabel(grade.gradeFormatted),
            label: grade.gradeFormatted,
            size: 46,
            crossedOut: grade.cancelled,
          ),
          isThreeLine: true,
        ),
        if (grade.competences.isNotEmpty)
          for (final c in grade.competences)
            CompetenceWidget(
              competence: c,
              cancelled: grade.cancelled,
            ),
      ],
    );
  }
}

class ObservationWidget extends StatelessWidget {
  final Observation observation;

  const ObservationWidget({super.key, required this.observation});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        observation.typeName,
        style: observation.cancelled ? lineThrough : null,
      ),
      subtitle: Text(
        "${DateFormat("dd.MM.yy").format(observation.date)}${observation.note.isNullOrEmpty ? "" : ": ${observation.note}"}\n${observation.created}",
        style: observation.cancelled ? lineThrough : null,
      ),
    );
  }
}

class CompetenceWidget extends StatelessWidget {
  final Competence competence;
  final bool cancelled;

  const CompetenceWidget(
      {super.key, required this.competence, required this.cancelled});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 16, right: 8),
      child: Wrap(
        children: <Widget>[
          Text(
            competence.typeName,
            style: cancelled ? lineThrough : null,
          ),
          Row(
            children: List.generate(
              5,
              (n) => Star(
                filled: n < competence.grade,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Star extends StatelessWidget {
  final bool filled;

  const Star({super.key, required this.filled});
  @override
  Widget build(BuildContext context) {
    return Icon(
      filled ? Icons.star_rounded : Icons.star_outline_rounded,
      color: filled ? AppColors.cyan : null,
      size: 20,
    );
  }
}

class GradeTypeWidget extends StatelessWidget {
  final String typeName;
  final List<DetailEntry> entries;

  const GradeTypeWidget(
      {super.key, required this.typeName, required this.entries});
  @override
  Widget build(BuildContext context) {
    final displayGrades = entries
        .map(
          (g) => g is GradeDetail
              ? GradeWidget(grade: g)
              : ObservationWidget(
                  observation: g as Observation,
                ),
        )
        .toList();
    return displayGrades.isEmpty
        ? const SizedBox()
        : ExpansionTile(
            title: HudLabel(typeName),
            initiallyExpanded: true,
            children: displayGrades,
          );
  }
}

/// "What do I need?": the grade the next test needs for a chosen average.
class _ForecastPanel extends StatefulWidget {
  final Subject subject;
  final Semester semester;
  final UpcomingTest? nextTest;

  const _ForecastPanel({
    required this.subject,
    required this.semester,
    this.nextTest,
  });

  @override
  State<_ForecastPanel> createState() => _ForecastPanelState();
}

class _ForecastPanelState extends State<_ForecastPanel> {
  double target = 7;
  int weight = 100;

  @override
  void initState() {
    super.initState();
    final average = widget.subject.average(widget.semester);
    // Start with the next full grade above the current average.
    if (average != null) {
      target = (average / 100).floorToDouble().clamp(5, 9) + 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forecast = forecastNextGrade(
      widget.subject,
      widget.semester,
      target: target,
      weightPercentage: weight,
    );
    final needed = roundUpToQuarter(forecast.required);
    final (headline, color) = switch (forecast.kind) {
      ForecastKind.safe => (
          br("Schon sicher", "Schon safe, sigma 🗿",
              "Schon sicher – Sababa! 👌"),
          AppColors.success
        ),
      ForecastKind.impossible => (
          br("Mit einem Test nicht erreichbar", "Unmöglich, L + ratio 💀",
              "Oy vey – mit einem Test nicht erreichbar 😅"),
          AppColors.danger
        ),
      ForecastKind.reachable => (
          "Mindestens ${formatGradeSteps(needed)}",
          gradeColor(needed),
        ),
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HudLabel(br("Was brauche ich?", "Was brauche ich? 🤔",
              "Was brauche ich? 🤔")),
          if (widget.nextTest != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: AppColors.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Nächster Test: ${widget.nextTest!.homework.title} am "
                    "${DateFormat("EEEE, d. MMMM", "de").format(widget.nextTest!.date)}",
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (forecast.kind == ForecastKind.reachable)
                NeonRing(
                  value: needed,
                  label: formatGradeSteps(needed),
                  size: 56,
                  stroke: 5,
                )
              else
                Icon(
                  forecast.kind == ForecastKind.safe
                      ? Icons.verified_rounded
                      : Icons.block_rounded,
                  color: color,
                  size: 40,
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style:
                          theme.textTheme.titleMedium?.copyWith(color: color),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${widget.nextTest != null ? "in diesem Test" : "im nächsten Test"} "
                      "($weight %), damit dein Durchschnitt auf "
                      "${target.toStringAsFixed(0)} kommt.",
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const HudLabel("Ziel Ø"),
              for (final t in const [6.0, 7.0, 8.0, 9.0])
                ChoiceChip(
                  label: Text(t.toStringAsFixed(0)),
                  selected: target == t,
                  onSelected: (_) => setState(() => target = t),
                  visualDensity: VisualDensity.compact,
                ),
              const SizedBox(width: 8),
              const HudLabel("Gewicht"),
              for (final w in const [50, 100])
                ChoiceChip(
                  label: Text("$w %"),
                  selected: weight == w,
                  onSelected: (_) => setState(() => weight = w),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
