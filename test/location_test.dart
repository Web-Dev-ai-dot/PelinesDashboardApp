import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';

void main() {
  test('parses the complete real camelCase location contract', () {
    final Location location = Location.fromJson(<String, dynamic>{
      'id': '45f835da-6c9e-4a42-a230-5d961b97da95',
      'name': 'Test Location',
      'slug': 'test-location',
      'address': '123 Main St',
      'phone': null,
      'hoursJson': <String, dynamic>{
        'mon': <String, dynamic>{'open': '09:00', 'close': '17:00'},
      },
      'isActive': true,
      'deliveryFeeCents': 500,
      'deliveryMinimumCents': 2500,
      'isAcceptingOrders': true,
      'servicePrefsJson': <String, dynamic>{'autoAccept': false},
      'hoursExtrasJson': null,
      'cateringDeliveryJson': <String, dynamic>{'enabled': true},
      'regularDeliveryJson': <String, dynamic>{'enabled': false},
      'createdAt': '2026-05-02T10:00:00.000Z',
      'updatedAt': '2026-09-03T10:00:00.000Z',
    });

    expect(location.name, 'Test Location');
    expect(location.address, '123 Main St');
    expect(location.isActive, isTrue);
    expect(location.hoursJson?['mon'], isA<Map<String, dynamic>>());
    expect(location.cateringDeliveryJson?['enabled'], isTrue);
  });

  test('rejects an invalid complex JSON field', () {
    final Map<String, dynamic> json = _locationJson();
    json['hoursJson'] = <Object>[];
    expect(() => Location.fromJson(json), throwsFormatException);
  });
}

Map<String, dynamic> _locationJson() => <String, dynamic>{
  'id': '45f835da-6c9e-4a42-a230-5d961b97da95',
  'name': 'Test Location',
  'slug': 'test-location',
  'address': null,
  'phone': null,
  'hoursJson': null,
  'isActive': true,
  'deliveryFeeCents': 0,
  'deliveryMinimumCents': 0,
  'isAcceptingOrders': true,
  'servicePrefsJson': null,
  'hoursExtrasJson': null,
  'cateringDeliveryJson': null,
  'regularDeliveryJson': null,
  'createdAt': '2026-05-02T10:00:00.000Z',
  'updatedAt': '2026-09-03T10:00:00.000Z',
};
