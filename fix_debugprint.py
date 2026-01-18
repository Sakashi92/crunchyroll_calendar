import sys

files = [
    'lib/main.dart',
    'lib/services/crunchyroll_service.dart'
]

for fpath in files:
    try:
        with open(fpath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        content = content.replace('if (_debugPrint) print(', 'if (kDebugMode) print(')
        
        with open(fpath, 'w', encoding='utf-8') as f:
            f.write(content)
        
        print(f'✓ Updated {fpath}')
    except Exception as e:
        print(f'✗ Error {fpath}: {e}')
        sys.exit(1)

print('\n✓ All files updated - migration complete')
