import 'package:flutter/foundation.dart';

/// Notifier that signals when external predictions were persisted.
/// Set to `true` after predictions are saved so listeners (e.g. CalendarPage)
/// can reload their view.
final ValueNotifier<bool> predictionsUpdated = ValueNotifier<bool>(false);
