import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(useMaterial3: true, fontFamily: 'Inter');

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary500,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary500,
      onPrimary: AppColors.neutral0,
      primaryContainer: AppColors.primary25,
      onPrimaryContainer: AppColors.primary1100,
      secondary: AppColors.primary700,
      surface: AppColors.neutral0,
      onSurface: AppColors.neutral1300,
      surfaceContainerHighest: AppColors.neutral50,
      outline: AppColors.neutral100,
      error: AppColors.error500,
      onError: AppColors.neutral0,
      errorContainer: AppColors.errorBg,
      onErrorContainer: AppColors.error700,
    );

    final textTheme = base.textTheme
        .copyWith(
          titleLarge: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.neutral1300,
          ),
          titleMedium: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.neutral1300,
          ),
          bodyLarge: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: AppColors.neutral1300,
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.neutral900,
          ),
          bodySmall: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.neutral500,
          ),
          labelLarge: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.neutral1300,
          ),
        )
        .apply(fontFamily: 'Inter');

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.neutral25,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.neutral0,
        foregroundColor: AppColors.neutral1300,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.neutral1300,
        ),
        iconTheme: const IconThemeData(color: AppColors.neutral900, size: 22),
      ),
      cardTheme: CardThemeData(
        color: AppColors.neutral0,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
          side: const BorderSide(color: AppColors.neutral100),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.neutral0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xLarge),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.neutral1300,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.neutral700,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.neutral0,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.neutral300,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xLarge),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary500,
        foregroundColor: AppColors.neutral0,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.neutral900,
        contentTextStyle: const TextStyle(
          fontFamily: 'Inter',
          color: AppColors.neutral0,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary500,
          foregroundColor: AppColors.neutral0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s6,
            vertical: AppSpacing.s4,
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.neutral700,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s5,
            vertical: AppSpacing.s4,
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.neutral25,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s5,
          vertical: AppSpacing.s4,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: const BorderSide(color: AppColors.primary500, width: 1.5),
        ),
        hintStyle: const TextStyle(
          fontFamily: 'Inter',
          color: AppColors.neutral500,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.neutral700,
        textColor: AppColors.neutral1300,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.neutral100,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: AppColors.neutral700, size: 22),
      splashFactory: InkRipple.splashFactory,
    );
  }
}
