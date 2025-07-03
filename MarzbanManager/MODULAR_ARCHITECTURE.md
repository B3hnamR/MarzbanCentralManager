# Marzban Central Manager - Modular Architecture v3.1

## 🏗️ ساختار ماژولار جدید

این پروژه به ساختار ماژولار حرفه‌ای بازطراحی شده است تا نگهداری، توسعه و دیباگ آن آسان‌تر باشد.

## 📁 ساختار دایرکتوری

```
MarzbanManager/
├── marzban_central_manager_new.sh    # فایل اصلی جدید (ماژولار)
├── marzban_central_manager.sh        # فایل قدیمی (برای مقایسه)
├── marzban_node_deployer_fixed.sh    # اسکریپت نصب نود
├── migrate_to_modular.sh             # اسکریپت مهاجرت
├── MODULAR_ARCHITECTURE.md           # این فایل
└── lib/                               # کتابخانه ماژول‌ها
    ├── core/                          # ماژول‌های هسته
    │   ├── config.sh                  # مدیریت پیکربندی
    │   ├── logger.sh                  # سیستم لاگ
    │   ├── utils.sh                   # توابع کمکی
    │   └── dependencies.sh            # مدیریت وابستگی‌ها
    ├── api/                           # ماژول‌های API
    │   ├── marzban_api.sh            # API مرزبان
    │   └── telegram_api.sh           # API تلگرام
    ├── nodes/                         # مدیریت نودها
    │   ├── node_manager.sh           # مدیریت نودها
    │   └── ssh_operations.sh         # عملیات SSH
    ├── backup/                        # سیستم بکاپ
    │   └── backup_manager.sh         # مدیریت بکاپ
    ├── sync/                          # همگام‌سازی (آینده)
    │   └── sync_manager.sh           # مدیریت همگام‌سازی
    └── monitoring/                    # مانیتورینگ (آینده)
        └── monitor_manager.sh        # مدیریت مانیتورینگ
```

## 🧩 ماژول‌های اصلی

### 1. Core Modules (ماژول‌های هسته)

#### `config.sh` - مدیریت پیکربندی
- مدیریت متغیرهای سراسری
- بارگذاری و ذخیره تنظیمات
- اعتبارسنجی پیکربندی
- مدیریت دایرکتوری‌ها

#### `logger.sh` - سیستم لاگ
- سی��تم لاگ رنگی و زمان‌دار
- سطوح مختلف لاگ (DEBUG, INFO, WARNING, ERROR, SUCCESS)
- مخفی‌سازی اطلاعات حساس
- چرخش فایل‌های لاگ

#### `utils.sh` - توابع کمکی
- توابع سیستمی
- اعتبارسنجی ورودی‌ها
- عملیات فایل
- مدیریت فرآیندها

#### `dependencies.sh` - مدیریت وابستگی‌ها
- بررسی وابستگی‌ها
- نصب خودکار بسته‌ها
- مدیریت نسخه‌ها

### 2. API Modules (ماژول‌های API)

#### `marzban_api.sh` - API مرزبان
- احراز هویت و مدیریت توکن
- عملیات نود (افزودن، حذف، بروزرسانی)
- مدیریت کاربران
- دریافت آمار سیستم

#### `telegram_api.sh` - API تلگرام
- ارسال پیام‌ها
- مدیریت سطوح اطلاع‌رسانی
- قالب‌بندی پیام‌ها
- مدیریت خطاها

### 3. Node Management (مدیریت نودها)

#### `node_manager.sh` - مدیریت نودها
- افزودن و حذف نودها
- بروزرسانی پیکربندی
- مانیتورینگ سلامت
- مدیریت گواهی‌ها

#### `ssh_operations.sh` - عملیات SSH
- اتصال SSH با retry
- انتقال فایل (SCP/Rsync)
- عملیات دسته‌ای
- مدیریت کلیدهای SSH

### 4. Backup System (سیستم بکاپ)

#### `backup_manager.sh` - مدیریت بکاپ
- بکاپ کامل سیستم
- بکاپ انتخابی
- فشرده‌سازی هوشمند
- سیاست نگهداری
- بکاپ خودکار

## 🔧 مزایای ساختار ماژولار

### 1. **قابلیت نگهداری بالا**
- هر ماژول مسئولیت مشخصی دارد
- کد تمیز و سازماندهی شده
- آسان‌تر برای دیباگ

### 2. **قابلیت توسعه**
- افزودن ویژگی جدید بدون تغییر کد موجود
- ماژول‌های مستقل
- امکان تست جداگانه

### 3. **استفاده مجدد**
- ماژول‌ها قابل استفاده در پروژه‌های دیگر
- API یکپارچه
- مستندسازی بهتر

### 4. **مدیریت خطا بهتر**
- خطاها در سطح ماژول مدیریت می‌شوند
- لاگ‌گیری دقیق‌تر
- بازیابی آسان‌تر

## 🚀 نحوه استفاده

### اجرای فایل جدید:
```bash
# اجرای حالت ت��املی
./marzban_central_manager_new.sh

# اجرای دستورات خاص
./marzban_central_manager_new.sh --backup-full
./marzban_central_manager_new.sh --monitor-health
./marzban_central_manager_new.sh --update-certificates
```

### بارگذاری ماژول‌ها در اسکریپت‌های دیگر:
```bash
# بارگذاری ماژول خاص
source lib/core/logger.sh
source lib/api/marzban_api.sh

# استفاده از توابع
log_info "This is a test message"
get_marzban_token
```

## 🔄 مهاجرت از نسخه قدیمی

### 1. **تست نسخه جدید**
```bash
# تست عملکرد
./marzban_central_manager_new.sh --dependency-check
./marzban_central_manager_new.sh --version
```

### 2. **انتقال تنظیمات**
تنظیمات موجود به طور خودکار بارگذاری می‌شوند.

### 3. **جایگزینی فایل اصلی**
```bash
# پشتیبان‌گیری از فایل قدیمی
cp marzban_central_manager.sh marzban_central_manager_old.sh

# جایگزینی
mv marzban_central_manager_new.sh marzban_central_manager.sh
chmod +x marzban_central_manager.sh
```

## 🛠️ توسعه و سفارشی‌سازی

### افزودن ماژول جدید:

1. **ایجاد فایل ماژول:**
```bash
# مثال: ماژول مدیریت SSL
touch lib/ssl/ssl_manager.sh
```

2. **ساختار ماژول:**
```bash
#!/bin/bash
# SSL Management Module
# Professional Edition v3.1
# Author: B3hnamR

# توابع عمومی
init_ssl_manager() {
    log_debug "SSL manager initialized"
    return 0
}

# توابع اختصاصی
generate_ssl_certificate() {
    # کد تولید گواهی
}
```

3. **اضافه کردن به فایل اصلی:**
```bash
# در تابع load_all_modules
local ssl_modules=(
    "$LIB_DIR/ssl/ssl_manager.sh"
)
```

### سفارشی‌سازی لاگ:
```bash
# تغییر سطح لاگ
set_log_level "DEBUG"

# لاگ سفارشی
log_custom() {
    local message="$1"
    echo -e "[$(date '+%H:%M:%S')] 🔧 CUSTOM: $message"
}
```

## 📋 TODO و ویژگی‌های آینده

### ماژول‌های در حال توسعه:
- [ ] `sync_manager.sh` - همگام‌سازی پیشرفته
- [ ] `monitor_manager.sh` - مانیتورینگ مداوم
- [ ] `ssl_manager.sh` - مدیریت گواهی‌های SSL
- [ ] `nginx_manager.sh` - مدیریت Nginx
- [ ] `haproxy_manager.sh` - مدیریت HAProxy

### بهبودهای برنامه‌ریزی شده:
- [ ] رابط وب
- [ ] API RESTful
- [ ] پشتیبانی از Docker Compose
- [ ] مانیتورینگ Prometheus
- [ ] داشبورد Grafana

## 🤝 مشارکت

برای مشارکت در توسعه:

1. **Fork** کردن پروژه
2. ایجاد **branch** جدید برای ویژگی
3. **Commit** تغییرات با توضیحات واضح
4. ارسال **Pull Request**

### استانداردهای کدنویسی:
- استفاده از `set -euo pipefail`
- نام‌گذاری واضح برای توابع
- کامنت‌گذاری مناسب
- مدیریت خطای جامع
- تست قبل از commit

## 📞 پشتیبانی

- **GitHub Issues:** برای گزارش مشکلات
- **Discussions:** برای سوالات عمومی
- **Email:** behnamrjd@gmail.com

---

**نکته:** این ساختار ماژولار امکان توسعه و نگهداری آسان‌تر پروژه را فراهم می‌کند. هر ماژول مستقل عمل کرده و قابلیت استفاده مجدد دارد.

**نسخه:** Professional Edition v3.1  
**نویسنده:** B3hnamR  
**تاریخ بروزرسانی:** $(date)