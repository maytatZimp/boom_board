import 'dart:math' as math;

/// Returns [fraction] of [totalExtent], clamped to [min]..[max].
double clampedFraction(
  double totalExtent,
  double fraction, {
  required double min,
  required double max,
}) {
  return (totalExtent * fraction).clamp(min, max);
}

/// Computes a fluid square tile size for an NxN grid that fits within the
/// given available width/height, clamped to [min]/[max]. [gridUnits]
/// defaults to 9 to account for the board's 8 tiles plus its label row/column.
/// [chrome] reserves extra pixels (e.g. borders) that aren't part of the
/// grid itself but still consume the available space.
double fluidTileSize(
  double availableWidth,
  double availableHeight, {
  double gridUnits = 9,
  double chrome = 0,
  double min = 28,
  double max = 64,
}) {
  final limiting = math.min(availableWidth, availableHeight) - chrome;
  return (limiting / gridUnits).clamp(min, max);
}
