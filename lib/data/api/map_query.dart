String mapQueryPath(
  String path, {
  required String bbox,
  Map<String, Object?> parameters = const {},
}) {
  final encodedBbox = bbox.split(',').map(Uri.encodeQueryComponent).join(',');
  final encodedParameters = parameters.entries
      .where((entry) => entry.value != null)
      .map((entry) {
        final key = Uri.encodeQueryComponent(entry.key);
        var value = Uri.encodeQueryComponent(entry.value.toString());
        if (entry.key == 'at') value = value.replaceAll('%3A', ':');
        return '$key=$value';
      })
      .join('&');
  return '$path?bbox=$encodedBbox'
      '${encodedParameters.isEmpty ? '' : '&$encodedParameters'}';
}
