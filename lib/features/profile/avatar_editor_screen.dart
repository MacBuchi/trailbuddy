import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/errors.dart';
import '../../core/read_after_write.dart';
import '../../core/widgets/rider_avatar.dart';
import '../../l10n/l10n.dart';
import '../../models/avatar_config.dart';
import '../../models/profile.dart';
import '../coach/coach.dart';
import '../help/tab_tours.dart';
import 'avatar_labels.dart';
import 'profile_providers.dart';

const avatarEditorPath = '/profile/avatar';

class AvatarEditorScreen extends ConsumerWidget {
  const AvatarEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    final current = profile.valueOrNull;
    if (current != null) {
      return _Editor(key: ValueKey(current.id), profile: current);
    }
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.avatarEdit)),
      body: Center(
        child: profile.hasError
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.avatarLoadError),
                  TextButton(
                    onPressed: () => ref.invalidate(myProfileProvider),
                    child: Text(l.avatarRetry),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final _random = Random();
  late final AvatarConfig? _original = widget.profile.avatar;
  late AvatarConfig? _draft = _original;
  bool _saving = false;
  String? _error;

  void _set(AvatarConfig? config) => setState(() {
    _draft = config;
    _error = null;
  });

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/profile');
    }
  }

  Future<void> _save() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final fresh = await ref
          .read(myProfileProvider.notifier)
          .updateAvatar(_draft);
      if (!mounted) return;
      _close();
      if (!fresh) {
        messenger.showSnackBar(
          SnackBar(content: Text(doneOrStale(l, l.avatarSaved, fresh: fresh))),
        );
      }
    } catch (error, stack) {
      logError('Avatar speichern', error, stack);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '${l.avatarSaveError} ${friendlyError(l, error)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final choices = _draft ?? AvatarConfig.standard;
    final presets = _presets(l);
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.avatarEdit),
          automaticallyImplyLeading: !_saving,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: Column(
              children: [
                CoachAnchor(
                  id: ProfileCoach.avatarPreview,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      children: [
                        RiderAvatar(
                          key: const ValueKey('avatar-preview'),
                          name: widget.profile.username,
                          config: _draft,
                          size: 88,
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () =>
                                    _set(AvatarConfig.random(_random.nextInt)),
                          icon: const Icon(Icons.shuffle),
                          label: Text(l.avatarShuffle),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      Text(
                        l.avatarTemplates,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (label, config) in presets)
                            ChoiceChip(
                              avatar: AvatarPortrait(config: config, size: 20),
                              label: Text(label),
                              selected: _draft == config,
                              onSelected: _saving ? null : (_) => _set(config),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.padded,
                            ),
                        ],
                      ),
                      for (final part in [
                        AvatarPart.headwear,
                        AvatarPart.gearColor,
                        AvatarPart.skin,
                        AvatarPart.hair,
                        AvatarPart.hairColor,
                        AvatarPart.beard,
                        AvatarPart.glasses,
                        AvatarPart.expression,
                        AvatarPart.background,
                      ]) ...[
                        const SizedBox(height: 16),
                        Text(
                          avatarPartLabel(l, part),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final option in part.options)
                              ChoiceChip(
                                key: ValueKey('avatar-${part.name}-$option'),
                                avatar: switch (avatarSwatch(part, option)) {
                                  final color? => ExcludeSemantics(
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: color,
                                        border: Border.all(
                                          color: palette.muted,
                                        ),
                                      ),
                                    ),
                                  ),
                                  null => null,
                                },
                                label: Text(avatarOptionLabel(l, part, option)),
                                selected: choices[part] == option,
                                onSelected: _saving
                                    ? null
                                    : (_) =>
                                          _set(choices.withPart(part, option)),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.padded,
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: _saving || _draft == null
                              ? null
                              : () => _set(null),
                          child: Text(l.avatarReset),
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    children: [
                      if (_error case final error?)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            error,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _saving ? null : _close,
                            child: Text(l.commonCancel),
                          ),
                          FilledButton(
                            onPressed: _saving || _draft == _original
                                ? null
                                : _save,
                            child: _saving
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(l.commonSave),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<(String, AvatarConfig)> _presets(AppLocalizations l) => [
  (l.avatarPresetTrail, AvatarConfig.standard),
  (
    l.avatarPresetPark,
    _preset({
      'headwear': 'fullface',
      'glasses': 'goggles',
      'gearColor': 'red',
      'skin': 'brown',
      'background': 'sand',
      'hair': 'buzz',
      'hairColor': 'black',
    }),
  ),
  (
    l.avatarPresetSummit,
    _preset({
      'headwear': 'headband',
      'hair': 'braids',
      'hairColor': 'black',
      'skin': 'deep',
      'gearColor': 'ochre',
      'background': 'lavender',
      'expression': 'grin',
    }),
  ),
  (
    l.avatarPresetDust,
    _preset({
      'headwear': 'fullface',
      'gearColor': 'white',
      'skin': 'fair',
      'hair': 'curly',
      'hairColor': 'auburn',
      'background': 'rose',
    }),
  ),
  (
    l.avatarPresetGravel,
    _preset({
      'headwear': 'cap',
      'gearColor': 'ochre',
      'hair': 'long',
      'hairColor': 'blond',
      'skin': 'porcelain',
      'glasses': 'shades',
      'background': 'slate',
    }),
  ),
  (
    l.avatarPresetAfterWork,
    _preset({
      'headwear': 'none',
      'hair': 'curly',
      'hairColor': 'auburn',
      'skin': 'tan',
      'glasses': 'clear',
      'background': 'rose',
      'expression': 'wink',
    }),
  ),
  (
    l.avatarPresetTour,
    _preset({
      'gearColor': 'blue',
      'hair': 'bald',
      'hairColor': 'gray',
      'beard': 'full',
      'skin': 'fair',
      'background': 'lavender',
      'expression': 'laugh',
    }),
  ),
  (
    l.avatarPresetRoots,
    _preset({
      'gearColor': 'red',
      'hair': 'long',
      'hairColor': 'black',
      'beard': 'stubble',
      'skin': 'brown',
      'background': 'slate',
      'expression': 'focused',
    }),
  ),
];

AvatarConfig _preset(Map<String, String> changes) =>
    AvatarConfig.tryParse({...AvatarConfig.standard.toJson(), ...changes})!;
