# بررسی مسیر فایل‌های Node Deployer

## ساختار فایل‌ها:
```
MarzbanManager/
├── marzban_central_manager.sh          # اسکریپت اصلی
├── marzban_node_deployer_fixed.sh      # فایل deployer (هدف)
└── lib/
    └── nodes/
        ├── node_manager.sh              # فایل منبع
        └── node_manager_with_haproxy.sh # فایل منبع
```

## مسیرهای محاسبه شده:

### وقتی اسکریپت از `lib/nodes/node_manager.sh` اجرا می‌شود:
- `$0` = `lib/nodes/node_manager.sh`
- `$(dirname "$0")` = `lib/nodes`
- `$(dirname "$(dirname "$0")")` = `lib`
- `$(dirname "$(dirname "$0")")/marzban_node_deployer_fixed.sh` = `lib/marzban_node_deployer_fixed.sh` ❌

### مسیر صحیح باید باشد:
- از `lib/nodes` به `MarzbanManager` = `../../`
- مسیر صحیح: `$(dirname "$(dirname "$(dirname "$0")")")/marzban_node_deployer_fixed.sh`

## مشکل:
فایل `marzban_node_deployer_fixed.sh` در مسیر `MarzbanManager/` است، نه `lib/`

## راه‌حل:
باید از `$(dirname "$(dirname "$(dirname "$0")")")` استفاده کنیم یا مسیر مطلق.