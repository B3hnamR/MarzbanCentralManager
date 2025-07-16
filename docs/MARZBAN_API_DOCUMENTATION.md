# مستندات کامل API مرزبان و نحوه کار با آن

## 📚 منبع: آموزش‌های رسمی مرزبان و marzpy

این فایل شامل تمام دستورات، آموزش‌ها و نحوه کار با API مرزبان است که از مستندات رسمی و کتابخانه marzpy استخراج شده است.

---

## 🔧 **مرزبان نود (Marzban Node)**

مرزبان نود به شما اجازه می‌دهد تا بار ترافیکی را میان سرورهای مختلف پخش کنید و همچنین امکان استفاده از سرورهایی با لوکیشن‌های متفاوت را فراهم می‌کند.

### **نصب سریع (پیشنهادی)**

#### نصب معمولی:
```bash
sudo bash -c "$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban-node.sh)" @ install
```

#### نصب با نام دلخواه:
```bash
sudo bash -c "$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban-node.sh)" @ install --name marzban-node2
```

#### نصب فقط اسکریپت مدیریت:
```bash
sudo bash -c "$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban-node.sh)" @ install-script
```

#### مشاهده کامندهای مرزبان نود:
```bash
marzban-node help
```

### **نصب دستی (پیشرفته)**

#### مرحله 1: آپدیت سرور و نصب ابزارها
```bash
apt-get update; apt-get install curl socat git -y
```

#### مرحله 2: نصب Docker
```bash
curl -fsSL https://get.docker.com | sh
```

#### مرحله 3: کلون مرزبان نود
```bash
git clone https://github.com/Gozargah/Marzban-node
mkdir /var/lib/marzban-node
```

#### مرحله 4: ویرایش docker-compose.yml
```bash
cd ~/Marzban-node
nano docker-compose.yml
```

#### فایل docker-compose.yml بهینه شده:
```yaml
services:
  marzban-node:
    # build: .
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host

    # env_file: .env
    environment:
      SSL_CERT_FILE: "/var/lib/marzban-node/ssl_cert.pem"
      SSL_KEY_FILE: "/var/lib/marzban-node/ssl_key.pem"
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
      SERVICE_PROTOCOL: "rest"

    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
```

#### مرحله 5: ایجاد فایل سرتیفیکیت
```bash
nano /var/lib/marzban-node/ssl_client_cert.pem
# محتوای سرتیفیکیت را از پنل کپی کنید
```

#### مرحله 6: اجرای مرزبان نود
```bash
docker compose up -d
```

### **اتصال مرزبان نود به چند پنل**

#### حالت اول: با استفاده از Host Network
```yaml
services:
  marzban-node-panel1:
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host
    environment:
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/panel1_cert.pem"
      SERVICE_PORT: "2000"
      XRAY_API_PORT: "2001"
      SERVICE_PROTOCOL: "rest"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node

  marzban-node-panel2:
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host
    environment:
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/panel2_cert.pem"
      SERVICE_PORT: "3000"
      XRAY_API_PORT: "3001"
      SERVICE_PROTOCOL: "rest"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
```

#### حالت دوم: با استفاده از Port Mapping
```yaml
services:
  marzban-node-panel1:
    image: gozargah/marzban-node:latest
    restart: always
    environment:
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/panel1_cert.pem"
      SERVICE_PORT: "2000"
      XRAY_API_PORT: "2001"
      SERVICE_PROTOCOL: "rest"
    ports:
      - "2000:2000"
      - "2001:2001"
      - "2053:2053"
      - "2054:2054"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node

  marzban-node-panel2:
    image: gozargah/marzban-node:latest
    restart: always
    environment:
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/panel2_cert.pem"
      SERVICE_PORT: "3000"
      XRAY_API_PORT: "3001"
      SERVICE_PROTOCOL: "rest"
    ports:
      - "3000:3000"
      - "3001:3001"
      - "2096:2096"
      - "2097:2097"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
```

### **آپدیت مرزبان نود**
```bash
cd ~/Marzban-node
docker compose pull
docker compose down --remove-orphans; docker compose up -d
```

### **مدیریت مرزبان نود**

#### ری‌استارت بعد از تغییر تنظیمات:
```bash
cd ~/Marzban-node
docker compose down --remove-orphans; docker compose up -d
```

#### مشاهده لاگ‌ها:
```bash
cd ~/Marzban-node
docker compose logs -f
```

### **متغیرهای محیطی مرزبان نود**

| متغیر | مقدار پیشفرض | توضیح |
|-------|---------------|--------|
| `SERVICE_PORT` | `62050` | پورت سرویس مرزبان نود |
| `XRAY_API_PORT` | `62051` | پورت Xray Api |
| `XRAY_EXECUTABLE_PATH` | `/usr/local/bin/xray` | آدرس فایل اجرایی xray |
| `XRAY_ASSETS_PATH` | `/usr/local/share/xray` | آدرس پوشه فایل های asset |
| `SSL_CERT_FILE` | `/var/lib/marzban-node/ssl_cert.pem` | آدرس فایل certificate |
| `SSL_KEY_FILE` | `/var/lib/marzban-node/ssl_key.pem` | آدرس فایل key |
| `SSL_CLIENT_CERT_FILE` | - | آدرس فایل certificate کاربر |
| `DEBUG` | `False` | فعالسازی حالت توسعه |
| `SERVICE_PROTOCOL` | `rpyc` | پروتکل سرویس مرزبان نود |

---

## 🌐 **API مرزبان**

### **فعالسازی API**

#### در فایل .env:
```env
DOCS=True
```

#### دسترسی به مستندات API:
```
https://domain.xxx:port/docs
```

### **Endpoints اصلی API**

| Endpoint | Method | توضیح |
|----------|--------|--------|
| `/api/admin/token` | POST | دریافت توکن احراز هویت |
| `/api/admin` | GET | اطلاعات admin فعلی |
| `/api/admins` | GET | لیست تمام admin‌ها |
| `/api/admin` | POST | ایجاد admin جدید |
| `/api/admin/{username}` | PUT | ویرایش admin |
| `/api/admin/{username}` | DELETE | حذف admin |
| `/api/users` | GET | لیست کاربران |
| `/api/user` | POST | افزودن کاربر |
| `/api/user/{username}` | GET | اطلاعات کاربر |
| `/api/user/{username}` | PUT | ویرایش کاربر |
| `/api/user/{username}` | DELETE | حذف کاربر |
| `/api/user/{username}/reset` | POST | ریست مصرف کاربر |
| `/api/users/reset` | POST | ریست مصرف همه کاربران |
| `/api/user/{username}/usage` | GET | آمار مصرف کاربر |
| `/api/nodes` | GET | لیست نودها |
| `/api/node` | POST | افزودن نود |
| `/api/node/{node_id}` | GET | اطلاعات نود |
| `/api/node/{node_id}` | PUT | ویرایش نود |
| `/api/node/{node_id}` | DELETE | حذف نود |
| `/api/node/{node_id}/reconnect` | POST | اتصال مجدد نود |
| `/api/nodes/usage` | GET | آمار مصرف نودها |
| `/api/system` | GET | آمار سیستم |
| `/api/inbounds` | GET | لیست inbounds |
| `/api/hosts` | GET | لیست hosts |
| `/api/hosts` | PUT | ویرایش hosts |
| `/api/core` | GET | آمار core |
| `/api/core/restart` | POST | ری‌استارت core |
| `/api/core/config` | GET | تنظیمات core |
| `/api/core/config` | PUT | ویرایش تنظیمات core |
| `/api/user-template` | GET | لیست templates |
| `/api/user-template` | POST | افزودن template |
| `/api/user-template/{id}` | GET | اطلاعات template |
| `/api/user-template/{id}` | PUT | ویرایش template |
| `/api/user-template/{id}` | DELETE | حذف template |

---

## 🐍 **کتابخانه marzpy**

### **نصب**
```bash
pip install marzpy --upgrade
```

### **استفاده پایه**
```python
from marzpy import Marzban
import asyncio
        
async def main():
    panel = Marzban("username","password","https://example.com")
    token = await panel.get_token()
    #await panel.anyfunction(token)

asyncio.run(main())
```

### **ویژگی‌های کتابخانه**

#### Admin Management:
- get token
- get admin
- create admin
- modify admin
- remove admin
- get all admins

#### Subscription:
- user subscription
- user subscription info

#### System:
- get system stats
- get inbounds
- get hosts
- modify hosts

#### Core:
- get core stats
- restart core
- get core config
- modify core config

#### User Management:
- add user
- get user
- modify user
- remove user
- reset user data usage
- reset all users data usage
- get all users
- get user usage

#### User Template:
- get all user templates
- add user template
- get user template
- modify user template
- remove user template

#### Node Management:
- add node
- get node
- modify node
- remove node
- get all nodes
- reconnect node
- get all nodes usage

### **مثال‌های کاربردی**

#### دریافت توکن:
```python
from marzpy import Marzban

panel = Marzban("username","password","https://example.com")
mytoken = await panel.get_token()
```

#### دریافت admin فعلی:
```python
admin = await panel.get_current_admin(token=mytoken)
print(admin) #output: {'username': 'admin', 'is_sudo': True}
```

#### ایجاد admin:
```python
info = {'username':'test','password':'password','is_sudo':False}
result = await panel.create_admin(token=mytoken,data=info)
print(result) #output: success
```

#### ویرایش admin:
```python
target_admin = "test"
info = {'password':'newpassword','is_sudo':False}
result = await panel.change_admin_password(username=target_admin,token=mytoken,data=info)
print(result) #output: success
```

#### حذف admin:
```python
target_admin = "test"
result = await panel.delete_admin(username=target_admin,token=mytoken)
print(result) #output: success
```

#### لیست همه admin‌ها:
```python
result = await panel.get_all_admins(token=mytoken)
print(result) 
#output: [{'username': 'test', 'is_sudo': True}, {'username': 'test1', 'is_sudo': False}]
```

#### دریافت subscription کاربر:
```python
subscription_url = "https://sub.yourdomain.com/sub/TOKEN"
result = await panel.get_subscription(subscription_url)
print(result) #output: Configs
```

#### اطلاعات subscription:
```python
subscription_url = "https://sub.yourdomain.com/sub/TOKEN"
result = await panel.get_subscription_info(subscription_url)
print(result) #output: User information (usage,links,inbounds,....)
```

#### آمار سیستم:
```python
result = await panel.get_system_stats(token=mytoken)
print(result) #output: system stats Memory & CPU usage ...
```

#### لیست inbounds:
```python
result = await panel.get_inbounds(token=mytoken)
print(result) #output: list of inbounds
```

#### لیست hosts:
```python
result = await panel.get_hosts(token=mytoken)
print(result) #output: list of hosts
```

#### ویرایش hosts:
```python
hosts = {
  "VMess TCP": [
    {
      "remark": "somename",
      "address": "someaddress",
      "port": 0,
      "sni": "somesni",
      "host": "somehost",
      "security": "inbound_default",
      "alpn": "",
      "fingerprint": ""
    }
  ]
}
# **Backup first**
result = await panel.modify_hosts(token=mytoken,data=hosts)
print(result) #output: hosts
```

#### آمار Core:
```python
result = await panel.get_xray_core(token=mytoken)
print(result)
 #output: {'version': '1.8.1', 'started': True, 'logs_websocket': '/api/core/logs'}
```

#### ری‌استارت Core:
```python
result = await panel.restart_xray_core(token=mytoken)
print(result)
 #output: success
```

#### تنظیمات Core:
```python
result = await panel.get_xray_config(token=mytoken)
print(result) #output: your xray core config
```

#### ویرایش تنظیمات Core:
```python
new_config={"your config"}
result = await panel.modify_xray_config(token=mytoken,config=new_config)
print(result) #output: success
```

#### افزودن کاربر:
```python
from marzpy.api.user import User

user = User(
    username="Mewhrzad",
    proxies={
        "vmess": {"id": "35e7e39c-7d5c-1f4b-8b71-508e4f37ff53"},
        "vless": {"id": "35e7e39c-7d5c-1f4b-8b71-508e4f37ff53"},
    },
    inbounds={"vmess": ["VMess TCP"], "vless": ["VLESS TCP REALITY"]},
    expire=0,
    data_limit=0,
    data_limit_reset_strategy="no_reset",
    status="active"
)
result = await panel.add_user(user=user, token=token) #return new User object

print(result.username) #-> Mewhrzad
```

#### دریافت کاربر:
```python
result = await panel.get_user("Mewhrzad",token=mytoken) #return User object
print(result.subscription_url)
```

#### ویرایش کاربر:
```python
new_user = User(
    username="test",
    proxies={
        "vmess": {"id": "35e4e39c-7d5c-4f4b-8b71-558e4f37ff53"},
        "vless": {"id": "35e4e39c-7d5c-4f4b-8b71-558e4f37ff53"},
    },
    inbounds={"vmess": ["VMess TCP"], "vless": ["VLESS TCP REALITY"]},
    expire=0,
    data_limit=0,
    data_limit_reset_strategy="no_reset",
    status="active",
)
result = await panel.modify_user("Mewhrzad", token=mytoken, user=new_user)
print(result.subscription_url) #output: modified user object
```

#### حذف کاربر:
```python
result = await panel.delete_user("test", token=mytoken)
print(result) #output: success
```

#### ریست مصرف کاربر:
```python
result = await panel.reset_user_traffic("test", token=mytoken)
print(result) #output: success
```

#### ریست مصرف همه کاربران:
```python
result = await panel.reset_all_users_traffic(token=mytoken)
print(result) #output: success
```

#### لیست همه کاربران:
```python
result = await panel.get_all_users(token=mytoken) #return list of users
for user in result:
    print(user.username) 
```

#### آمار مصرف کاربر:
```python
result = await panel.get_user_usage("mewhrzad",token=mytoken)
print(result) 
#output: [{'node_id': None, 'node_name': 'MTN', 'used_traffic': 0}, 
#{'node_id': 1, 'node_name': 'MCI', 'used_traffic': 0}]
```

#### لیست همه templates:
```python
result = await panel.get_all_templates(token=mytoken) #return template list object
for template in result:
    print(template.name)
```

#### افزودن template:
```python
from marzpy.api.template import Template

temp = Template(
    name="new_template",
    inbounds={"vmess": ["VMESS TCP"], "vless": ["VLESS TCP REALITY"]},
    data_limit=0,
    expire_duration=0,
    username_prefix=None,
    username_suffix=None,
)
result = await panel.add_template(token=mytoken, template=temp)  # return new Template object
print(result.name) #output: new_template
```

#### دریافت template:
```python
template_id = 11
result = await panel.get_template_by_id(token=mytoken, id=template_id) # return Template object
print(result.name) #output: new_template
```

#### ویرایش template:
```python
from marzpy.api.template import Template

temp = Template(
    name="new_template2",
    inbounds={"vmess": ["VMESS TCP"], "vless": ["VLESS TCP REALITY"]},
    data_limit=0,
    expire_duration=0,
    username_prefix=None,
    username_suffix=None,
)
result = await panel.modify_template_by_id(
    id=1, token=mytoken, template=temp)  # return Modified Template object
print(result.name) #output: new_template2
```

#### حذف template:
```python
result = await panel.delete_template_by_id(id=1, token=mytoken)
print(result) #output: success
```

#### افزودن نود:
```python
from marzpy.api.node import Node

my_node = Node(
    name="somename",
    address="test.example.com",
    port=62050,
    api_port=62051,
    certificate="your_cert",
    id=4,
    xray_version="1.8.1",
    status="connected",
    message="string",
)

result = await panel.add_node(token=mytoken, node=my_node)  # return new Node object
print(result.address)
```

#### دریافت نود:
```python
result = await panel.get_node_by_id(id=1, token=mytoken)  # return exist Node object
print(result.address) #output: address of node 1
```

#### ویرایش نود:
```python
from marzpy.api.node import Node

my_node = Node(
    name="somename",
    address="test.example.com",
    port=62050,
    api_port=62051,
    certificate="your_cert",
    id=4,
    xray_version="1.8.1",
    status="connected",
    message="string",
)

result = await panel.modify_node_by_id(id=1, token=mytoken,node=my_node)  # return modified Node object
print(result.address) #output:test.example.com
```

#### حذف نود:
```python
result = await panel.delete_node(id=1, token=mytoken)
print(result) #output: success
```

#### لیست همه نودها:
```python
result = await panel.get_all_nodes(token=mytoken)  # return List of Node object
for node in result:
    print(node.address)
```

#### اتصال مجدد نود:
```python
result = await panel.reconnect_node(id=1,token=mytoken)
print(result) #output: success
```

#### آمار مصرف نودها:
```python
result = await panel.get_nodes_usage(token=mytoken)
for node in result:
    print(node)
#output:{'node_id': 1, 'node_name': 'N1', 'uplink': 1000000000000, 'downlink': 1000000000000}
# {'node_id': 2, 'node_name': 'N2', 'uplink': 1000000000000, 'downlink': 1000000000000}
```

---

## 🔧 **نکات فنی و بهترین روش‌ها**

### **امنیت API**
- همیشه از HTTPS استفاده کنید
- توکن‌ها را امن نگهداری کنید
- از rate limiting استفاده کنید
- لاگ‌های حساس را مخفی کنید

### **مدیریت خطا**
- همیشه response codes را بررسی کنید
- از try-catch استفاده کنید
- retry mechanism پیاده‌سازی کنید
- timeout مناسب تنظیم کنید

### **بهینه‌سازی عملکرد**
- از pagination استفاده کنید
- connection pooling پیاده‌سازی کنید
- cache مناسب استفاده کنید
- async operations استفاده کنید

### **مانیتورینگ**
- وضعیت نودها را مداوم بررسی کنید
- لاگ‌ها را منظم بررسی کنید
- آمار مصرف را ردیابی کنید
- backup منظم بگیرید

---

## 📋 **چک لیست پیاده‌سازی**

### ✅ **نصب و راه‌اندازی**
- [ ] نصب مرزبان نود
- [ ] تنظیم SSL certificates
- [ ] پیکربندی docker-compose
- [ ] تست اتصال به پنل

### ✅ **API Integration**
- [ ] فعالسازی API در پنل
- [ ] تست احراز هویت
- [ ] پیاده‌سازی error handling
- [ ] تنظیم rate limiting

### ✅ **مدیریت کاربران**
- [ ] CRUD operations
- [ ] مدیریت templates
- [ ] ریست مصرف داده
- [ ] آمارگیری

### ✅ **مدیریت نودها**
- [ ] افزودن/حذف نود
- [ ] مانیتورینگ وضعیت
- [ ] اتصال مجدد
- [ ] آمار مصرف

### ✅ **امنیت**
- [ ] مخفی‌سازی credentials
- [ ] validation ورودی‌ها
- [ ] لاگ امن
- [ ] backup منظم

---

## 🔗 **منابع و مراجع**

### **مستندات رسمی:**
- [Marzban Documentation](https://github.com/Gozargah/Marzban)
- [Marzban Node Documentation](https://github.com/Gozargah/Marzban-node)
- [Marzban Scripts](https://github.com/Gozargah/Marzban-scripts)

### **کتابخانه‌ها:**
- [marzpy Library](https://github.com/ErfanTech/marzpy)
- [Python aiohttp](https://docs.aiohttp.org/)

### **ابزارها:**
- [jq - JSON processor](https://stedolan.github.io/jq/)
- [curl - Command line tool](https://curl.se/)
- [Docker](https://docs.docker.com/)

---

**تاریخ ایجاد:** $(date)  
**نسخه:** Professional Edition v3.1  
**منبع:** مستندات رسمی مرزبان و marzpy  
**پروژه:** MarzbanCentralManager by B3hnamR