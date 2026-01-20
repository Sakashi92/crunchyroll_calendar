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
  static const int _dbVersion = 3; // Set to 3 and use onOpen to ensure table exists
  
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
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: (db) async {
          try {
            if (kDebugMode) print('🔓 Opening DB, verifying schema...');
            final tables = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
              [_tableName],
            );

            if (tables.isEmpty) {
              if (kDebugMode) print('  - Notifications table missing on open, creating...');
              await _createNotificationsTable(db);
            } else {
              if (kDebugMode) print('  - Notifications table present');
            }
          } catch (e) {
            if (kDebugMode) print('❌ Error in onOpen DB check: $e');
          }
        },
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error initializing database: $e');
      rethrow;
    }
  }
  
  /// Erstellt die Tabellen beim erstmaligen Erstellen der DB
  Future<void> _onCreate(Database db, int version) async {
    try {
      await _createNotificationsTable(db);
      if (kDebugMode) print('✓ Notifications table created (version $version)');
    } catch (e) {
      if (kDebugMode) print('❌ Error creating table: $e');
      rethrow;
    }
  }

  /// Upgrade-Logik wenn die DB-Version erhöht wird
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    try {
      if (kDebugMode) print('🔄 Upgrading database from version $oldVersion to $newVersion');
      
      // Von Version 1 zu 2: Stelle sicher, dass die Tabelle existiert
      if (oldVersion < 2) {
        // Prüfe ob die Tabelle bereits existiert
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [_tableName],
        );
        
        if (tables.isEmpty) {
          if (kDebugMode) print('  - Creating missing notifications table...');
          await _createNotificationsTable(db);
        } else {
          if (kDebugMode) print('  - Notifications table already exists');
        }
      }
      
      if (kDebugMode) print('✓ Database upgrade completed');
    } catch (e) {
      if (kDebugMode) print('❌ Error upgrading database: $e');
      rethrow;
    }
  }

  /// Erstellt die notifications Tabelle
  Future<void> _createNotificationsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        favoriteId INTEGER,
        favoriteTitle TEXT NOT NULL,
        releaseTitle TEXT NOT NULL,
        episodeNumber TEXT,
        notifyTime TEXT NOT NULL,
        isShown INTEGER DEFAULT 0,
        contentHash TEXT
      )
    ''');
    
    // Index für schnellere Abfragen
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_favorite_title ON $_tableName(favoriteTitle)
    ''');
    
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_notify_time ON $_tableName(notifyTime)
    ''');
    
    // Index für Content-Hash (für Deduplication)
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_content_hash ON $_tableName(contentHash)
    ''');
  }

  /// Sicherstellen, dass die Tabelle existiert (idempotent)
  Future<void> _ensureTableExists(Database db) async {
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [_tableName],
      );

      if (tables.isEmpty) {
        if (kDebugMode) print('⚠️  _ensureTableExists: table missing, creating...');
        await _createNotificationsTable(db);
      } else {
        if (kDebugMode) print('✔️  _ensureTableExists: table present');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error in _ensureTableExists: $e');
      // Rethrow to let callers handle it if necessary
      rethrow;
    }
  }
  
  /// Loggt eine neue Benachrichtigung
  Future<int> logNotification(NotificationLog notification) async {
    try {
      final db = await database;
      // Ensure table exists (extra safety for corrupted/missing schemas)
      await _ensureTableExists(db);

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
      
      // Baue die WHERE-Klausel dynamisch auf, um NULL-Werte richtig zu behandeln
      String where = 'favoriteTitle = ? AND releaseTitle = ? AND notifyTime > ?';
      List<dynamic> whereArgs = [favoriteTitle, releaseTitle, yesterday.toIso8601String()];
      
      // Wenn episodeNumber null ist, prüfe auf IS NULL, sonst auf Gleichheit
      if (episodeNumber == null) {
        where += ' AND episodeNumber IS NULL';
      } else {
        where += ' AND episodeNumber = ?';
        whereArgs.add(episodeNumber);
      }
      
      final result = await db.query(
        _tableName,
        where: where,
        whereArgs: whereArgs,
      );
      
      return result.isNotEmpty;
    } catch (e) {
      if (kDebugMode) print('❌ Error checking notification history: $e');
      return false;
    }
  }
  
  /// 🚀 NEUE METHODE: Smartere Deduplication basierend auf Content-Hash
  /// Prüft ob dieser EXAKTE Inhalt schon mal versendet wurde (GLOBAL, kein Zeitlimit!)
  /// Returns: true wenn Duplikat gefunden (nicht senden), false wenn neu (senden)
  /// 
  /// WICHTIG: Einmal versendet = immer duplikat! Nie wieder senden!
  Future<bool> isDuplicate(
    String contentHash, {
    String? favoriteTitle,
    String? releaseTitle,
    String? episodeNumber,
  }) async {
    try {
      final db = await database;

      // 1) PRIMÄRE PRÜFUNG: Suche nach exakt gleichem contentHash (NEVER SEND AGAIN)
      // Zeitlimit: KEINE! Einmal versendet = immer Duplikat!
      final hashResult = await db.query(
        _tableName,
        where: 'contentHash = ?',
        whereArgs: [contentHash],
        limit: 1,
      );

      if (hashResult.isNotEmpty) {
        if (kDebugMode) {
          final existingTime = hashResult.first['notifyTime'] as String?;
          print('⏭️  [DEDUP] Exact contentHash found (sent on $existingTime) - SKIP: $contentHash');
        }
        return true;
      }
      // Kein Duplikat gefunden (nur Content-Hash wird berücksichtigt)
      if (kDebugMode) print('✅ [DEDUP] New content (no matching contentHash) - WILL SEND: $favoriteTitle / $releaseTitle / $episodeNumber');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Error checking duplicate: $e');
      // Im Fehlerfall: besser NICHT senden (false = senden, also true = skip)
      return true;
    }
  }
  
  /// 🚀 NEUE METHODE: Gibt eine Übersicht der Benachrichtigungen der letzten Stunden
  Future<Map<String, dynamic>> getNotificationStats({int hoursBack = 2}) async {
    try {
      final db = await database;
      
      final cutoffTime = DateTime.now().subtract(Duration(hours: hoursBack));
      
      final result = await db.rawQuery('''
        SELECT 
          COUNT(*) as totalCount,
          COUNT(DISTINCT contentHash) as uniqueCount,
          COUNT(DISTINCT favoriteTitle) as favCount,
          MIN(notifyTime) as oldestTime,
          MAX(notifyTime) as newestTime
        FROM $_tableName
        WHERE notifyTime > ?
      ''', [cutoffTime.toIso8601String()]);
      
      if (result.isNotEmpty) {
        return result.first.cast<String, dynamic>();
      }
      
      return {
        'totalCount': 0,
        'uniqueCount': 0,
        'favCount': 0,
        'oldestTime': null,
        'newestTime': null,
      };
    } catch (e) {
      if (kDebugMode) print('❌ Error getting notification stats: $e');
      return {};
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
