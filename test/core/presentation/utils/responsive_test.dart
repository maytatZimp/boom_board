import 'package:boom_board/core/presentation/utils/responsive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('clampedFraction', () {
    test('returns the raw fraction when it sits inside the bounds', () {
      expect(clampedFraction(1000, 0.25, min: 100, max: 400), 250);
    });

    test('clamps up to min', () {
      expect(clampedFraction(100, 0.1, min: 50, max: 400), 50);
    });

    test('clamps down to max', () {
      expect(clampedFraction(2000, 0.5, min: 100, max: 400), 400);
    });

    test('returns min for a zero extent', () {
      expect(clampedFraction(0, 0.5, min: 24, max: 400), 24);
    });

    test('is inclusive at both bounds', () {
      expect(clampedFraction(400, 1.0, min: 100, max: 400), 400);
      expect(clampedFraction(100, 1.0, min: 100, max: 400), 100);
    });
  });

  group('fluidTileSize', () {
    test('divides the limiting dimension by the grid units', () {
      // Height is the limiting side: 450 / 9 = 50, inside the 28..64 default.
      expect(fluidTileSize(900, 450), 50);
    });

    test('uses width when width is the smaller side', () {
      expect(fluidTileSize(450, 900), 50);
    });

    test('subtracts chrome before dividing', () {
      // (468 - 18) / 9 = 50
      expect(fluidTileSize(900, 468, chrome: 18), 50);
    });

    test('clamps to the max on a very large viewport', () {
      expect(fluidTileSize(4000, 4000), 64);
    });

    test('clamps to the min on a very small viewport', () {
      expect(fluidTileSize(100, 100), 28);
    });

    test('clamps to the min when chrome exceeds the available space', () {
      // A negative limiting extent must not produce a negative tile size.
      expect(fluidTileSize(200, 200, chrome: 500), 28);
    });

    test('honours the fractional gridUnits the board actually passes', () {
      // simple_mode_screen.dart uses `gridUnits: 8 + _kLabelFraction` rather
      // than the default 9, so the fractional path has to work.
      expect(fluidTileSize(900, 425, gridUnits: 8.5), 50);
    });

    test('respects explicit min and max overrides', () {
      expect(fluidTileSize(900, 900, min: 10, max: 20), 20);
      expect(fluidTileSize(90, 90, min: 10, max: 20), 10);
    });
  });
}
