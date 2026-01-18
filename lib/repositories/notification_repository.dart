import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/notification_log.dart';
import 'package:flutter/foundation.dart';

/// Repository für die Verwaltung von Benachrichtigungs-Historien
/// Speichert alle Benachrichtigungen zur Duplikat-Vermeidung
class NotificationRepository {
  static const String _tableName = 'notifications';
  static const String _dbName = 'crunchyroll_calendar.db';
  static const int _maxRetentionDays = 30;
  
  static Database? _database;
  
  /// Initialisiert die Datenbank
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }
  
  /// Erstellt/öffnet die Datenbank und initialisiert das Schema
  Future<Database> _initDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _dbName);
      
      if (kDebugMode) print('📦 Initializing Notifications DB at: $path');
      
      return await openDatabase(
        path,
        version: 1,
        onCreate: _onCreate,
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error initializing database: $e');
      rethrow;
    }
  }
  
  /// Erstellt die Tabellen beim erstmaligen Erstellen der DB
  Future<void> _onCreate(Database db, int version) async {
    try {
      await db.execute('''
        CREATE TABLE $_tableName (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          favoriteId INTEGER,
          favoriteTitle TEXT NOT NULL,
          releaseTitle TEXT NOT NULL,
          episodeNumber TEXT,
          notifyTime TEXT NOT NULL,
          isShown INTEGER DEFAULT 0
        )
      ''');
      
      // Index für schnellere Abfragen
      await db.execute('''
        CREATE INDEX idx_favorite_title ON $_tableName(favoriteTitle)
      ''');
      
      await db.execute('''
        CREATE INDEX idx_notify_time ON $_tableName(notifyTime)
      ''');
      
      if (kDebugMode) print('✓ Notifications table created');
    } catch (e) {
      if (kDebugMode) print('❌ Error creating table: $e');
      rethrow;
    }
  }
  
  /// Loggt eine neue Benachrichtigung
  Future<int> logNotification(NotificationLog notification) async {
    try {
      final db = await database;
      
      // Cleanup alte Einträge bevor wir neue hinzufügen
      await _cleanupOldNotifications();
      
      final id = await db.insert(
        _tableName,
        notification.toJson(),
      );
      
      if (kDebugMode) {
        print('✓ Logged notification: ${notification.releaseTitle} for ${notification.favoriteTitle}');
      }
      return id;
    } catch (e) {
      if (kDebugMode) print('❌ Error logging notification: $e');
      rethrow;
    }
  }
  
  /// Prüft ob eine Benachrichtigung bereits gesendet wurde (Duplikat-Vermeidung)
  /// Sucht nach: selbes Favorit + selbe Episode innerhalb der letzten 24 Stunden
  Future<bool> hasBeenNotified(String favoriteTitle, String releaseTitle, String? episodeNumber) async {
    try {
      final db = await database;
      const oneDayAgo = 24;
      
      final yesterday = DateTime.now().subtract(const Duration(hours: oneDayAgo));
      
      final result = await db.query(
        _tableName,
        where: 'favoriteTitle = ? AND releaseTitle = ? AND episodeNumber = ? AND notifyTime > ?',
        whereArgs: [favoriteTitle, releaseTitle, episodeNumber, yesterday.toIso8601String()],
      );
      
      return result.isNotEmpty;
    } catch (e) {
      if (kDebugMode) print('❌ Error checking notification history: $e');
      return false;
    }
  }
  
  /// Holt die Benachrichtigungs-Historie (optional gefiltert nach Favorit)
  Future<List<NotificationLog>> getHistory({String? favoriteTitle, int limit = 100}) async {
    try {
      final db = await database;
      
      late final List<Map<String, dynamic>> maps;
      
      if (favoriteTitle != null) {
        maps = await db.query(
          _tableName,
          where: 'favoriteTitle = ?',
          whereArgs: [favoriteTitle],
          orderBy: 'notifyTime DESC',
          limit: limit,
        );
      } else {
        maps = await db.query(
          _tableName,
          orderBy: 'notifyTime DESC',
          limit: limit,
        );
      }
      
      return maps.map((map) => NotificationLog.fromJson(map)).toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error getting history: $e');
      return [];
    }
  }
  
  /// Markiert eine Benachrichtigung als angezeigt
  Future<bool> markAsShown(int notificationId) async {
    try {
      final db = await database;
      final updated = await db.update(
        _tableName,
        {'isShown': 1},
        where: 'id = ?',
        whereArgs: [notificationId],
      );
      
      return updated > 0;
    } catch (e) {
      if (kDebugMode) print('❌ Error marking as shown: $e');
      return false;
    }
  }
  
  /// Zählt unangezeigte Benachrichtigungen
  Future<int> getUnshownCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName WHERE isShown = 0'
      );
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting unshown count: $e');
      return 0;
    }
  }
  
  /// Löscht alte Benachrichtigungen (älter als X Tage)
  Future<int> _cleanupOldNotifications({int retentionDays = _maxRetentionDays}) async {
    try {
      final db = await database;
      
      final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));
      
      final deleted = await db.delete(
        _tableName,
        where: 'notifyTime < ?',
        whereArgs: [cutoffDate.toIso8601String()],
      );
      
      if (deleted > 0 && kDebugMode) {
        print('🗑️  Cleaned up $deleted old notifications (older than $retentionDays days)');
      }
      
      return deleted;
    } catch (e) {
      if (kDebugMode) print('❌ Error cleaning up old notifications: $e');
      return 0;
    }
  }
  
  /// Löscht alle Benachrichtigungen für ein Favorit (wenn es gelöscht wird)
  Future<int> deleteByFavoriteTitle(String favoriteTitle) async {
    try {
      final db = await database;
      final deleted = await db.delete(
        _tableName,
        where: 'favoriteTitle = ?',
        whereArgs: [favoriteTitle],
      );
      
      if (kDebugMode) print('✓ Deleted $deleted notifications for: $favoriteTitle');
      return deleted;
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting by favorite: $e');
      return 0;
    }
  }
  
  /// Löscht alle Benachrichtigungen (für Debug/Reset)
  Future<int> deleteAllNotifications() async {
    try {
      final db = await database;
      final deleted = await db.delete(_tableName);
      
      if (kDebugMode) print('✓ Deleted all notifications (count: $deleted)');
      return deleted;
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting all notifications: $e');
      rethrow;
    }
  }
  
  /// Schließt die Datenbank
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      if (kDebugMode) print('✓ Notifications database closed');
    }
  }
}
