/// Builds user-visible track filenames without exposing internal source IDs.
///
/// File names intentionally use only the display title. Disambiguation for
/// duplicate titles is added by the download/export destination as a numeric
/// suffix, never with a provider slug or source ID.
String trackFileBase(String title) {
  // Provider names can occasionally be included in upstream display titles.
  // Keep those labels out of user-visible media filenames.
  var base = title
      .replaceAll(
        RegExp(
          r'jio[\s_-]*saavn|saavn|youtube(?:[\s_-]*(?:music|explode(?:[\s_-]*dart)?))?|googlevideo|ytimg|lrclib|radio[\s_-]*paradise|spotify',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'^[\s\-–—|:]+|[\s\-–—|:]+$'), '')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^\.+|\.+$'), '')
      .trim();
  if (base.isEmpty) base = 'Unknown track';
  final runes = base.runes.toList(growable: false);
  if (runes.length > 96) {
    base = String.fromCharCodes(runes.take(96)).trim();
  }
  return base.isEmpty ? 'Unknown track' : base;
}

/// Returns a sanitized display filename for a track and its media extension.
String trackFileName(String title, String extension) {
  var normalizedExtension = extension.trim().toLowerCase();
  if (normalizedExtension.isNotEmpty && !normalizedExtension.startsWith('.')) {
    normalizedExtension = '.$normalizedExtension';
  }
  if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(normalizedExtension)) {
    normalizedExtension = '';
  }
  return '${trackFileBase(title)}$normalizedExtension';
}
