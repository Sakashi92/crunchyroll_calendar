import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../models/anime_release.dart';
import '../services/app_settings_service.dart';

class CalendarDisplay extends StatefulWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final CalendarFormat calendarFormat;
  final bool isCalendarMinimized;
  final bool isScrolledPastThreshold;
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
    this.isScrolledPastThreshold = false,
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

    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // In portrait mode, make background transparent when scroll threshold is passed
    final bool useTransparentBackground =
        !isLandscape && widget.isScrolledPastThreshold;

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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: useTransparentBackground
              ? Colors.transparent
              : theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          boxShadow: useTransparentBackground
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: TableCalendar<AnimeRelease>(
          key: ValueKey(widget.calendarFormat),
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
            // Make today/selected circles larger and shift 1px up
            cellMargin: const EdgeInsets.only(
              left: 5,
              right: 5,
              top: 6,
              bottom: 4,
            ),
            todayDecoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.5),
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
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
            weekendStyle: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
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
                    Builder(
                      builder: (context) {
                        final isLandscape =
                            MediaQuery.of(context).orientation ==
                            Orientation.landscape;
                        return Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: isLandscape
                                ? const EdgeInsets.only(bottom: 4, right: 28)
                                : const EdgeInsets.only(bottom: 6, right: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.surface,
                                  width: 1.0,
                                ),
                              ),
                              child: Text(
                                'V',
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.primary
                                              .computeLuminance() >
                                          0.5
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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
      ),
    );
  }

  Widget _buildMinimizedHeader(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.selectedDay ?? widget.focusedDay;
    final releases = widget.eventLoader(selected);

    return FutureBuilder<bool>(
      future: AppSettingsService.getFullDateInPill(),
      builder: (context, snapshot) {
        final useFullDate = snapshot.data ?? false;
        final dateFormat = useFullDate ? 'EEEE, d. MMMM' : 'E, d. MMM';

        return Center(
          child: InkWell(
            onTap: widget.onExpand,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat(dateFormat, 'de_DE').format(selected),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '•',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    releases.isEmpty
                        ? 'Keine Releases'
                        : '${releases.length} Release${releases.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
