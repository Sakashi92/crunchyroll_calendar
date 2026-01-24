import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../models/anime_release.dart';

class CalendarDisplay extends StatefulWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final CalendarFormat calendarFormat;
  final bool isCalendarMinimized;
  final List<AnimeRelease> Function(DateTime) eventLoader;
  final void Function(DateTime, DateTime) onDaySelected;
  final void Function(CalendarFormat) onFormatChanged;
  final void Function(DateTime) onPageChanged;
  final VoidCallback onExpand;
  final void Function({required bool up}) onCycleFormat;

  const CalendarDisplay({
    super.key,
    required this.focusedDay,
    this.selectedDay,
    required this.calendarFormat,
    required this.isCalendarMinimized,
    required this.eventLoader,
    required this.onDaySelected,
    required this.onFormatChanged,
    required this.onPageChanged,
    required this.onExpand,
    required this.onCycleFormat,
  });

  @override
  State<CalendarDisplay> createState() => _CalendarDisplayState();
}

class _CalendarDisplayState extends State<CalendarDisplay> {
  double _verticalDragDelta = 0.0;
  final double _verticalDragThreshold = 120.0;

  @override
  Widget build(BuildContext context) {
    if (widget.isCalendarMinimized) {
      return _buildMinimizedHeader(context);
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _verticalDragDelta = 0.0,
      onPointerMove: (event) {
        _verticalDragDelta += event.delta.dy;
        if (_verticalDragDelta <= -_verticalDragThreshold) {
          _verticalDragDelta += _verticalDragThreshold;
          widget.onCycleFormat(up: true);
        } else if (_verticalDragDelta >= _verticalDragThreshold) {
          _verticalDragDelta -= _verticalDragThreshold;
          widget.onCycleFormat(up: false);
        }
      },
      onPointerUp: (_) => _verticalDragDelta = 0.0,
      onPointerCancel: (_) => _verticalDragDelta = 0.0,
      child: TableCalendar<AnimeRelease>(
        locale: 'de_DE',
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: widget.focusedDay,
        calendarFormat: widget.calendarFormat,
        startingDayOfWeek: StartingDayOfWeek.monday,
        selectedDayPredicate: (day) => isSameDay(widget.selectedDay, day),
        onDaySelected: widget.onDaySelected,
        onFormatChanged: widget.onFormatChanged,
        onPageChanged: widget.onPageChanged,
        eventLoader: widget.eventLoader,
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
        ),
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          formatButtonShowsNext: false,
        ),
        calendarBuilders: CalendarBuilders<AnimeRelease>(
          markerBuilder: (context, date, events) {
            if (events.isEmpty) {
              return const SizedBox.shrink();
            }
            final color = Theme.of(context).colorScheme.primary;
            final hasPrediction = events.any((e) => e.isPredicted);

            return Stack(
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      width: 22,
                      height: 3,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                if (hasPrediction)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6, right: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade700,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'V',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        availableCalendarFormats: const {
          CalendarFormat.month: 'Monat',
          CalendarFormat.twoWeeks: '2 Wochen',
          CalendarFormat.week: 'Woche',
        },
      ),
    );
  }

  Widget _buildMinimizedHeader(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.selectedDay ?? widget.focusedDay;
    final releases = widget.eventLoader(selected);

    return InkWell(
      onTap: widget.onExpand,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.calendar_today,
                size: 20,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(selected),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    releases.isEmpty
                        ? 'Keine Releases'
                        : '${releases.length} Release${releases.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
