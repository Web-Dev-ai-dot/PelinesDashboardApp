import 'package:flutter/material.dart';

abstract final class PelinesColors {
  static const Color brandPrimary = Color(0xFFF21D1D);
  static const Color brandPrimarySoft = Color(0x33F21D1D);
  static const Color brandYellow = Color(0xFFFBB224);
  static const Color brandYellowSoft = Color(0x33FBB224);

  static const Color textPrimary = Color(0xFF272F39);
  static const Color textSecondary = Color(0xFF6C7A90);
  static const Color page = Color(0xFFF5F5F5);
  static const Color mutedSurface = Color(0xFFF3F4F6);
  static const Color border = Color(0xFFE5E7EB);
  static const Color card = Color(0xFFFFFFFF);

  static const Color destructive = Color(0xFFF21D1D);
  static const Color successForeground = Color(0xFF12733C);
  static const Color successBackground = Color(0x3321DA71);
  static const Color blue = Color(0xFF1D74BA);
  static const Color blueSoft = Color(0x331D74BA);
  static const Color preparing = Color(0xFF7C3AED);
  static const Color statusReady = Color(0xFFF21D1D);
}

abstract final class PelinesSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class PelinesRadius {
  static const double control = 8;
  static const double card = 12;
  static const double prominentCard = 16;
  static const double dialog = 24;
  static const double pill = 999;
}

abstract final class PelinesLayout {
  static const double compactWidth = 600;
  static const double contentMaxWidth = 760;
  static const double labelPairMinWidth = 400;
  static const double touchTarget = 48;
}

abstract final class PelinesShadows {
  static const List<BoxShadow> subtle = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 3)),
  ];

  static const List<BoxShadow> prominent = <BoxShadow>[
    BoxShadow(color: Color(0x24000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

abstract final class PelinesTypography {
  static const String bodyFamily = 'Work Sans';
  static const String headingFamily = 'Bree Serif';

  static TextStyle? pageTitle(TextTheme theme) => theme.titleLarge?.copyWith(
    fontFamily: bodyFamily,
    fontWeight: FontWeight.w700,
  );

  static TextTheme textTheme(TextTheme base) {
    final TextTheme body = base.apply(
      fontFamily: bodyFamily,
      bodyColor: PelinesColors.textPrimary,
      displayColor: PelinesColors.textPrimary,
    );
    return body.copyWith(
      displayLarge: _heading(body.displayLarge),
      displayMedium: _heading(body.displayMedium),
      displaySmall: _heading(body.displaySmall),
      headlineLarge: _heading(body.headlineLarge),
      headlineMedium: _heading(body.headlineMedium),
      headlineSmall: _heading(body.headlineSmall),
      labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelMedium: body.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: body.labelSmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  static TextStyle? _heading(TextStyle? style) =>
      style?.copyWith(fontFamily: headingFamily, fontWeight: FontWeight.w400);
}

@immutable
class PelinesStatusColors extends ThemeExtension<PelinesStatusColors> {
  const PelinesStatusColors({
    required this.pending,
    required this.pendingBackground,
    required this.confirmed,
    required this.confirmedBackground,
    required this.preparing,
    required this.ready,
    required this.completed,
    required this.completedBackground,
    required this.cancelled,
    required this.cancelledBackground,
  });

  const PelinesStatusColors.light()
    : pending = PelinesColors.brandYellow,
      pendingBackground = PelinesColors.brandYellowSoft,
      confirmed = PelinesColors.successForeground,
      confirmedBackground = PelinesColors.successBackground,
      preparing = PelinesColors.preparing,
      ready = PelinesColors.statusReady,
      completed = PelinesColors.blue,
      completedBackground = PelinesColors.blueSoft,
      cancelled = PelinesColors.destructive,
      cancelledBackground = PelinesColors.brandPrimarySoft;

  final Color pending;
  final Color pendingBackground;
  final Color confirmed;
  final Color confirmedBackground;
  final Color preparing;
  final Color ready;
  final Color completed;
  final Color completedBackground;
  final Color cancelled;
  final Color cancelledBackground;

  @override
  PelinesStatusColors copyWith({
    Color? pending,
    Color? pendingBackground,
    Color? confirmed,
    Color? confirmedBackground,
    Color? preparing,
    Color? ready,
    Color? completed,
    Color? completedBackground,
    Color? cancelled,
    Color? cancelledBackground,
  }) => PelinesStatusColors(
    pending: pending ?? this.pending,
    pendingBackground: pendingBackground ?? this.pendingBackground,
    confirmed: confirmed ?? this.confirmed,
    confirmedBackground: confirmedBackground ?? this.confirmedBackground,
    preparing: preparing ?? this.preparing,
    ready: ready ?? this.ready,
    completed: completed ?? this.completed,
    completedBackground: completedBackground ?? this.completedBackground,
    cancelled: cancelled ?? this.cancelled,
    cancelledBackground: cancelledBackground ?? this.cancelledBackground,
  );

  @override
  PelinesStatusColors lerp(
    covariant ThemeExtension<PelinesStatusColors>? other,
    double t,
  ) {
    if (other is! PelinesStatusColors) return this;
    return PelinesStatusColors(
      pending: Color.lerp(pending, other.pending, t)!,
      pendingBackground: Color.lerp(
        pendingBackground,
        other.pendingBackground,
        t,
      )!,
      confirmed: Color.lerp(confirmed, other.confirmed, t)!,
      confirmedBackground: Color.lerp(
        confirmedBackground,
        other.confirmedBackground,
        t,
      )!,
      preparing: Color.lerp(preparing, other.preparing, t)!,
      ready: Color.lerp(ready, other.ready, t)!,
      completed: Color.lerp(completed, other.completed, t)!,
      completedBackground: Color.lerp(
        completedBackground,
        other.completedBackground,
        t,
      )!,
      cancelled: Color.lerp(cancelled, other.cancelled, t)!,
      cancelledBackground: Color.lerp(
        cancelledBackground,
        other.cancelledBackground,
        t,
      )!,
    );
  }
}
