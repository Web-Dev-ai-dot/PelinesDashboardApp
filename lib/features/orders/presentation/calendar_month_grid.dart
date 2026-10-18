import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/orders_date_filter.dart';

/// Calendar-only coordinates. Month arrows retain the existing day clamp.
class CalendarMonthGrid extends StatelessWidget {
  const CalendarMonthGrid({
    required this.selectedDay,
    required this.today,
    required this.onDateChanged,
    this.hasOrders,
    super.key,
  });
  final DateTime selectedDay, today;
  final ValueChanged<DateTime> onDateChanged;
  final bool Function(DateTime)? hasOrders;

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final offset = DateTime(selectedDay.year, selectedDay.month, 1).weekday % 7;
    final days = DateUtils.getDaysInMonth(selectedDay.year, selectedDay.month);
    final count = ((offset + days + 6) ~/ 7) * 7;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    void shiftMonth(int delta) {
      final month = DateTime(selectedDay.year, selectedDay.month + delta);
      onDateChanged(dayInMonth(selectedDay, month.year, month.month));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('calendar-previous-month'),
              tooltip: loc.previousMonthTooltip,
              style: IconButton.styleFrom(
                backgroundColor: PelinesColors.mutedSurface,
                minimumSize: const Size(48, 48),
                shape: const CircleBorder(),
              ),
              onPressed: () => shiftMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  DateFormat.yMMMM(locale).format(selectedDay),
                  key: const Key('calendar-month-title'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            IconButton(
              key: const Key('calendar-next-month'),
              tooltip: loc.nextMonthTooltip,
              style: IconButton.styleFrom(
                backgroundColor: PelinesColors.mutedSurface,
                minimumSize: const Size(48, 48),
                shape: const CircleBorder(),
              ),
              onPressed: () => shiftMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: ExcludeSemantics(
                  child: Center(
                    child: Text(
                      loc.narrowWeekdays[i],
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
            mainAxisExtent: math.max(60, 44 * scale),
          ),
          itemCount: count,
          itemBuilder: (context, index) {
            final number = index - offset + 1;
            if (number < 1 || number > days) return const SizedBox.shrink();
            final date = DateTime(selectedDay.year, selectedDay.month, number);
            final selected = number == selectedDay.day;
            final current = DateUtils.isSameDay(date, today);
            final marked = hasOrders?.call(date) ?? false;
            return Semantics(
              selected: selected,
              button: true,
              label:
                  '${loc.formatFullDate(date)}${current ? ', ${tr(context, 'Today')}' : ''}${marked ? ', ${tr(context, 'Has orders')}' : ''}',
              onTap: () => onDateChanged(date),
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    Expanded(
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
                              ? const BorderSide(
                                  color: PelinesColors.brandPrimary,
                                )
                              : null,
                        ),
                        child: Text(
                          loc.formatDecimal(number),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 10,
                      child: marked
                          ? Center(
                              child: Container(
                                key: ValueKey('calendar-month-dot-$number'),
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: PelinesColors.brandPrimary,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
