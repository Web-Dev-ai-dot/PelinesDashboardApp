import 'package:flutter/material.dart';

import 'pelines_tokens.dart';

enum PelinesInputVariant { form, search, login, select }

enum PelinesButtonVariant {
  primary,
  accept,
  cancel,
  secondary,
  preparing,
  ready,
  complete,
}

/// Opt-in web variants. Existing screens retain their current Material theme
/// until their presentation is migrated; no screen-specific defaults change.
abstract final class PelinesControlStyles {
  static InputDecoration input({
    PelinesInputVariant variant = PelinesInputVariant.form,
    String? label,
    String? hint,
    String? error,
  }) {
    final pill =
        variant == PelinesInputVariant.search ||
        variant == PelinesInputVariant.login;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(
        pill ? PelinesRadius.pill : PelinesRadius.control,
      ),
      borderSide: pill
          ? BorderSide.none
          : const BorderSide(color: PelinesColors.border),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      filled: true,
      fillColor: pill ? PelinesColors.mutedSurface : PelinesColors.card,
      contentPadding: EdgeInsets.symmetric(
        horizontal: pill ? 20 : 12,
        vertical: 16,
      ),
      constraints: const BoxConstraints(minHeight: PelinesLayout.touchTarget),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(
          color: PelinesColors.brandPrimary,
          width: 2,
        ),
      ),
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: PelinesColors.destructive),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: const BorderSide(
          color: PelinesColors.destructive,
          width: 2,
        ),
      ),
      prefixIcon: variant == PelinesInputVariant.search
          ? const Icon(Icons.search, size: 20)
          : null,
    );
  }

  static ButtonStyle button(PelinesButtonVariant variant) {
    final outlined =
        variant == PelinesButtonVariant.cancel ||
        variant == PelinesButtonVariant.secondary;
    final color = switch (variant) {
      PelinesButtonVariant.accept => PelinesColors.successForeground,
      PelinesButtonVariant.preparing => PelinesColors.preparing,
      PelinesButtonVariant.complete => PelinesColors.blue,
      PelinesButtonVariant.secondary => PelinesColors.textPrimary,
      _ => PelinesColors.brandPrimary,
    };
    return FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      backgroundColor: outlined ? PelinesColors.card : color,
      foregroundColor: outlined ? color : PelinesColors.card,
      disabledBackgroundColor: PelinesColors.mutedSurface,
      disabledForegroundColor: PelinesColors.textSecondary,
      side: BorderSide(
        color: outlined
            ? (variant == PelinesButtonVariant.cancel
                  ? color
                  : PelinesColors.border)
            : Colors.transparent,
      ),
      shape: const StadiumBorder(),
      elevation: 0,
      textStyle: const TextStyle(
        fontFamily: PelinesTypography.bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

abstract final class AppTheme {
  static ThemeData get light {
    const ColorScheme colorScheme = ColorScheme.light(
      primary: PelinesColors.brandPrimary,
      onPrimary: PelinesColors.card,
      primaryContainer: PelinesColors.brandPrimarySoft,
      onPrimaryContainer: PelinesColors.brandPrimary,
      secondary: PelinesColors.brandYellow,
      onSecondary: PelinesColors.textPrimary,
      secondaryContainer: PelinesColors.brandYellowSoft,
      onSecondaryContainer: PelinesColors.textPrimary,
      error: PelinesColors.destructive,
      onError: PelinesColors.card,
      surface: PelinesColors.card,
      onSurface: PelinesColors.textPrimary,
      outline: PelinesColors.border,
      outlineVariant: PelinesColors.mutedSurface,
    );
    final TextTheme textTheme = PelinesTypography.textTheme(
      Typography.material2021().black,
    );
    final OutlineInputBorder inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(PelinesRadius.pill),
      borderSide: BorderSide.none,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: PelinesColors.page,
      fontFamily: PelinesTypography.bodyFamily,
      textTheme: textTheme,
      extensions: const <ThemeExtension<dynamic>>[PelinesStatusColors.light()],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PelinesColors.mutedSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: PelinesSpacing.lg,
          vertical: PelinesSpacing.md,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder,
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: PelinesColors.destructive),
        ),
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(
            color: PelinesColors.brandPrimary,
            width: 2,
          ),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(
            color: PelinesColors.destructive,
            width: 2,
          ),
        ),
        labelStyle: const TextStyle(
          color: PelinesColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: const TextStyle(color: PelinesColors.textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(
            PelinesLayout.touchTarget,
            PelinesLayout.touchTarget,
          ),
          backgroundColor: PelinesColors.brandPrimary,
          foregroundColor: PelinesColors.card,
          disabledBackgroundColor: PelinesColors.brandPrimarySoft,
          disabledForegroundColor: PelinesColors.textSecondary,
          textStyle: const TextStyle(
            fontFamily: PelinesTypography.bodyFamily,
            fontWeight: FontWeight.w600,
          ),
          shape: const StadiumBorder(),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            PelinesLayout.touchTarget,
            PelinesLayout.touchTarget,
          ),
          foregroundColor: PelinesColors.textPrimary,
          side: const BorderSide(color: PelinesColors.border),
          textStyle: const TextStyle(
            fontFamily: PelinesTypography.bodyFamily,
            fontWeight: FontWeight.w600,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(
            PelinesLayout.touchTarget,
            PelinesLayout.touchTarget,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(
            PelinesLayout.touchTarget,
            PelinesLayout.touchTarget,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return PelinesColors.card;
          }
          return PelinesColors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return PelinesColors.brandPrimary;
          }
          return PelinesColors.border;
        }),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: PelinesColors.brandPrimary,
        foregroundColor: PelinesColors.card,
        elevation: 2,
      ),
      dividerTheme: const DividerThemeData(
        color: PelinesColors.border,
        space: PelinesSpacing.md,
      ),
      cardTheme: CardThemeData(
        color: PelinesColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelinesRadius.prominentCard),
          side: const BorderSide(color: PelinesColors.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: PelinesColors.mutedSurface,
        selectedColor: PelinesColors.brandPrimarySoft,
        side: const BorderSide(color: PelinesColors.border),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: PelinesSpacing.sm),
        labelStyle: const TextStyle(
          color: PelinesColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: PelinesColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PelinesRadius.dialog),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: PelinesColors.page,
        foregroundColor: PelinesColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: PelinesTypography.pageTitle(textTheme),
        titleSpacing: PelinesSpacing.md,
      ),
    );
  }
}
