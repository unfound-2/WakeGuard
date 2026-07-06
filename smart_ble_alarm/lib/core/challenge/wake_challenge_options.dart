class WakeChallengeOptions {
  static const defaultObject = 'Bathroom sink';

  static const suggestedObjects = [
    defaultObject,
    'Toothbrush',
    'Coffee maker',
    'Medication',
    'Kitchen sink',
    'Front door',
  ];

  static String cleanObjectName(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? defaultObject : trimmed;
  }
}
