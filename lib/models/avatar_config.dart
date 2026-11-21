/// The wire keys and values are stable catalog IDs shared with the database.
enum AvatarPart {
  skin(['porcelain', 'fair', 'warm', 'tan', 'brown', 'deep']),
  hair(['bald', 'buzz', 'short', 'curly', 'long', 'braids']),
  beard(['none', 'stubble', 'mustache', 'full']),
  expression(['smile', 'grin', 'focused', 'wink', 'laugh']),
  glasses(['none', 'clear', 'shades', 'goggles']),
  headwear(['none', 'trail', 'fullface', 'cap', 'headband']),
  background(['sand', 'sky', 'rose', 'lavender', 'slate']),
  hairColor(['black', 'brown', 'blond', 'auburn', 'gray']),
  gearColor(['charcoal', 'blue', 'red', 'white', 'ochre']);

  const AvatarPart(this.options);

  final List<String> options;
}

class AvatarConfig {
  const AvatarConfig._(this._parts);

  final Map<AvatarPart, String> _parts;

  static const standard = AvatarConfig._({
    AvatarPart.skin: 'warm',
    AvatarPart.hair: 'short',
    AvatarPart.beard: 'none',
    AvatarPart.expression: 'smile',
    AvatarPart.glasses: 'none',
    AvatarPart.headwear: 'trail',
    AvatarPart.background: 'sky',
    AvatarPart.hairColor: 'brown',
    AvatarPart.gearColor: 'charcoal',
  });

  String operator [](AvatarPart part) => _parts[part]!;

  AvatarConfig withPart(AvatarPart part, String option) {
    if (!part.options.contains(option)) {
      throw ArgumentError.value(option, part.name);
    }
    return AvatarConfig._(Map.unmodifiable({..._parts, part: option}));
  }

  static AvatarConfig random(int Function(int) nextInt) => AvatarConfig._(
    Map.unmodifiable({
      for (final part in AvatarPart.values)
        part: part.options[nextInt(part.options.length)],
    }),
  );

  Map<String, Object> toJson() => {
    'v': 1,
    for (final part in AvatarPart.values) part.name: this[part],
  };

  static AvatarConfig? tryParse(Object? raw) {
    if (raw is! Map ||
        raw['v'] != 1 ||
        raw.length != AvatarPart.values.length + 1) {
      return null;
    }
    final parts = <AvatarPart, String>{};
    for (final part in AvatarPart.values) {
      final option = raw[part.name];
      if (option is! String || !part.options.contains(option)) return null;
      parts[part] = option;
    }
    return AvatarConfig._(Map.unmodifiable(parts));
  }

  /// PostgREST embeds this shared-primary-key relationship as an object.
  static AvatarConfig? fromProfile(Object? profile) {
    if (profile is! Map || profile['profile_avatars'] is! Map) return null;
    final row = profile['profile_avatars'] as Map;
    return tryParse(row['config']);
  }

  @override
  bool operator ==(Object other) =>
      other is AvatarConfig &&
      AvatarPart.values.every((part) => this[part] == other[part]);

  @override
  int get hashCode =>
      Object.hashAll(AvatarPart.values.map((part) => this[part]));
}
