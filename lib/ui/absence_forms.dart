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

import 'package:dr/actions/absences_actions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Lessons a school day can have in the Digitales Register.
const _lessonHours = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

Future<T?> _showFormSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: child,
      ),
    ),
  );
}

/// Asks for the data of an absence that will happen in the future.
Future<AddFutureAbsencePayload?> showAddFutureAbsenceSheet(
  BuildContext context, {
  String? defaultSignature,
}) {
  return _showFormSheet<AddFutureAbsencePayload>(
    context,
    _FutureAbsenceForm(defaultSignature: defaultSignature),
  );
}

/// Asks for reason and signature to justify a past absence.
/// Resolves to `(reason, signature)`.
Future<(String, String)?> showJustifyAbsenceSheet(
  BuildContext context, {
  required String fromTo,
  String? defaultSignature,
}) {
  return _showFormSheet<(String, String)>(
    context,
    _JustifyForm(fromTo: fromTo, defaultSignature: defaultSignature),
  );
}

class _SheetHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SheetHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ReasonAndSignatureFields extends StatelessWidget {
  final TextEditingController reason;
  final TextEditingController signature;
  const _ReasonAndSignatureFields({
    required this.reason,
    required this.signature,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: reason,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: "Grund",
            hintText: "z. B. Arzttermin, Krankheit, Familienfeier",
            alignLabelWithHint: true,
          ),
          validator: (v) =>
              v == null || v.trim().isEmpty ? "Bitte gib einen Grund an" : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: signature,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: "Unterschrift",
            helperText: "Vor- und Nachname der Person, die entschuldigt",
            prefixIcon: Icon(Icons.draw_outlined),
          ),
          validator: (v) => v == null || v.trim().isEmpty
              ? "Bitte unterschreibe mit deinem Namen"
              : null,
        ),
      ],
    );
  }
}

class _FutureAbsenceForm extends StatefulWidget {
  final String? defaultSignature;
  const _FutureAbsenceForm({this.defaultSignature});

  @override
  State<_FutureAbsenceForm> createState() => _FutureAbsenceFormState();
}

class _FutureAbsenceFormState extends State<_FutureAbsenceForm> {
  final _formKey = GlobalKey<FormState>();
  late final _reason = TextEditingController();
  late final _signature =
      TextEditingController(text: widget.defaultSignature ?? "");
  late DateTime _start = _today;
  late DateTime _end = _today;
  int _startHour = 1;
  int _endHour = 6;
  String? _rangeError;

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _reason.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: start ? _today : _start,
      lastDate: _today.add(const Duration(days: 365)),
      locale: const Locale("de"),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = picked;
      }
      _rangeError = null;
    });
  }

  void _submit() {
    final sameDay = _start == _end;
    if (sameDay && _endHour < _startHour) {
      setState(() => _rangeError =
          "Die letzte Stunde liegt vor der ersten. Bitte korrigiere die Stunden.");
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      AddFutureAbsencePayload(
        startDate: _start,
        endDate: _end,
        startHour: _startHour,
        endHour: _endHour,
        reason: _reason.text.trim(),
        signature: _signature.text.trim(),
      ),
    );
  }

  Widget _dateField(String label, DateTime value, {required bool start}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _pickDate(start: start),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined),
        ),
        child: Text(DateFormat("EE, d. MMM yyyy", "de").format(value)),
      ),
    );
  }

  Widget _hourField(String label, int value, ValueChanged<int> onChanged) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final h in _lessonHours)
          DropdownMenuItem(value: h, child: Text("$h. Stunde")),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() {
          onChanged(v);
          _rangeError = null;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHeader(
            title: "Abwesenheit melden",
            subtitle:
                "Melde eine geplante Abwesenheit im Voraus. Die Schule sieht sie sofort im Register.",
          ),
          Row(
            children: [
              Expanded(child: _dateField("Von", _start, start: true)),
              const SizedBox(width: 12),
              Expanded(
                  child: _hourField("Ab", _startHour, (v) => _startHour = v)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _dateField("Bis", _end, start: false)),
              const SizedBox(width: 12),
              Expanded(child: _hourField("Bis", _endHour, (v) => _endHour = v)),
            ],
          ),
          if (_rangeError != null) ...[
            const SizedBox(height: 8),
            Text(
              _rangeError!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          _ReasonAndSignatureFields(reason: _reason, signature: _signature),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send_rounded, size: 20),
            label: const Text("Abwesenheit eintragen"),
          ),
        ],
      ),
    );
  }
}

class _JustifyForm extends StatefulWidget {
  final String fromTo;
  final String? defaultSignature;
  const _JustifyForm({required this.fromTo, this.defaultSignature});

  @override
  State<_JustifyForm> createState() => _JustifyFormState();
}

class _JustifyFormState extends State<_JustifyForm> {
  final _formKey = GlobalKey<FormState>();
  late final _reason = TextEditingController();
  late final _signature =
      TextEditingController(text: widget.defaultSignature ?? "");

  @override
  void dispose() {
    _reason.dispose();
    _signature.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetHeader(title: "Absenz entschuldigen", subtitle: widget.fromTo),
          _ReasonAndSignatureFields(reason: _reason, signature: _signature),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                (_reason.text.trim(), _signature.text.trim()),
              );
            },
            icon: const Icon(Icons.check_rounded, size: 20),
            label: const Text("Entschuldigung abschicken"),
          ),
        ],
      ),
    );
  }
}
