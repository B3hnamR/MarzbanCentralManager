#!/bin/bash
# Marzban Central Manager - Quick Run Script

# Change to script directory
cd "$(dirname "$0")"

# Check if virtual environment exists
if [[ ! -f "venv/bin/activate" ]]; then
    echo "❌ Virtual environment not found!"
    echo "💡 Run ./install.sh to install first"
    exit 1
fi

# Activate virtual environment
source venv/bin/activate

# Check if main script exists
if [[ ! -f "marzban_manager.py" ]]; then
    echo "❌ marzban_manager.py not found!"
    echo "💡 Make sure you're in the correct directory"
    exit 1
fi

# Run the application
exec python3 marzban_manager.py "$@"