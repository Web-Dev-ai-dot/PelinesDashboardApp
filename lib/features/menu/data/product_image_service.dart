import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

const int maxProductImageBytes = 5 * 1024 * 1024;

enum ProductImageType {
  jpeg('image/jpeg', 'jpg', CompressFormat.jpeg),
  png('image/png', 'png', CompressFormat.png),
  webp('image/webp', 'webp', CompressFormat.webp);

  const ProductImageType(this.mimeType, this.extension, this.compressFormat);
  final String mimeType;
  final String extension;
  final CompressFormat compressFormat;
}

ProductImageType? detectProductImageType(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return ProductImageType.jpeg;
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return ProductImageType.png;
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return ProductImageType.webp;
  }
  return null;
}

class ProcessedProductImage {
  const ProcessedProductImage({
    required this.bytes,
    required this.type,
    required this.filename,
  });
  final Uint8List bytes;
  final ProductImageType type;
  final String filename;
}

abstract interface class ProductImageProcessor {
  Future<ProcessedProductImage> process(XFile file);
}

class FlutterProductImageProcessor implements ProductImageProcessor {
  const FlutterProductImageProcessor();

  @override
  Future<ProcessedProductImage> process(XFile file) async {
    final Uint8List source = await file.readAsBytes();
    final ProductImageType? type = detectProductImageType(source);
    if (type == null) {
      throw const ProductImageException('Choose a JPEG, PNG, or WebP image.');
    }
    final Uint8List result = await FlutterImageCompress.compressWithList(
      source,
      minWidth: 1280,
      minHeight: 1280,
      quality: 82,
      format: type.compressFormat,
      autoCorrectionAngle: true,
    );
    if (result.isEmpty) {
      throw const ProductImageException('The image could not be processed.');
    }
    if (result.length > maxProductImageBytes) {
      throw const ProductImageException(
        'The processed image is larger than 5 MiB.',
      );
    }
    return ProcessedProductImage(
      bytes: result,
      type: type,
      filename:
          'product-${DateTime.now().microsecondsSinceEpoch}.${type.extension}',
    );
  }
}

abstract interface class ProductImagePicker {
  Future<XFile?> pick();
}

class GalleryProductImagePicker implements ProductImagePicker {
  GalleryProductImagePicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<XFile?> pick() => _picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 1280,
    maxHeight: 1280,
    imageQuality: 100,
  );
}

abstract interface class ProductStorageUploader {
  Future<void> upload({
    required Uri uploadUrl,
    required Uint8List bytes,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  });
}

class DioProductStorageUploader implements ProductStorageUploader {
  DioProductStorageUploader({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 60),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
  final Dio _dio;

  @override
  Future<void> upload({
    required Uri uploadUrl,
    required Uint8List bytes,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    await _dio.putUri<void>(
      uploadUrl,
      data: bytes,
      options: Options(
        contentType: contentType,
        headers: const <String, String>{
          'cache-control': 'max-age=3600',
          'x-upsert': 'false',
        },
        responseType: ResponseType.plain,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
      onSendProgress: onProgress,
    );
  }
}

class ProductImageException implements Exception {
  const ProductImageException(this.message);
  final String message;
  @override
  String toString() => message;
}
