# مثال عملکرد سیستم HAProxy در Marzban Central Manager

## فایل HAProxy نمونه (قبل از افزودن نود)

```haproxy
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

# HTTP to HTTPS Redirect
frontend http_redirect
    mode http
    bind *:80
    redirect scheme https code 301

# Main HTTPS Frontend - SNI Routing
frontend https_front
    mode tcp
    bind *:443
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    # Panel routing
    use_backend panel if { req.ssl_sni -m end p.v2pro.store }

    # Primary VLESS routing
    use_backend vless_primary if { req.ssl_sni -m end node1.v2pro.store }

    # Default fallback
    default_backend panel

# Backend for Panel
backend panel
    mode tcp
    balance roundrobin
    server panel1 127.0.0.1:8443 check

# Backend for Primary VLESS
backend vless_primary
    mode tcp
    balance roundrobin
    server primary1 127.0.0.1:10011
```

## فرآیند افزودن نود جدید

### 1. کاربر نود جدید اضافه می‌کند:
```bash
Node Name: node2
Node IP: 192.168.1.100
Node Domain: node2.v2pro.store
Backend Port: 10011 (default)
```

### 2. سیستم HAProxy خودکار عمل می‌کند:

#### مرحله 1: افزودن SNI Routing Rule
```haproxy
# در بخش frontend https_front اضافه می‌شود:
use_backend node2_backend if { req.ssl_sni -m end node2.v2pro.store }
```

#### مرحله 2: افزودن Backend جدید
```haproxy
# در انتهای فایل اضافه می‌شود:

# Backend for node2
backend node2_backend
    mode tcp
    balance roundrobin
    server node2 192.168.1.100:10011
```

## فایل HAProxy نهایی (بعد از افزودن نود)

```haproxy
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

# HTTP to HTTPS Redirect
frontend http_redirect
    mode http
    bind *:80
    redirect scheme https code 301

# Main HTTPS Frontend - SNI Routing
frontend https_front
    mode tcp
    bind *:443
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    # Panel routing
    use_backend panel if { req.ssl_sni -m end p.v2pro.store }

    # Primary VLESS routing
    use_backend vless_primary if { req.ssl_sni -m end node1.v2pro.store }

    # NEW: Node2 routing - اضافه شده توسط سیستم
    use_backend node2_backend if { req.ssl_sni -m end node2.v2pro.store }

    # Default fallback
    default_backend panel

# Backend for Panel
backend panel
    mode tcp
    balance roundrobin
    server panel1 127.0.0.1:8443 check

# Backend for Primary VLESS
backend vless_primary
    mode tcp
    balance roundrobin
    server primary1 127.0.0.1:10011

# NEW: Backend for node2 - اضافه شده توسط سیستم
backend node2_backend
    mode tcp
    balance roundrobin
    server node2 192.168.1.100:10011
```

## ویژگی‌های کلیدی سیستم

### 1. **تشخیص خودکار ساختار**
- سیستم خودکار frontend اصلی را تشخیص می‌دهد
- پورت اصلی (443) را شناسایی می‌کند
- ساختار موجود را حفظ می‌کند

### 2. **افزودن ایمن**
- قبل از تغییر، بکاپ ایجاد می‌کند
- کانفیگ را اعتبارسنجی می‌کند
- در صورت خطا، به بکاپ برمی‌گردد

### 3. **همگام‌سازی خودکار**
- کانفیگ را به تمام نودها کپی می‌کند
- روی هر نود اعتبارسنجی می‌کند
- HAProxy را reload می‌کند

### 4. **حذف هوشمند**
- تمام مراجع نود را پاک می‌کند
- SNI routing rule را حذف می‌کند
- Backend section را کامل پاک می‌کند

## مثال حذف نود

### قبل از حذف:
```haproxy
# Frontend section
use_backend node2_backend if { req.ssl_sni -m end node2.v2pro.store }

# Backend section
backend node2_backend
    mode tcp
    balance roundrobin
    server node2 192.168.1.100:10011
```

### بعد از حذف:
```haproxy
# هر دو بخش کاملاً حذف می‌شوند
# فایل به حالت قبل از افزودن نود برمی‌گردد
```

## مزایای این روش

### ✅ **مزایا:**
1. **حفظ ساختار موجود**: هیچ تغییری در کانفیگ اصلی نمی‌دهد
2. **افزودن ایمن**: قبل از هر تغییر بکاپ می‌گیرد
3. **اعتبارسنجی**: کانفیگ را قبل از اعمال تست می‌کند
4. **همگام‌سازی**: تمام نودها را به‌روز نگه می‌دارد
5. **بازگشت خودکار**: در صورت خطا به حالت قبل برمی‌گردد

### 🔧 **ویژگی‌های فنی:**
1. **تشخیص هوشمند**: frontend و backend موجود را تشخیص می‌دهد
2. **افزودن دقیق**: در مکان مناسب قوانین را اضافه می‌کند
3. **حذف کامل**: تمام مراجع نود را پاک می‌کند
4. **مدیریت خطا**: در صورت مشکل، تغییرات را برمی‌گرداند

## نحوه استفاده در کد

```bash
# افزودن نود جدید
add_node_to_haproxy "node2" "192.168.1.100" "node2.v2pro.store" "10011"

# حذف نود
remove_node_from_haproxy "node2"

# همگام‌سازی با تمام نودها
sync_haproxy_to_all_nodes

# بررسی وضعیت همگامی
check_haproxy_sync_status_all_nodes
```

این سیستم کاملاً خودکار است و نیازی به دخالت دستی کاربر ندارد.