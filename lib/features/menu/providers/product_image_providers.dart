import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../auth/providers/auth_providers.dart';
import '../../locations/providers/locations_providers.dart';
import '../data/menu_repository.dart';
import '../data/product_image_service.dart';
import '../models/menu_models.dart';
import 'menu_providers.dart';

typedef ProductImageContext = ({
  String locationId,
  String locationSlug,
  MenuKind kind,
  String categoryId,
  String productId,
});

final productImagePickerProvider = Provider<ProductImagePicker>(
  (ref) => GalleryProductImagePicker(),
);
final productImageProcessorProvider = Provider<ProductImageProcessor>(
  (ref) => const FlutterProductImageProcessor(),
);
final productStorageUploaderProvider = Provider<ProductStorageUploader>(
  (ref) => DioProductStorageUploader(),
);

enum ProductImagePhase {
  idle,
  picking,
  processing,
  requestingUploadUrl,
  uploading,
  updatingProduct,
  reconciling,
  success,
  error,
}

class ProductImageState {
  const ProductImageState({
    this.phase = ProductImagePhase.idle,
    this.message,
    this.progress,
    this.pendingPublicUrl,
  });
  final ProductImagePhase phase;
  final String? message;
  final double? progress;
  final String? pendingPublicUrl;
  bool get isBusy => switch (phase) {
    ProductImagePhase.picking ||
    ProductImagePhase.processing ||
    ProductImagePhase.requestingUploadUrl ||
    ProductImagePhase.uploading ||
    ProductImagePhase.updatingProduct ||
    ProductImagePhase.reconciling => true,
    _ => false,
  };
  bool get canRetryPatch =>
      phase == ProductImagePhase.error && pendingPublicUrl != null;
}

final productImageMutationProvider = NotifierProvider.autoDispose
    .family<ProductImageController, ProductImageState, ProductImageContext>(
      ProductImageController.new,
    );

class ProductImageController extends Notifier<ProductImageState> {
  ProductImageController(this.context);
  final ProductImageContext context;

  @override
  ProductImageState build() => const ProductImageState();

  Future<bool> changeImage() async {
    if (state.isBusy) return false;
    if (!await _validateContext()) return false;
    state = const ProductImageState(phase: ProductImagePhase.picking);

    try {
      final file = await ref.read(productImagePickerProvider).pick();
      if (file == null) {
        state = const ProductImageState();
        return false;
      }
      state = const ProductImageState(phase: ProductImagePhase.processing);
      final ProcessedProductImage image = await ref
          .read(productImageProcessorProvider)
          .process(file);
      if (image.bytes.isEmpty || image.bytes.length > maxProductImageBytes) {
        throw const ProductImageException(
          'The processed image must be between 1 byte and 5 MiB.',
        );
      }

      state = const ProductImageState(
        phase: ProductImagePhase.requestingUploadUrl,
      );
      final ProductUploadTarget target = await ref
          .read(menuRepositoryProvider)
          .createProductUploadTarget(
            filename: image.filename,
            contentType: image.type.mimeType,
            sizeBytes: image.bytes.length,
          );

      state = const ProductImageState(
        phase: ProductImagePhase.uploading,
        progress: 0,
      );
      await ref
          .read(productStorageUploaderProvider)
          .upload(
            uploadUrl: target.uploadUrl,
            bytes: image.bytes,
            contentType: image.type.mimeType,
            onProgress: (int sent, int total) {
              if (total > 0 && state.phase == ProductImagePhase.uploading) {
                state = ProductImageState(
                  phase: ProductImagePhase.uploading,
                  progress: sent / total,
                );
              }
            },
          );
      return await _patchAndReconcile(target.publicUrl.toString());
    } on ApiException catch (error) {
      await _apiError(error);
    } on ProductImageException catch (error) {
      state = ProductImageState(
        phase: ProductImagePhase.error,
        message: error.message,
      );
    } on DioException {
      state = const ProductImageState(
        phase: ProductImagePhase.error,
        message: 'The storage upload failed or timed out. The product image was not changed.',
      );
    } on Object {
      state = const ProductImageState(
        phase: ProductImagePhase.error,
        message: 'The image could not be changed.',
      );
    }
    return false;
  }

  Future<bool> retryProductUpdate() async {
    final String? publicUrl = state.pendingPublicUrl;
    if (state.isBusy || publicUrl == null) return false;
    if (!await _validateContext()) return false;
    return _patchAndReconcile(publicUrl);
  }

  Future<bool> _patchAndReconcile(String publicUrl) async {
    state = ProductImageState(
      phase: ProductImagePhase.updatingProduct,
      pendingPublicUrl: publicUrl,
    );
    try {
      await ref
          .read(menuRepositoryProvider)
          .updateProductImage(context.productId, publicUrl);
      return await _reconcile(publicUrl);
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
      if (_ambiguous(error)) return _reconcile(publicUrl, patchError: error);
      state = ProductImageState(
        phase: ProductImagePhase.error,
        pendingPublicUrl: publicUrl,
        message:
            '${error.message} The file may remain unused in storage; retry saving without uploading it again.',
      );
      return false;
    } on Object {
      state = ProductImageState(
        phase: ProductImagePhase.error,
        pendingPublicUrl: publicUrl,
        message: 'The image was uploaded but the product could not be updated. Retry saving without uploading again.',
      );
      return false;
    }
  }

  Future<bool> _reconcile(String publicUrl, {ApiException? patchError}) async {
    state = ProductImageState(
      phase: ProductImagePhase.reconciling,
      pendingPublicUrl: publicUrl,
    );
    try {
      final product = await ref
          .read(menuRepositoryProvider)
          .getProduct(context.productId);
      if (product.categoryId == context.categoryId &&
          product.imageUrl == publicUrl) {
        state = const ProductImageState(
          phase: ProductImagePhase.success,
          message: 'Product image updated.',
        );
        _refresh();
        return true;
      }
      state = ProductImageState(
        phase: ProductImagePhase.error,
        pendingPublicUrl: publicUrl,
        message: patchError == null
            ? 'The saved product does not contain the uploaded image URL.'
            : '${patchError.message} The update was not confirmed; retry saving manually.',
      );
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
      state = ProductImageState(
        phase: ProductImagePhase.error,
        pendingPublicUrl: publicUrl,
        message: '${error.message} The product could not be verified.',
      );
    } on Object {
      state = ProductImageState(
        phase: ProductImagePhase.error,
        pendingPublicUrl: publicUrl,
        message: 'The product could not be verified after upload.',
      );
    }
    return false;
  }

  Future<bool> _validateContext() async {
    try {
      final location = await ref.read(currentLocationProvider.future);
      if (location == null ||
          location.id != context.locationId ||
          location.slug != context.locationSlug) {
        throw const MenuContextChangedException();
      }
      final category = await ref
          .read(menuRepositoryProvider)
          .getCategory(context.categoryId);
      if (category.locationId != context.locationId ||
          category.kind != context.kind) {
        throw const MenuContextChangedException();
      }
      final product = await ref
          .read(menuRepositoryProvider)
          .getProduct(context.productId);
      if (product.categoryId != context.categoryId) {
        throw const MenuContextChangedException();
      }
      return true;
    } on ApiException catch (error) {
      await _apiError(error);
    } on Object catch (error) {
      state = ProductImageState(
        phase: ProductImagePhase.error,
        message: error.toString(),
      );
    }
    return false;
  }

  Future<void> _apiError(ApiException error) async {
    if (error.statusCode == 401) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
    state = ProductImageState(
      phase: ProductImagePhase.error,
      message: error.message,
    );
  }

  bool _ambiguous(ApiException error) =>
      error.cause is DioException &&
      const <DioExceptionType>{
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      }.contains((error.cause! as DioException).type);

  void _refresh() {
    ref.invalidate(
      menuProductDetailProvider((
        locationId: context.locationId,
        categoryId: context.categoryId,
        productId: context.productId,
      )),
    );
    ref.invalidate(
      menuProductsProvider((
        locationId: context.locationId,
        locationSlug: context.locationSlug,
        categoryId: context.categoryId,
      )),
    );
  }
}
