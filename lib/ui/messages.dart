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

import 'dart:convert';

import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/holo.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:quill_delta/quill_delta.dart';
import 'package:quill_delta_viewer/quill_delta_viewer.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

class MessagesPage extends StatelessWidget {
  final MessagesState? state;
  final bool noInternet;
  final void Function(MessageAttachmentFile message) onOpenFile;
  final void Function(Message message) onMarkAsRead;

  const MessagesPage({
    super.key,
    required this.state,
    required this.noInternet,
    required this.onOpenFile,
    required this.onMarkAsRead,
  });
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ResponsiveAppBar(
        title: Text("Mitteilungen"),
      ),
      body: state == null
          ? noInternet
              ? const NoInternet()
              : const Center(child: CircularProgressIndicator())
          : LastFetchedOverlay(
              lastFetched: state!.lastFetched,
              noInternet: noInternet,
              child: Stack(
                children: <Widget>[
                  AnimatedLinearProgressIndicator(
                    show: state!.showMessage != null &&
                        !state!.messages.any((m) => m.id == state!.showMessage),
                  ),
                  if (state!.messages.isEmpty)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.mark_email_read_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Noch keine Mitteilungen",
                            style: Theme.of(context).textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: state!.messages.length,
                    itemBuilder: (context, i) {
                      return MessageWidget(
                        message: state!.messages[i],
                        onOpenFile: onOpenFile,
                        onMarkAsRead: onMarkAsRead,
                        noInternet: noInternet,
                        expand: state!.messages[i].id == state!.showMessage,
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

class MessageWidget extends StatefulWidget {
  final Message message;
  final void Function(MessageAttachmentFile message) onOpenFile;
  final void Function(Message message) onMarkAsRead;
  final bool noInternet;
  final bool expand;

  const MessageWidget({
    super.key,
    required this.message,
    required this.onOpenFile,
    required this.noInternet,
    required this.onMarkAsRead,
    required this.expand,
  });

  @override
  _MessageWidgetState createState() => _MessageWidgetState();
}

class _MessageWidgetState extends State<MessageWidget> {
  late final bool initiallyExpanded;
  @override
  void initState() {
    initiallyExpanded = widget.expand;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (initiallyExpanded) {
      widget.onMarkAsRead(widget.message);
    }
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isNew = widget.message.isNew || initiallyExpanded;
    Widget meta(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 72, child: HudLabel(label)),
              Expanded(child: Text(value, style: textTheme.bodyMedium)),
            ],
          ),
        );
    return HoloPanel(
      padding: EdgeInsets.zero,
      highlighted: isNew,
      accent: isNew ? AppColors.cyan : null,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        onExpansionChanged: (expanded) {
          if (expanded && widget.message.isNew) {
            widget.onMarkAsRead(widget.message);
          }
        },
        leading: SubjectGlyph(
          name: widget.message.fromName,
          color: isNew ? AppColors.cyan : AppColors.violet,
          size: 40,
        ),
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.message.subject,
                style: textTheme.titleMedium,
              ),
            ),
            if (isNew) ...[
              const SizedBox(width: 8),
              StatusPill(label: "neu", color: AppColors.cyan),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: HudLabel(
            "${DateFormat("dd.MM.yy · HH:mm").format(widget.message.timeSent)} · ${widget.message.fromName}",
          ),
        ),
        children: [
          Divider(color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 8),
          meta("Von", widget.message.fromName),
          meta("An", widget.message.recipientString),
          meta(
            "Gesendet",
            DateFormat("EEEE, d. MMMM yyyy, HH:mm", "de")
                .format(widget.message.timeSent),
          ),
          const SizedBox(height: 8),
          renderMessage(widget.message.text, context),
          if (widget.message.attachments.isNotEmpty) ...[
            const SizedBox(height: 16),
            HudLabel(
              widget.message.attachments.length > 1 ? "Anhänge" : "Anhang",
            ),
            const SizedBox(height: 8),
            for (final attachment in widget.message.attachments)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh
                      .withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.insert_drive_file_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        attachment.originalName,
                        style: textTheme.bodyMedium,
                      ),
                      trailing: TextButton.icon(
                        onPressed:
                            !attachment.fileAvailable && widget.noInternet
                                ? null
                                : () {
                                    widget.onOpenFile(attachment);
                                  },
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text("Öffnen"),
                      ),
                    ),
                    AnimatedLinearProgressIndicator(
                      show: attachment.downloading,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

Widget renderMessage(String msg, BuildContext context) {
  return QuillDeltaViewer(
      delta: Delta.fromJson(jsonDecode(msg)["ops"] as List));
}
