#!/usr/bin/env python3
"""
Quick installation test script for Marzban Central Manager
"""

import sys
import os
from pathlib import Path

# Add src to Python path
sys.path.insert(0, str(Path(__file__).parent / "src"))

def test_imports():
    """Test basic imports."""
    print("🔄 Testing imports...")
    
    try:
        # Test core imports
        from src.core.logger import get_logger
        from src.core.utils import is_valid_ip, format_bytes
        from src.core.exceptions import APIError
        print("✅ Core modules imported successfully")
        
        # Test model imports
        from src.models.node import Node
        from src.models.response import APIResponse
        print("✅ Model modules imported successfully")
        
        # Test CLI imports
        from src.cli.commands.node import node
        print("✅ CLI modules imported successfully")
        
        return True
        
    except ImportError as e:
        print(f"❌ Import error: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def test_utilities():
    """Test utility functions."""
    print("🔄 Testing utility functions...")
    
    try:
        from src.core.utils import is_valid_ip, format_bytes, format_duration
        
        # Test utility functions
        assert is_valid_ip('192.168.1.1') == True
        assert is_valid_ip('invalid') == False
        assert format_bytes(1024) == '1.00 KB'
        assert format_duration(3661) == '1h 1m 1s'
        
        print("✅ Utility functions work correctly")
        return True
        
    except Exception as e:
        print(f"❌ Utility test failed: {e}")
        return False

def test_basic_functionality():
    """Test basic functionality without async."""
    print("🔄 Testing basic functionality...")
    
    try:
        from src.core.config import MarzbanConfig
        from src.models.node import Node, NodeStatus
        
        # Test config creation
        config = MarzbanConfig(
            base_url="https://test.com",
            username="test",
            password="test"
        )
        assert config.base_url == "https://test.com"
        
        # Test node creation
        node = Node(
            id=1,
            name="Test Node",
            address="192.168.1.100",
            port=62050,
            api_port=62051,
            status=NodeStatus.CONNECTED
        )
        assert node.name == "Test Node"
        
        print("✅ Basic functionality works correctly")
        return True
        
    except Exception as e:
        print(f"❌ Basic functionality test failed: {e}")
        return False

def main():
    """Main test function."""
    print("🚀 Marzban Central Manager - Installation Test")
    print("=" * 50)
    
    tests = [
        test_imports,
        test_utilities,
        test_basic_functionality
    ]
    
    passed = 0
    total = len(tests)
    
    for test in tests:
        if test():
            passed += 1
        print()
    
    print("=" * 50)
    print(f"📊 Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed! Installation is successful.")
        print("\n🚀 You can now run:")
        print("   ./marzban_manager.py")
        print("   python3 main.py interactive")
        return 0
    else:
        print("❌ Some tests failed. Please check the installation.")
        return 1

if __name__ == "__main__":
    sys.exit(main())