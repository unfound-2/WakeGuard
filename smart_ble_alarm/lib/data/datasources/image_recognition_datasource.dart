import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

/// A single object the on-device model recognised in a photo.
class RecognizedItem {
  final String label;
  final double confidence;
  const RecognizedItem(this.label, this.confidence);
}

/// Wraps Google ML Kit's on-device image labeler so alarms can be dismissed by
/// photographing a real-world object. Runs entirely offline — no network — so
/// it works the same way the standalone alarm clock does.
class ImageRecognitionDatasource {
  final ImageLabeler _labeler;

  /// [confidenceThreshold] is the minimum confidence (0..1) a label needs before
  /// the model reports it.
  ImageRecognitionDatasource({double confidenceThreshold = 0.6})
    : _labeler = ImageLabeler(
        options: ImageLabelerOptions(confidenceThreshold: confidenceThreshold),
      );

  /// Labels the photo at [path], most-confident first.
  Future<List<RecognizedItem>> labelImageFile(String path) async {
    final input = InputImage.fromFilePath(path);
    final labels = await _labeler.processImage(input);
    final items = labels
        .map((l) => RecognizedItem(l.label, l.confidence))
        .toList();
    items.sort((a, b) => b.confidence.compareTo(a.confidence));
    return items;
  }

  /// True if the photo at [path] contains something matching [targetLabel].
  Future<bool> imageMatchesLabel(String path, String targetLabel) async {
    final items = await labelImageFile(path);
    return items.any((item) => matchesLabel(item.label, targetLabel));
  }

  /// Case-insensitive, whitespace-tolerant match. A detected label counts as a
  /// match when it equals the target, or either contains the other (so "Coffee
  /// cup" matches a saved "cup", and vice-versa). Pure and side-effect free so
  /// it can be unit-tested without the native model.
  static bool matchesLabel(String detected, String target) {
    final d = detected.trim().toLowerCase();
    final t = target.trim().toLowerCase();
    if (d.isEmpty || t.isEmpty) return false;
    return d == t || d.contains(t) || t.contains(d);
  }

  /// Releases the native labeler. Call when the owning screen is disposed.
  Future<void> close() => _labeler.close();
}
