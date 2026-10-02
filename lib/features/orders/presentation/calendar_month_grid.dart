import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/orders_date_filter.dart';

/// Calendar-only date coordinates. Period changes use the existing clamping
/// rule; the grid has no second header, arrows, or swipe navigation.
class CalendarMonthGrid extends StatelessWidget {
  const CalendarMonthGrid({
    required this.selectedDay,
    required this.today,
    required this.onDateChanged,
    super.key,
  });
  final DateTime selectedDay, today;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final offset = DateUtils.firstDayOffset(
      selectedDay.year,
      selectedDay.month,
      loc,
    );
    final days = DateUtils.getDaysInMonth(selectedDay.year, selectedDay.month);
    final count = ((offset + days + 6) ~/ 7) * 7;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    Widget select({
      required String label,
      required int value,
      required List<int> values,
      required String Function(int) text,
      required ValueChanged<int> onChanged,
    }) => DropdownButtonFormField<int>(
      key: ValueKey('calendar-$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: PelinesControlStyles.input(label: tr(context, label)),
      items: [
        for (final option in values)
          DropdownMenuItem(
            value: option,
            child: Text(
              text(option),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final month = select(
              label: 'Month',
              value: selectedDay.month,
              values: List.generate(12, (i) => i + 1),
              text: (m) => DateFormat.MMMM(locale).format(DateTime(2024, m)),
              onChanged: (m) =>
                  onDateChanged(dayInMonth(selectedDay, selectedDay.year, m)),
            );
            final year = select(
              label: 'Year',
              value: selectedDay.year,
              values: List.generate(81, (i) => 2020 + i),
              text: (y) => '$y',
              onChanged: (y) =>
                  onDateChanged(dayInMonth(selectedDay, y, selectedDay.month)),
            );
            return constraints.maxWidth >= 270 * scale
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: month),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: year),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [month, const SizedBox(height: 12), year],
                  );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: ExcludeSemantics(
                  child: Center(
                    child: Text(
                      loc.narrowWeekdays[(loc.firstDayOfWeekIndex + i) % 7],
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
        GridView.builder(
          key: ValueKey(
            'calendar-grid-${selectedDay.year}-${selectedDay.month}',
          ),
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: math.max(48, 36 * scale),
          ),
          itemCount: count,
          itemBuilder: (context, index) {
            final number = index - offset + 1;
            if (number < 1 || number > days) return const SizedBox.shrink();
            final date = DateTime(selectedDay.year, selectedDay.month, number);
            final selected = number == selectedDay.day;
            final current = DateUtils.isSameDay(date, today);
            return Semantics(
              selected: selected,
              button: true,
              label:
                  '${loc.formatFullDate(date)}${current ? ', ${tr(context, 'Today')}' : ''}',
              onTap: () => onDateChanged(date),
              child: ExcludeSemantics(
                child: TextButton(
                  key: ValueKey('calendar-day-$number'),
                  onPressed: () => onDateChanged(date),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    foregroundColor: selected
                        ? Colors.white
                        : PelinesColors.textPrimary,
                    backgroundColor: selected
                        ? PelinesColors.brandPrimary
                        : null,
                    shape: const CircleBorder(),
                    side: current && !selected
                        ? const BorderSide(color: PelinesColors.brandPrimary)
                        : null,
                  ),
                  child: Text(
                    loc.formatDecimal(number),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
