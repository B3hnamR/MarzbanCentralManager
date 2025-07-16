#!/usr/bin/env python3
"""
Quick syntax test for marzban_manager.py
"""

import ast
import sys

def test_syntax(filename):
    """Test Python syntax of a file."""
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            source = f.read()
        
        # Parse the source code
        ast.parse(source, filename=filename)
        print(f"✅ {filename}: Syntax is valid")
        return True
        
    except SyntaxError as e:
        print(f"❌ {filename}: Syntax error at line {e.lineno}")
        print(f"   {e.text.strip() if e.text else ''}")
        print(f"   {' ' * (e.offset - 1)}^" if e.offset else "")
        print(f"   {e.msg}")
        return False
    except Exception as e:
        print(f"❌ {filename}: Error reading file: {e}")
        return False

def main():
    """Test syntax of main files."""
    files_to_test = [
        'marzban_manager.py',
        'main.py',
        'test_install.py'
    ]
    
    print("🔍 Testing Python syntax...")
    all_good = True
    
    for filename in files_to_test:
        if not test_syntax(filename):
            all_good = False
    
    if all_good:
        print("\n🎉 All files have valid syntax!")
        return 0
    else:
        print("\n❌ Some files have syntax errors!")
        return 1

if __name__ == "__main__":
    sys.exit(main())