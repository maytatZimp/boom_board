import 'package:boom_board/core/data/models/mapper/player_extension.dart';
import 'package:boom_board/core/data/models/models/player_model.dart';
import 'package:boom_board/core/domain/entities/player_entity.dart';
import 'package:boom_board/features/simple_mode/data/models/mapper/socket_event_data_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PlayerModel buildModel({
    String id = 'p-1',
    bool isAlive = true,
    bool hasPositioned = false,
    bool isDisconnected = false,
  }) {
    return PlayerModel(
      id: id,
      name: 'Alice',
      isAlive: isAlive,
      hasPositioned: hasPositioned,
      isDisconnected: isDisconnected,
    );
  }

  group('PlayerModel <-> PlayerEntity', () {
    test('toEntity copies every field', () {
      final entity = buildModel(isAlive: false, hasPositioned: true, isDisconnected: true).toEntity();

      expect(entity.id, 'p-1');
      expect(entity.name, 'Alice');
      expect(entity.isAlive, isFalse);
      expect(entity.hasPositioned, isTrue);
      expect(entity.isDisconnected, isTrue);
    });

    test('round-trips model -> entity -> model without loss', () {
      final original = buildModel(id: 'p-9', hasPositioned: true);
      final result = original.toEntity().toModel();

      expect(result.id, original.id);
      expect(result.name, original.name);
      expect(result.isAlive, original.isAlive);
      expect(result.hasPositioned, original.hasPositioned);
      expect(result.isDisconnected, original.isDisconnected);
    });
  });

  group('toSimpleModeEntity', () {
    test('maps a model list and defaults hasThrowBomb to false', () {
      final players = [buildModel(id: 'a'), buildModel(id: 'b', isAlive: false)].toSimpleModeEntity();

      expect(players, hasLength(2));
      expect(players.first.id, 'a');
      expect(players.last.isAlive, isFalse);
      expect(players.every((p) => p.hasThrowBomb == false), isTrue);
    });

    test('drops position and throwOrder, which the wire model does not carry', () {
      final player = [buildModel(hasPositioned: true)].toSimpleModeEntity().single;

      expect(player.hasPositioned, isTrue);
      expect(player.x, isNull);
      expect(player.y, isNull);
      expect(player.throwOrder, isNull);
    });

    test('maps an empty list to an empty list', () {
      expect(<PlayerModel>[].toSimpleModeEntity(), isEmpty);
    });

    test('the PlayerEntity overload behaves identically', () {
      final entity = PlayerEntity(
        id: 'p-2',
        name: 'Bob',
        isAlive: true,
        hasPositioned: true,
        isDisconnected: false,
      );

      final player = [entity].toSimpleModeEntity().single;

      expect(player.id, 'p-2');
      expect(player.name, 'Bob');
      expect(player.hasPositioned, isTrue);
      expect(player.hasThrowBomb, isFalse);
    });
  });
}
