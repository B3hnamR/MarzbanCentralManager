#!/bin/bash
# Live Deployment Monitor
# Run this on the node server to monitor deployment progress

echo "🔍 Live Deployment Monitor"
echo "=========================="

while true; do
    clear
    echo "🔍 Live Deployment Monitor - $(date '+%H:%M:%S')"
    echo "================================================"
    
    # Container status
    echo "📦 Container Status:"
    if docker ps | grep -q marzban-node; then
        echo "   ✅ Container is running"
        docker ps | grep marzban-node | awk '{print "   📊 " $1 " - " $2 " - " $7}'
    else
        echo "   ❌ Container is not running"
        if docker ps -a | grep -q marzban-node; then
            echo "   ⚠️  Container exists but stopped"
            docker ps -a | grep marzban-node | awk '{print "   📊 " $1 " - " $2 " - " $7}'
        fi
    fi
    
    echo ""
    
    # Port status
    echo "🌐 Port Status:"
    if ss -tuln | grep -q ':62050'; then
        echo "   ✅ Port 62050 is listening"
        ss -tuln | grep ':62050' | awk '{print "   📊 " $1 " " $5}'
    else
        echo "   ❌ Port 62050 is not listening"
    fi
    
    if ss -tuln | grep -q ':62051'; then
        echo "   ✅ Port 62051 is listening"
    else
        echo "   ⚠️  Port 62051 is not listening"
    fi
    
    echo ""
    
    # Recent logs
    echo "📝 Recent Logs (last 3 lines):"
    if docker logs marzban-node --tail=3 2>/dev/null; then
        echo ""
    else
        echo "   ❌ No logs available"
    fi
    
    echo ""
    
    # Service test
    echo "🔗 Service Test:"
    local response=$(curl -k -s --connect-timeout 3 --max-time 5 -w "%{http_code}" "https://localhost:62050" -o /dev/null 2>/dev/null || echo "000")
    if [[ "$response" != "000" ]]; then
        echo "   ✅ HTTPS service responding (HTTP $response)"
    else
        echo "   ❌ HTTPS service not responding"
    fi
    
    echo ""
    echo "Press Ctrl+C to exit monitor"
    echo "Refreshing in 5 seconds..."
    
    sleep 5
done