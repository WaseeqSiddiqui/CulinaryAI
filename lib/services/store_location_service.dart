import 'package:flutter/services.dart';

class StoreLocation {
  const StoreLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final String address;
  final double latitude;
  final double longitude;
  final double accuracy;

  factory StoreLocation.fromMap(Map<Object?, Object?> value) {
    final address = value['address']?.toString().trim() ?? '';
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    final accuracy = value['accuracy'];
    if (address.isEmpty ||
        latitude is! num ||
        !latitude.isFinite ||
        latitude.abs() > 90 ||
        longitude is! num ||
        !longitude.isFinite ||
        longitude.abs() > 180 ||
        accuracy is! num ||
        !accuracy.isFinite ||
        accuracy < 0) {
      throw const FormatException('The phone returned an incomplete location.');
    }
    return StoreLocation(
      address: address,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      accuracy: accuracy.toDouble(),
    );
  }
}

class StoreLocationService {
  static const channel = MethodChannel(
    'com.enterprise.culinary_ai/location_permission',
  );

  Future<StoreLocation> currentAddress() async {
    final result = await channel
        .invokeMapMethod<Object?, Object?>('getCurrentLocationAddress')
        .timeout(const Duration(seconds: 30));
    if (result == null) {
      throw const FormatException('The phone did not return a location.');
    }
    return StoreLocation.fromMap(result);
  }
}
