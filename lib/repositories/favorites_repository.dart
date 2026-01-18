import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
//import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/favorite_anime.dart';
import 'package:flutter/foundation.dart';

/// Repository für die Verwaltung von Lieblings-Anime
/// Handles alle Datenbank-Operationen für Favoriten
class FavoritesRepository {
  static const String _tableName = 'favorites';
  static const String _dbName = 'crunchyroll_calendar.db';
  
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
      
      if (kDebugMode) print('📦 Initializing Favorites DB at: $path');
      
      return await openDatabase(
        path,
        version: 2, // Version erhöht für seriesUrl Spalte
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
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
          title TEXT UNIQUE NOT NULL,
          imageUrl TEXT,
          seriesUrl TEXT,
          addedDate TEXT NOT NULL,
          lastChecked TEXT
        )
      ''');
      
      if (kDebugMode) print('✓ Favorites table created');
    } catch (e) {
      if (kDebugMode) print('❌ Error creating table: $e');
      rethrow;
    }
  }
  
  /// Aktualisiert die Datenbank bei Version-Upgrade
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    try {
      if (oldVersion < 2) {
        // Füge seriesUrl Spalte hinzu
        await db.execute('ALTER TABLE $_tableName ADD COLUMN seriesUrl TEXT');
        if (kDebugMode) print('✓ Added seriesUrl column to favorites table');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error upgrading database: $e');
      rethrow;
    }
  }
  
  /// Fügt ein neues Lieblings-Anime hinzu
  Future<int> addFavorite(FavoriteAnime favorite) async {
    try {
      final db = await database;
      // Normalisiere den Titel (Trim + Capitalize)
      final normalizedFavorite = FavoriteAnime(
        id: favorite.id,
        title: favorite.title.trim(),
        imageUrl: favorite.imageUrl,
        seriesUrl: favorite.seriesUrl,
        addedDate: favorite.addedDate,
        lastChecked: favorite.lastChecked,
      );
      
      final id = await db.insert(
        _tableName,
        normalizedFavorite.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      if (kDebugMode) print('✓ Added favorite: ${normalizedFavorite.title} (id: $id)');
      return id;
    } catch (e) {
      if (kDebugMode) print('❌ Error adding favorite: $e');
      rethrow;
    }
  }
  
  /// Entfernt ein Lieblings-Anime anhand des Titels
  Future<bool> removeFavorite(String title) async {
    try {
      final db = await database;
      final normalizedTitle = title.trim();
      final deleted = await db.delete(
        _tableName,
        where: 'LOWER(TRIM(title)) = LOWER(?)',
        whereArgs: [normalizedTitle],
      );
      
      final success = deleted > 0;
      if (kDebugMode) print('${success ? '✓' : '⚠'} Removed favorite: $title (deleted: $deleted)');
      return success;
    } catch (e) {
      if (kDebugMode) print('❌ Error removing favorite: $e');
      rethrow;
    }
  }
  
  /// Holt alle Lieblings-Anime
  Future<List<FavoriteAnime>> getAllFavorites() async {
    try {
      final db = await database;
      final maps = await db.query(
        _tableName,
        orderBy: 'addedDate DESC',
      );
      
      final favorites = maps.map((map) => FavoriteAnime.fromJson(map)).toList();
      
      if (kDebugMode) print('✓ Retrieved ${favorites.length} favorites');
      return favorites;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting favorites: $e');
      rethrow;
    }
  }
  
  /// Prüft ob ein Anime ein Favorit ist
  Future<bool> isFavorite(String title) async {
    try {
      final db = await database;
      final normalizedTitle = title.trim();
      final result = await db.query(
        _tableName,
        where: 'LOWER(TRIM(title)) = LOWER(?)',
        whereArgs: [normalizedTitle],
      );
      
      return result.isNotEmpty;
    } catch (e) {
      if (kDebugMode) print('❌ Error checking favorite: $e');
      return false;
    }
  }
  
  /// Aktualisiert den lastChecked Zeitstempel für ein Favorit
  Future<bool> updateLastChecked(String title) async {
    try {
      final db = await database;
      final updated = await db.update(
        _tableName,
        {'lastChecked': DateTime.now().toIso8601String()},
        where: 'title = ?',
        whereArgs: [title],
      );
      
      return updated > 0;
    } catch (e) {
      if (kDebugMode) print('❌ Error updating lastChecked: $e');
      return false;
    }
  }
  
  /// Holt die Anzahl der Favoriten
  Future<int> getFavoriteCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting favorite count: $e');
      return 0;
    }
  }
  
  /// Löscht alle Favoriten (für Debug/Reset)
  Future<int> deleteAllFavorites() async {
    try {
      final db = await database;
      final deleted = await db.delete(_tableName);
      
      if (kDebugMode) print('✓ Deleted all favorites (count: $deleted)');
      return deleted;
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting all favorites: $e');
      rethrow;
    }
  }
  
  /// Schließt die Datenbank
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      if (kDebugMode) print('✓ Favorites database closed');
    }
  }
  
  /// Exportiert alle Favoriten als JSON-Datei
  /// Der User kann den Speicherort selbst wählen
  /// Gibt den Pfad zur exportierten Datei zurück oder null wenn abgebrochen
  Future<String?> exportFavoritesToJson() async {
    try {
      final favorites = await getAllFavorites();
      
      // Erstelle Export-Datenstruktur
      final exportData = {
        'version': 1,
        'exportDate': DateTime.now().toIso8601String(),
        'favoritesCount': favorites.length,
        'favorites': favorites.map((f) => f.toJson()).toList(),
      };
      
      // Konvertiere zu JSON
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      
      // Generiere Dateiname mit Zeitstempel
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final suggestedFileName = 'crunchyroll_favorites_$timestamp.json';
      
      // Konvertiere JSON zu Bytes
      final bytes = utf8.encode(jsonString);
      
      // Lasse User den Speicherort wählen (mit Bytes!)
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Favoriten exportieren',
        fileName: suggestedFileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      
      // User hat abgebrochen
      if (outputPath == null) {
        if (kDebugMode) print('ℹ️ Export cancelled by user');
        return null;
      }
      
      if (kDebugMode) print('✅ Exported ${favorites.length} favorites to: $outputPath');
      return outputPath;
    } catch (e) {
      if (kDebugMode) print('❌ Error exporting favorites: $e');
      rethrow;
    }
  }
  
  /// Importiert Favoriten aus einer JSON-Datei
  /// Gibt die Anzahl der importierten Favoriten zurück
  Future<int> importFavoritesFromJson(String filePath) async {
    try {
      final file = File(filePath);
      
      if (!await file.exists()) {
        throw Exception('Datei nicht gefunden: $filePath');
      }
      
      // Lese JSON-Datei
      final jsonString = await file.readAsString();
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      
      // Validiere Format
      if (!data.containsKey('favorites')) {
        throw Exception('Ungültiges Format: "favorites" Feld fehlt');
      }
      
      final favoritesList = data['favorites'] as List<dynamic>;
      int importedCount = 0;
      int skippedCount = 0;
      
      // Importiere jeden Favoriten
      for (var favoriteJson in favoritesList) {
        try {
          final favorite = FavoriteAnime.fromJson(favoriteJson as Map<String, dynamic>);
          
          // Prüfe ob bereits vorhanden
          final exists = await isFavorite(favorite.title);
          
          if (!exists) {
            await addFavorite(favorite);
            importedCount++;
          } else {
            skippedCount++;
            if (kDebugMode) print('⏭️ Skipped duplicate: ${favorite.title}');
          }
        } catch (e) {
          if (kDebugMode) print('⚠️ Error importing single favorite: $e');
        }
      }
      
      if (kDebugMode) {
        print('✅ Import complete: $importedCount imported, $skippedCount skipped');
      }
      
      return importedCount;
    } catch (e) {
      if (kDebugMode) print('❌ Error importing favorites: $e');
      rethrow;
    }
  }
}
