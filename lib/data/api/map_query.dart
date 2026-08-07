String mapQueryPath(
  String path, {
  required String bbox,
  Map<String, Object?> parameters = const {},
}) {
  final encodedBbox = bbox.split(',').map(Uri.encodeQueryComponent).join(',');
  final encodedParameters = Uri(
    queryParameters: {
      for (final entry in parameters.entries)
        if (entry.value != null) entry.key: entry.value.toString(),
    },
  ).query;
  return '$path?bbox=$encodedBbox'
      '${encodedParameters.isEmpty ? '' : '&$encodedParameters'}';
}
