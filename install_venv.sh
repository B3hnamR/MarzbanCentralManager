#!/bin/bash

# Quick Virtual Environment Installation Script
# Marzban Central Manager v4.0

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_color() {
    echo -e "${1}${2}${NC}"
}

print_color $BLUE "🚀 Marzban Central Manager - Quick Virtual Environment Setup"
echo ""

# Check Python
if ! command -v python3 &> /dev/null; then
    print_color $RED "❌ Python 3 not found. Please install Python 3.8+"
    exit 1
fi

print_color $GREEN "✅ Python found: $(python3 --version)"

# Create virtual environment
print_color $BLUE "🔄 Creating virtual environment..."
python3 -m venv venv

# Activate virtual environment
print_color $BLUE "🔄 Activating virtual environment..."
source venv/bin/activate

# Upgrade pip
print_color $BLUE "🔄 Upgrading pip..."
pip install --upgrade pip

# Install dependencies
print_color $BLUE "🔄 Installing dependencies..."
if [[ -f "requirements.txt" ]]; then
    pip install -r requirements.txt
else
    pip install httpx>=0.25.0 click>=8.1.0 pyyaml>=6.0 tabulate>=0.9.0 psutil>=5.9.0 netifaces>=0.11.0
fi

# Create directories
print_color $BLUE "🔄 Setting up directories..."
mkdir -p config logs
chmod 755 config logs

# Make scripts executable
chmod +x marzban_manager.py main.py

# Create activation script
cat > activate_venv.sh << 'EOF'
#!/bin/bash
source venv/bin/activate
echo "🟢 Virtual environment activated"
echo "To run: ./marzban_manager.py"
EOF
chmod +x activate_venv.sh

# Test installation
print_color $BLUE "🔄 Testing installation..."
if python3 test_install.py; then
    print_color $GREEN "✅ Installation successful!"
else
    print_color $RED "❌ Installation test failed"
    exit 1
fi

echo ""
print_color $GREEN "🎉 Virtual Environment Setup Complete!"
echo ""
print_color $YELLOW "📋 To use Marzban Central Manager:"
print_color $BLUE "   1. Activate virtual environment: ./activate_venv.sh"
print_color $BLUE "   2. Run the application: ./marzban_manager.py"
echo ""
print_color $YELLOW "💡 Or run directly:"
print_color $BLUE "   ./activate_venv.sh && ./marzban_manager.py"
echo ""