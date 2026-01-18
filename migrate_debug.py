#!/usr/bin/env python3

with open('lib/services/crunchyroll_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Ersetze alle if (_debugPrint) mit if (kDebugMode)
content = content.replace('if (_debugPrint) print(', 'if (kDebugMode) print(')

with open('lib/services/crunchyroll_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print('✓ Replaced all _debugPrint with kDebugMode')

# Auch main.dart
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Entferne die const _debugPrint und ersetze durch import
content = content.replace('// Debug-Modus - auf false setzen für Release-Build\nconst bool _debugPrint = bool.fromEnvironment(\'DEBUG\', defaultValue: false);\n\n', '')
content = content.replace('import \'package:flutter/material.dart\';', 'import \'package:flutter/material.dart\';\nimport \'package:flutter/foundation.dart\';')
content = content.replace('if (_debugPrint) print(', 'if (kDebugMode) print(')

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print('✓ Updated main.dart - removed custom _debugPrint, using kDebugMode')
