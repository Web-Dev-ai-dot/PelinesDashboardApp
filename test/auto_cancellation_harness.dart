import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/features/locations/data/locations_repository.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

class CancellationCurrent extends CurrentLocationController {
  CancellationCurrent(this.harness);
  final CancellationHarness harness;
  @override
  Future<Location?> build() async => harness.location;
  void replace(Location value) => state = AsyncData(value);
}

class CancellationHarness {
  CancellationHarness({Map<String, dynamic>? prefs}) {
    data = {
      'id': 'A',
      'name': 'Tualatin',
      'slug': 'tualatin',
      'isActive': true,
      'isAcceptingOrders': true,
      'deliveryFeeCents': 0,
      'deliveryMinimumCents': 0,
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-09-25T00:00:00Z',
      'servicePrefsJson': prefs,
    };
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.method == 'PATCH') {
            patches.add(
              jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>,
            );
            await patchHold?.future;
            if (applyPatch) {
              data.addAll(options.data as Map<String, dynamic>);
              data['updatedAt'] = DateTime.parse(data['updatedAt'] as String)
                  .add(const Duration(seconds: 1))
                  .toIso8601String();
            }
            if (timeout) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
              return;
            }
          } else if (options.path != 'locations') {
            reads++;
            await readHold?.future;
            if (failReadAfterPatch && patches.isNotEmpty) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,
                ),
              );
              return;
            }
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: jsonDecode(
                jsonEncode(options.path == 'locations' ? [data] : data),
              ),
            ),
          );
        },
      ),
    );
    repository = ApiLocationsRepository(ApiClient(dio: dio));
  }
  late Map<String, dynamic> data;
  late ApiLocationsRepository repository;
  List<Map<String, dynamic>> patches = [];
  int reads = 0;
  bool applyPatch = true, timeout = false, failReadAfterPatch = false;
  Completer<void>? patchHold, readHold;
  Location get location => Location.fromJson(data);
  ProviderContainer container() => ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      locationsRepositoryProvider.overrideWithValue(repository),
      currentLocationProvider.overrideWith(() => CancellationCurrent(this)),
    ],
  );
}
