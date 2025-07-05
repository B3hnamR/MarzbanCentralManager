# Marzban Central Manager - API Features Documentation

## 🚀 نسخه Professional Edition v3.1 - ویژگی‌های API جدید

این مستند ویژگی‌های جدید API که بر اساس مستندات رسمی مرزبان و کتابخانه marzpy پیاده‌سازی شده‌اند را شرح می‌دهد.

## 📋 فهرست ویژگی‌های جدید

### 🔐 **مدیریت Admin**
- ✅ دریافت اطلاعات admin فعلی
- ✅ لیست تمام admin‌ها
- ✅ ایجاد admin جدید
- ✅ ویرایش admin موجود
- ✅ حذف admin

### 👥 **مدیریت کاربران پیشرفته**
- ✅ لیست کاربران با pagination
- ✅ افزودن کاربر جدید
- ✅ ویرایش کاربر موجود
- ✅ حذف کاربر
- ✅ ریست مصرف داده کاربر
- ✅ ریست مصرف داده تمام کاربران
- ✅ دریافت آ��ار مصرف کاربر
- ✅ دریافت subscription کاربر

### 🏗️ **مدیریت Core**
- ✅ دریافت آمار core
- ✅ restart کردن Xray core
- ✅ دریافت تنظیمات core
- ✅ ویرایش تنظیمات core
- ✅ دریافت لاگ‌های core

### 🌐 **مدیریت سیستم**
- ✅ دریافت inbounds
- ✅ دریافت hosts
- ✅ ویرایش hosts

### 🔗 **مدیریت Node پیشرفته**
- ✅ reconnect کردن node
- ✅ دریافت آمار مصرف nodes
- ✅ دریافت آمار مصرف node خاص
- ✅ بررسی connectivity node
- ✅ انتظار برای آماده شدن node

### 📋 **مدیریت Template**
- ✅ لیست تمام templates
- ✅ دریافت template با ID
- ✅ افزودن template جدید
- ✅ ویرایش template موجود
- ✅ حذف template
- ✅ ایجاد template به صورت تعاملی
- ✅ ویرایش template به صورت تعاملی

### 📱 **ابزارهای Subscription**
- ✅ دریافت subscription کاربر
- ✅ دریافت اطلاعات subscription
- ✅ استخراج username از URL
- ✅ اعتبارسنجی URL
- ✅ دریافت configs در فرمت‌های مختلف
- ✅ تجزیه و تحلیل subscription
- ✅ تست دسترسی subscription
- ✅ دانل��د configs

## 🛠️ نحوه استفاده

### 1. **مدیریت کاربران**

#### لیست کاربران:
```bash
./marzban_central_manager.sh --list-users
```

#### حذف کاربر (تعاملی):
```bash
# از منوی اصلی گزینه 28 را انتخاب کنید
```

#### ریست مصرف داده:
```bash
# از منوی اصلی گزینه 29 را انتخاب کنید
```

### 2. **مدیریت Template**

#### لیست templates:
```bash
./marzban_central_manager.sh --list-templates
```

#### ایجاد template جدید:
```bash
# از منوی اصلی گزینه 31 را انتخاب کنید
```

#### مثال ایجاد template:
```json
{
  "name": "VIP_Template",
  "inbounds": {
    "vmess": ["VMess TCP"],
    "vless": ["VLESS TCP REALITY"]
  },
  "data_limit": 107374182400,
  "expire_duration": 2592000,
  "username_prefix": "vip_",
  "username_suffix": "_user"
}
```

### 3. **ابزارهای Subscription**

#### تجزیه و تحلیل subscription:
```bash
./marzban_central_manager.sh --analyze-subscription "https://panel.example.com/sub/TOKEN"
```

#### تست دسترسی:
```bash
# از منوی اصلی گزینه 35 را انتخاب کنید
```

#### دانلود configs:
```bash
# از منوی اصلی گزینه 36 را انتخاب کنید
```

## 📊 فرمت‌های پشتیبانی شده

### Subscription Formats:
- **base64** (��یشفرض)
- **clash**
- **sing-box**
- **outline**

### مثال استفاده:
```bash
# دریافت در فرمت clash
get_subscription_configs "URL" "clash"

# دریافت در فرمت sing-box
get_subscription_configs "URL" "sing-box"
```

## 🔧 API Functions جدید

### User Management:
```bash
# لیست کاربران با pagination
get_all_users [offset] [limit]

# افزودن کاربر
add_user "$user_json_data"

# ویرایش کاربر
modify_user "$username" "$user_json_data"

# حذف کاربر
delete_user "$username"

# ریست مصرف داده
reset_user_data_usage "$username"
reset_all_users_data_usage

# دریافت آمار مصرف
get_user_usage "$username"
```

### Template Management:
```bash
# لیست templates
get_all_templates

# دریافت template با ID
get_template_by_id "$template_id"

# افزودن template
add_template "$template_json_data"

# ویرایش template
modify_template_by_id "$template_id" "$template_json_data"

# حذف template
delete_template_by_id "$template_id"
```

### Subscription Tools:
```bash
# دریافت subscription
get_user_subscription "$subscription_url" [format]

# دریافت اطلاعات subscription
get_user_subscription_info "$subscription_url"

# استخراج username
extract_username_from_subscription "$subscription_url"

# تجزیه و تحلیل
analyze_subscription_info "$subscription_url"

# تست دسترسی
test_subscription_access "$subscription_url"
```

### Node Management:
```bash
# reconnect node
reconnect_node "$node_id"

# دریافت آمار nodes
get_nodes_usage

# دریافت آمار node خاص
get_node_usage "$node_id"

# بررسی connectivity
check_node_connectivity "$node_id"

# انتظار برای آماده شدن
wait_for_node_ready "$node_id" [max_attempts] [wait_interval]
```

## 🎯 ویژگی‌های تعاملی

### 1. **ایجاد Template تعاملی**
- راهنمای گام به گام
- نمایش inbounds موجود
- اعتبارسنجی JSON
- پیش‌نمایش template

### 2. **تجزیه و تحلیل Subscription**
- نمایش اطلاعات کاربر
- آمار مصرف با درصد
- وضعیت انقضا
- تعداد configs موجود

### 3. **مدیریت کاربران**
- لیست فرمت شده
- تأیید حذف
- گزینه‌های ریست مختلف

## 🔒 امنیت و اعتبارسنجی

### ویژگی‌های امنیتی:
- ✅ اعتبارسنجی ورودی‌ها
- ✅ تأیید عملیات حساس
- ✅ مخفی‌سازی اطلاعات حساس در لاگ
- ✅ Timeout management
- ✅ Error handling جامع

### اعتبارسنجی‌ها:
- ✅ فرمت JSON
- ✅ فرمت URL
- ✅ ID های عددی
- ✅ Username patterns
- ✅ Data limits

## 📈 بهبودهای عملکرد

### Optimization:
- ✅ Pagination برای لیست‌های بزرگ
- ✅ Caching برای API calls
- ✅ Rate limiting
- ✅ Connection pooling
- ✅ Retry mechanism

### Memory Management:
- ✅ Efficient JSON parsing
- ✅ Stream processing برای فایل‌های بزرگ
- ✅ Cleanup temporary files

## 🚀 استفاده پیشرفته

### Command Line Integration:
```bash
# ترکیب با سایر ابزارها
./marzban_central_manager.sh --list-users | jq '.[] | select(.status=="active")'

# فیلتر کاربران فعال
./marzban_central_manager.sh --list-users | jq '.[] | select(.data_limit > 0)'

# آمار کلی
./marzban_central_manager.sh --list-users | jq 'length'
```

### Automation Scripts:
```bash
#!/bin/bash
# مثال اسکریپت خودکار

# بررسی کاربران منقضی شده
expired_users=$(./marzban_central_manager.sh --list-users | jq -r '.[] | select(.status=="expired") | .username')

for user in $expired_users; do
    echo "Processing expired user: $user"
    # عملیات مورد نظر
done
```

## ���� ویژگی‌های آینده

### در حال توسعه:
- [ ] **User Creation Wizard** - ایجاد کاربر با template
- [ ] **Bulk User Operations** - عملیات گروهی
- [ ] **Advanced Filtering** - فیلترهای پیشرفته
- [ ] **Export/Import Users** - خروجی/ورودی کاربران
- [ ] **Subscription Analytics** - آنالیز پیشرفته
- [ ] **Real-time Monitoring** - مانیتورینگ زنده

### برنامه‌ریزی شده:
- [ ] **Web Dashboard** - رابط وب
- [ ] **REST API Server** - سرور API
- [ ] **Mobile App** - اپلیکیشن موبایل
- [ ] **Grafana Integration** - یکپارچگی با Grafana

## 📞 پشتیبانی

### مشکلات رایج:

#### خطای API Connection:
```bash
# بررسی تنظیمات API
./marzban_central_manager.sh
# گزینه 18: Show API Status
```

#### خطای JSON Parsing:
```bash
# بررسی فرمت JSON
echo "$json_data" | jq .
```

#### خطای Subscription URL:
```bash
# تست دسترسی
curl -I "subscription_url"
```

### لاگ‌ها:
```bash
# مشاهده لاگ‌های سیستم
./marzban_central_manager.sh
# گزینه 22: View System Logs
```

---

**نکته:** این ویژگی‌ها بر اساس API رسمی مرزبان و بهترین practices پیاده‌سازی شده‌اند و با نسخه‌های جدید مرزبان سازگار هستند.

**نسخه:** Professional Edition v3.1  
**تاریخ بروزرسانی:** $(date)  
**نویسنده:** B3hnamR