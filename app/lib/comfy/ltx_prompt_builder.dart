// Structured LTX prompt pieces → one cinematic prompt for Comfy Cloud T2V.

class LtxChoice {
  const LtxChoice({
    required this.id,
    required this.label,
    required this.phrase,
  });

  final String id;
  final String label;
  /// Fragment woven into the auto prompt.
  final String phrase;
}

class LtxPowerLevel {
  const LtxPowerLevel({
    required this.id,
    required this.label,
    required this.intensity,
    required this.fx,
  });

  final String id;
  final String label;
  /// How strongly the action reads on a tiny desk screen.
  final String intensity;
  /// Extra VFX / scale language.
  final String fx;
}

const ltxCharacters = <LtxChoice>[
  LtxChoice(
    id: 'nova',
    label: 'NOVA',
    phrase: 'cute desk robot mascot NOVA, round chassis, soft LED eyes, friendly silhouette',
  ),
  LtxChoice(
    id: 'manga_hero',
    label: 'Manga hero',
    phrase: 'chibi manga hero with bold outlines, expressive eyes, compact athletic pose',
  ),
  LtxChoice(
    id: 'fox_spirit',
    label: 'Fox spirit',
    phrase: 'cute fox-spirit character with fluffy ears and tail, warm fur accents',
  ),
  LtxChoice(
    id: 'pixel_bot',
    label: 'Pixel bot',
    phrase: 'chunky pixel-art robot buddy, 8-bit inspired but smooth motion, clear shapes',
  ),
  LtxChoice(
    id: 'cat_mage',
    label: 'Cat mage',
    phrase: 'tiny cat mage in a cloak, big eyes, magical spark accents',
  ),
  LtxChoice(
    id: 'custom',
    label: 'Custom',
    phrase: '',
  ),
];

const ltxMotions = <LtxChoice>[
  LtxChoice(
    id: 'kamehameha',
    label: 'Kamehameha',
    phrase: 'fires a glowing energy beam traveling left to right across the frame',
  ),
  LtxChoice(
    id: 'wave',
    label: 'Wave',
    phrase: 'waves hello toward the camera with an open hand',
  ),
  LtxChoice(
    id: 'fist_pump',
    label: 'Fist pump',
    phrase: 'pumps a fist upward in a short celebration beat',
  ),
  LtxChoice(
    id: 'bow',
    label: 'Bow',
    phrase: 'gives a polite little bow then looks back up',
  ),
  LtxChoice(
    id: 'dash',
    label: 'Dash',
    phrase: 'dashes from left to right with a quick motion blur trail',
  ),
  LtxChoice(
    id: 'spin',
    label: 'Spin',
    phrase: 'does a quick playful spin in place then strikes a pose',
  ),
  LtxChoice(
    id: 'shield',
    label: 'Shield',
    phrase: 'raises a translucent energy shield that blooms in front of them',
  ),
  LtxChoice(
    id: 'shake_no',
    label: 'Shake no',
    phrase: 'shakes head no with a small warning gesture',
  ),
  LtxChoice(
    id: 'custom',
    label: 'Custom',
    phrase: '',
  ),
];

const ltxEmotions = <LtxChoice>[
  LtxChoice(
    id: 'cheerful',
    label: 'Cheerful',
    phrase: 'cheerful expression, bright eyes, warm body language',
  ),
  LtxChoice(
    id: 'proud',
    label: 'Proud',
    phrase: 'proud confident expression, chin up, triumphant vibe',
  ),
  LtxChoice(
    id: 'curious',
    label: 'Curious',
    phrase: 'curious tilted head, attentive gaze',
  ),
  LtxChoice(
    id: 'worried',
    label: 'Worried',
    phrase: 'worried concerned expression, careful tense posture',
  ),
  LtxChoice(
    id: 'fierce',
    label: 'Fierce',
    phrase: 'fierce focused expression, determined stance',
  ),
  LtxChoice(
    id: 'sleepy',
    label: 'Sleepy',
    phrase: 'sleepy soft half-lidded eyes, gentle slow energy',
  ),
  LtxChoice(
    id: 'mischief',
    label: 'Mischief',
    phrase: 'mischievous grin, playful spark in the eyes',
  ),
  LtxChoice(
    id: 'custom',
    label: 'Custom',
    phrase: '',
  ),
];

const ltxPowers = <LtxPowerLevel>[
  LtxPowerLevel(
    id: 'soft',
    label: 'Soft',
    intensity: 'subtle restrained motion',
    fx: 'soft glow, minimal particles, quiet energy',
  ),
  LtxPowerLevel(
    id: 'medium',
    label: 'Medium',
    intensity: 'clear readable action',
    fx: 'bright accent glow, light sparks, medium impact',
  ),
  LtxPowerLevel(
    id: 'max',
    label: 'Max',
    intensity: 'high-energy exaggerated motion for a tiny screen',
    fx: 'intense glowing aura, bold energy trails, dramatic sparks',
  ),
  LtxPowerLevel(
    id: 'custom',
    label: 'Custom',
    intensity: '',
    fx: '',
  ),
];

class LtxPromptSelection {
  const LtxPromptSelection({
    this.characterId = 'nova',
    this.motionId = 'kamehameha',
    this.emotionId = 'fierce',
    this.powerId = 'medium',
    this.styleNote = 'manga style',
    this.characterCustom = '',
    this.motionCustom = '',
    this.emotionCustom = '',
    this.powerCustom = '',
  });

  final String characterId;
  final String motionId;
  final String emotionId;
  final String powerId;
  /// Optional free-text style (e.g. "watercolor", "cyberpunk neon").
  final String styleNote;
  final String characterCustom;
  final String motionCustom;
  final String emotionCustom;
  final String powerCustom;

  LtxPromptSelection copyWith({
    String? characterId,
    String? motionId,
    String? emotionId,
    String? powerId,
    String? styleNote,
    String? characterCustom,
    String? motionCustom,
    String? emotionCustom,
    String? powerCustom,
  }) {
    return LtxPromptSelection(
      characterId: characterId ?? this.characterId,
      motionId: motionId ?? this.motionId,
      emotionId: emotionId ?? this.emotionId,
      powerId: powerId ?? this.powerId,
      styleNote: styleNote ?? this.styleNote,
      characterCustom: characterCustom ?? this.characterCustom,
      motionCustom: motionCustom ?? this.motionCustom,
      emotionCustom: emotionCustom ?? this.emotionCustom,
      powerCustom: powerCustom ?? this.powerCustom,
    );
  }

  LtxChoice get character => _pick(ltxCharacters, characterId, ltxCharacters.first);
  LtxChoice get motion => _pick(ltxMotions, motionId, ltxMotions.first);
  LtxChoice get emotion => _pick(ltxEmotions, emotionId, ltxEmotions.first);
  LtxPowerLevel get power =>
      ltxPowers.firstWhere((p) => p.id == powerId, orElse: () => ltxPowers[1]);

  String get characterPhrase {
    if (characterId == 'custom') {
      final custom = characterCustom.trim();
      return custom.isNotEmpty ? custom : 'original character, clear silhouette';
    }
    return character.phrase;
  }

  String get motionPhrase {
    if (motionId == 'custom') {
      final custom = motionCustom.trim();
      return custom.isNotEmpty ? custom : 'performs a clear readable action';
    }
    return motion.phrase;
  }

  String get emotionPhrase {
    if (emotionId == 'custom') {
      final custom = emotionCustom.trim();
      return custom.isNotEmpty ? custom : 'expressive readable emotion';
    }
    return emotion.phrase;
  }

  String get powerIntensity {
    if (powerId == 'custom') {
      final custom = powerCustom.trim();
      return custom.isNotEmpty ? custom : 'clear readable action';
    }
    return power.intensity;
  }

  String get powerFx {
    if (powerId == 'custom') {
      final custom = powerCustom.trim();
      return custom.isNotEmpty ? custom : 'readable energy accents';
    }
    return power.fx;
  }

  /// Auto-built prompt tuned for LTX + 1.47" desk readability.
  String build() {
    final style = styleNote.trim().isEmpty ? 'manga style' : styleNote.trim();
    return '$characterPhrase, $emotionPhrase, $motionPhrase, '
        '$powerIntensity, $powerFx, '
        'locked camera, simple uncluttered background, clear silhouette, '
        'readable on a tiny desk screen, $style';
  }

  Map<String, String> toPrefs() => {
        'character': characterId,
        'motion': motionId,
        'emotion': emotionId,
        'power': powerId,
        'style': styleNote,
        'character_custom': characterCustom,
        'motion_custom': motionCustom,
        'emotion_custom': emotionCustom,
        'power_custom': powerCustom,
      };

  static LtxPromptSelection fromPrefs(Map<String, String?> m) {
    return LtxPromptSelection(
      characterId: m['character'] ?? 'nova',
      motionId: m['motion'] ?? 'kamehameha',
      emotionId: m['emotion'] ?? 'fierce',
      powerId: m['power'] ?? 'medium',
      styleNote: m['style'] ?? 'manga style',
      characterCustom: m['character_custom'] ?? '',
      motionCustom: m['motion_custom'] ?? '',
      emotionCustom: m['emotion_custom'] ?? '',
      powerCustom: m['power_custom'] ?? '',
    );
  }
}

LtxChoice _pick(List<LtxChoice> list, String id, LtxChoice fallback) {
  for (final c in list) {
    if (c.id == id) return c;
  }
  return fallback;
}
