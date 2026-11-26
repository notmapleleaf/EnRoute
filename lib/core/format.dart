/// "350 m" or "2.1 km".
String formatDistance(double meters) {
  if (meters < 1000) {
    final rounded = (meters / 10).round() * 10;
    return '${rounded < 10 ? 10 : rounded} m';
  }
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

/// "<1 min", "4 min", "1 h 5 min".
String formatDuration(double seconds) {
  if (seconds < 60) return '<1 min';
  final totalMin = (seconds / 60).round();
  if (totalMin < 60) return '$totalMin min';
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}
