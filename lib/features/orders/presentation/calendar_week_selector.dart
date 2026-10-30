import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/l10n/admin_localizations.dart';
import '../../../app/theme/pelines_tokens.dart';
import '../models/calendar_planning.dart';

/// Date-only coordinates; indicators come from the unfiltered Calendar dataset.
class CalendarWeekSelector extends StatelessWidget {
  const CalendarWeekSelector({
    required this.selectedDay,
    required this.hasOrders,
    required this.onChanged,
    super.key,
  });

  final DateTime selectedDay;
  final bool Function(DateTime) hasOrders;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final days = calendarWeek(selectedDay);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final loc = MaterialLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            Container(
              key: const Key('calendar-week-surface'),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                color: PelinesColors.card,
                borderRadius: BorderRadius.circular(
                  PelinesRadius.prominentCard,
                ),
                border: Border.all(color: PelinesColors.border),
              ),
              child: Row(
                key: const Key('calendar-week-navigation'),
                children: [
                  IconButton(
                    key: const Key('calendar-previous-week'),
                    tooltip: tr(context, 'Previous week'),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () =>
                        onChanged(shiftCalendarWeek(selectedDay, -1)),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Keep 48px targets: narrow / enlarged-text layouts scroll
                        // horizontally instead of shrinking text or clipping weekdays.
                        final width = math.max(
                          48 * scale,
                          constraints.maxWidth / 7,
                        );
                        return SingleChildScrollView(
                          key: const Key('calendar-week-days'),
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final date in days)
                                SizedBox(
                                  width: width,
                                  child: Semantics(
                                    selected: DateUtils.isSameDay(
                                      date,
                                      selectedDay,
                                    ),
                                    label:
                                        '${loc.formatFullDate(date)}${hasOrders(date) ? ', ${tr(context, 'Has orders')}' : ''}',
                                    button: true,
                                    onTap: () => onChanged(date),
                                    child: ExcludeSemantics(
                                      child: TextButton(
                                        key: ValueKey(
                                          'calendar-week-day-${date.weekday}',
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          foregroundColor:
                                              DateUtils.isSameDay(
                                                date,
                                                selectedDay,
                                              )
                                              ? Colors.white
                                              : PelinesColors.textPrimary,
                                          backgroundColor:
                                              DateUtils.isSameDay(
                                                date,
                                                selectedDay,
                                              )
                                              ? PelinesColors.brandPrimary
                                              : null,
                                          shape: const StadiumBorder(),
                                        ),
                                        onPressed: () => onChanged(date),
                                        child: Column(
                                          children: [
                                            Text(
                                              DateFormat.E(locale).format(date),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              loc.formatDecimal(date.day),
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            SizedBox(
                                              height: 6,
                                              width: 6,
                                              child: hasOrders(date)
                                                  ? DecoratedBox(
                                                      key: ValueKey(
                                                        'calendar-week-dot-${date.weekday}',
                                                      ),
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color:
                                                            DateUtils.isSameDay(
                                                              date,
                                                              selectedDay,
                                                            )
                                                            ? Colors.white
                                                            : PelinesColors
                                                                  .brandPrimary,
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    key: const Key('calendar-next-week'),
                    tooltip: tr(context, 'Next week'),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () =>
                        onChanged(shiftCalendarWeek(selectedDay, 1)),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
