import sys
try:
    with open('all_lints.txt', 'rb') as f:
        content = f.read().decode('utf-16')
        print(content)
except Exception as e:
    print(f"Error: {e}")
