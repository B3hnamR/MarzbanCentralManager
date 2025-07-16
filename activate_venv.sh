#!/bin/bash
# Marzban Central Manager - Virtual Environment Activation Script

cd "$(dirname "$0")"

if [[ ! -d "venv" ]]; then
    echo "❌ Virtual environment not found!"
    echo "💡 Run ./install.sh to install first"
    exit 1
fi

source venv/bin/activate

echo "🟢 Virtual environment activated"
echo "📁 Location: $(pwd)/venv"
echo "🐍 Python: $(python --version)"
echo ""
echo "🚀 To run Marzban Central Manager:"
echo "   ./marzban_manager.py"
echo ""
echo "💡 To deactivate: deactivate"