/// Route anonymisation; never retains the raw route name.
List<String>? anonymousRoute(String? name) {
  if (name == null) return null;
  final query = name.indexOf('?');
  final withoutQuery = query < 0 ? name : name.substring(0, query);
  final fragment = withoutQuery.indexOf('#');
  final path =
      fragment < 0 ? withoutQuery : withoutQuery.substring(0, fragment);
  final hashes = <String>[];
  for (final encoded in path.split('/')) {
    if (encoded.isEmpty) continue;
    var segment = encoded;
    try {
      segment = _decodeUrlPart(encoded);
    } on FormatException {
      // Like decodeURIComponent: malformed encoding keeps this segment intact.
    } on ArgumentError {
      // Some malformed encodings are reported as argument errors by Dart.
    }
    final length = segment.length > 128 ? 128 : segment.length;
    var hash = 0x811c9dc5;
    for (var index = 0; index < length; index++) {
      hash = ((hash ^ segment.codeUnitAt(index)) * 0x01000193) & 0xffffffff;
    }
    hashes.add(hash.toRadixString(16).padLeft(8, '0'));
    if (hashes.length == 12) break;
  }
  return List<String>.unmodifiable(hashes);
}

String _decodeUrlPart(String value) {
  var start = value.indexOf('%');
  if (start < 0) return value;
  final decoded = StringBuffer();
  var literalStart = 0;
  while (start >= 0) {
    decoded.write(value.substring(literalStart, start));
    var end = start;
    do {
      end += 3;
    } while (end < value.length && value.codeUnitAt(end) == 0x25);
    if (end > value.length) throw const FormatException('Truncated encoding');
    // Dart rejects literal non-ASCII in decodeComponent, unlike JS. Decode
    // only percent-encoded runs, preserving all literal UTF-16 unchanged.
    decoded.write(Uri.decodeComponent(value.substring(start, end)));
    literalStart = end;
    start = value.indexOf('%', end);
  }
  decoded.write(value.substring(literalStart));
  return decoded.toString();
}
