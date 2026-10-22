# Конфигурация виртуальной машины devops-vm

Гипервизор: Oracle VirtualBox 7.2.  
Гостевая ОС: Ubuntu Server 24.04.5 LTS (ядро 6.8.0-147-generic), установка без minimized,
с OpenSSH server, без дополнительных snap-пакетов.

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Имя ВМ | `devops-vm` |
| Тип | Linux / Ubuntu (64-bit) |
| Оперативная память | 2048 МБ |
| Процессоры | 2 ядра |
| Диск | 25 ГБ, VDI, динамический |
| Разметка | LVM, корневой том `/dev/ubuntu-vg/ubuntu-lv` расширен на весь диск (≈23 ГБ) |
| Имя узла | `devops-vm`, FQDN `devops-vm.devops.local` |

Установщик по умолчанию отдаёт корневому тому только половину группы томов, поэтому после
установки том расширяется:

```bash
sudo lvextend -l +100%FREE -r /dev/ubuntu-vg/ubuntu-lv
df -h /
```

Имя узла и FQDN:

```bash
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f    # devops-vm.devops.local
```

## 2. Сетевые интерфейсы

| Адаптер VirtualBox | Тип | Интерфейс в ВМ | Адрес | Назначение |
|---|---|---|---|---|
| Адаптер 1 | NAT | `enp0s3` | `10.0.2.15/24` (DHCP) | выход в интернет (репозитории пакетов); вход на ВМ только через проброс портов |
| Адаптер 2 | Виртуальный адаптер хоста (Host-only), `VirtualBox Host-Only Ethernet Adapter` | `enp0s8` | `192.168.56.101/24` (DHCP VirtualBox) | прямой доступ с хоста: веб-сервер (ПР6), имя `devops.local` |

Адрес хоста в сети Host-only: `192.168.56.1`.

Разрешение имени на хосте (Windows, PowerShell от администратора):

```powershell
Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "192.168.56.101 devops.local"
ipconfig /flushdns
ping devops.local
```

## 3. Правило проброса портов

Адаптер 1 (NAT) → «Дополнительно» → «Проброс портов»:

| Имя | Протокол | Адрес хоста | Порт хоста | Адрес гостя | Порт гостя |
|---|---|---|---|---|---|
| `ssh` | TCP | `127.0.0.1` | `2222` | (пусто) | `2222` |

До усиления защиты SSH (снимки 01 и 02) порт гостя был `22`. После переноса sshd на 2222
(раздел 5) правило изменено на 2222 → 2222. Из командной строки хоста:

```powershell
VBoxManage modifyvm devops-vm --natpf1 delete ssh                          # ВМ выключена
VBoxManage modifyvm devops-vm --natpf1 "ssh,tcp,127.0.0.1,2222,,2222"
# для работающей ВМ: VBoxManage controlvm devops-vm natpf1 ...
```

## 4. Учётные записи

| Имя | UID | Группы | Аутентификация по SSH |
|---|---|---|---|
| `student` | 1000 | `student, adm, cdrom, sudo, dip, plugdev, lxd` | запрещена (`AllowUsers devops`); вход только в локальной консоли ВМ по паролю |
| `devops` | 1001 | `devops, sudo, users` | только по ключу ed25519 |
| `root` | 0 | — | запрещена (`PermitRootLogin no`), пароль не задан |

Создание учётной записи (в консоли ВМ под `student`):

```bash
sudo adduser devops
sudo usermod -aG sudo devops
groups devops
```

Ключ на хосте (отдельная пара, не ключ от GitHub/GitLab):

```powershell
ssh-keygen -t ed25519 -C "devops-vm-key" -f $env:USERPROFILE\.ssh\devops_vm
type $env:USERPROFILE\.ssh\devops_vm.pub | ssh devops@127.0.0.1 -p 2222 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Права на сервере: `~/.ssh` — 700, `~/.ssh/authorized_keys` — 600.  
Отпечаток ключа хоста (ED25519): `SHA256:KoBXU/5FuAC887s+yk4qkuXB7fXIInKhhyvLAIgewtw`
(проверка в консоли ВМ: `sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`).

Файл `~/.ssh/config` на хосте:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Вход: `ssh devops`; по имени из сети Host-only: `ssh -i ~/.ssh/devops_vm -p 2222 devops@devops.local`.

## 5. Служба SSH

- Версия: OpenSSH 9.6p1.
- Основной файл `/etc/ssh/sshd_config` не изменялся; эталонная копия — `/etc/ssh/sshd_config.backup`.
- Изменения вынесены в `/etc/ssh/sshd_config.d/99-hardening.conf` (root:root, 644).
- В `/etc/ssh/sshd_config.d/50-cloud-init.conf` строка `PasswordAuthentication yes`
  закомментирована: файлы читаются по алфавиту, действует первое значение, и без этого
  файл 50- перекрывал бы 99-.
- Активация по сокету отключена: `ssh.socket` — disabled, `ssh.service` — enabled.
  Иначе порт задаёт юнит `ssh.socket` (22), а не директива `Port`.

Содержимое `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
Port 2222

PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30

AllowUsers devops

X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

| Директива | Значение | Назначение |
|---|---|---|
| `Port` | 2222 | нестандартный порт, меньше шума от сканеров |
| `PermitRootLogin` | no | вход под root запрещён |
| `PasswordAuthentication` | no | только ключи |
| `PubkeyAuthentication` | yes | вход по ключу разрешён |
| `PermitEmptyPasswords` | no | пустые пароли запрещены |
| `MaxAuthTries` | 3 | не более 3 попыток за соединение |
| `LoginGraceTime` | 30 | 30 с на аутентификацию |
| `AllowUsers` | devops | вход разрешён только `devops` |
| `X11Forwarding` | no | проброс X11 не нужен |
| `ClientAliveInterval` / `ClientAliveCountMax` | 300 / 2 | разрыв зависшей сессии через ~10 мин |

Порядок применения (действующая сессия не закрывается, проверка — в новом терминале):

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo nano /etc/ssh/sshd_config.d/99-hardening.conf        # содержимое выше
sudo sed -i 's/^PasswordAuthentication yes/#PasswordAuthentication yes/' /etc/ssh/sshd_config.d/50-cloud-init.conf
sudo sshd -t && echo "Конфигурация корректна"
sudo sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)"
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd                                  # 0.0.0.0:2222 и [::]:2222
```

Затем на хосте правило проброса меняется на 2222 → 2222 (раздел 3).

Проверка с хоста:

```powershell
ssh devops                                               # успех
ssh -p 2222 root@127.0.0.1                               # Permission denied (publickey)
ssh -p 2222 -o PubkeyAuthentication=no devops@127.0.0.1  # Permission denied (publickey)
```

## 6. Правила межсетевого экрана

UFW 0.36.2, состояние `active`, журналирование `medium` (`/var/log/ufw.log`).

| Параметр | Значение |
|---|---|
| Входящие по умолчанию | deny |
| Исходящие по умолчанию | allow |
| Маршрутизируемые | disabled |

| Порт | Действие | Комментарий |
|---|---|---|
| 2222/tcp (IPv4 и IPv6) | LIMIT IN | SSH rate-limited (блокировка источника при 6 и более подключениях за 30 с) |
| 80/tcp (IPv4 и IPv6) | ALLOW IN | HTTP |
| 443/tcp (IPv4 и IPv6) | ALLOW IN | HTTPS |

Команды (правило для SSH создаётся до `ufw enable`):

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
sudo ufw status verbose
```

Не использовать `sudo ufw allow ssh`: имя `ssh` по `/etc/services` означает порт 22.

Проверка конфигурации: `scripts/audit.sh` (код возврата 0 — все проверки пройдены).

## 7. Снимки состояния

Время — московское (UTC+3).

| Снимок | Создан | Состояние |
|---|---|---|
| `01-clean-install` | 2026-10-22 01:59 | ОС установлена и обновлена (`apt update && apt upgrade`), корневой том расширен, создан `devops` с ключом; SSH на порту 22, проброс 2222 → 22 |
| `02-keys-configured` | 2026-10-22 02:12 | вход `ssh devops` по ключу через `~/.ssh/config` |
| `03-ssh-hardened` | 2026-10-22 14:36 | SSH усилен (раздел 5), порт 2222, проброс 2222 → 2222 |
| `04-nginx-https` | 2026-10-22 20:06 | Nginx, ресурс `devops.local` по HTTPS, перенаправление HTTP → HTTPS (раздел 8) |
| `05-docker-compose` | 2026-10-22 21:02 | Docker Engine, проект `~/app`: приложение + PostgreSQL, том `app_db_data` (раздел 9) |

Снимки создаются на выключенной ВМ (`sudo poweroff`).

## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Пакет | `nginx` из репозитория Ubuntu (`sudo apt install -y nginx`), версия 1.24.0 |
| Процессы | главный — `root`, рабочие — `www-data` |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site`, ссылка в `/etc/nginx/sites-enabled/` |
| Стандартный ресурс | отключён: ссылка `/etc/nginx/sites-enabled/default` удалена, файл в `sites-available` сохранён |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, каталоги 755, файлы 644 |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` |
| Сертификат | `/etc/ssl/certs/devops.crt`, `root:root`, 644; самоподписанный, CN и SAN `DNS:devops.local`, RSA 2048, срок 365 дней (до 2027-10-22) |
| Закрытый ключ | `/etc/ssl/private/devops.key`, `root:root`, 600 (каталог `/etc/ssl/private` — 700) |
| Протоколы | TLSv1.2, TLSv1.3; HSTS не используется (самоподписанный сертификат) |
| Порты | 80 — только перенаправление 301 на HTTPS; 443 — ресурс. Правила UFW из раздела 6 |

Установка и каталог ресурса:

```bash
sudo apt update && sudo apt install -y nginx
sudo mkdir -p /var/www/devops-site
sudo chown -R devops:devops /var/www/devops-site
```

Сертификат и ключ (запрос без интерактивного ввода, имя ресурса — в поле SAN):

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/devops.key \
    -out /etc/ssl/certs/devops.crt \
    -subj "/CN=devops.local" \
    -addext "subjectAltName=DNS:devops.local"
```

`openssl req` создаёт ключ с правами 600 и владельцем `root`; рабочие процессы `www-data`
ключ прочитать не могут — его загружает главный процесс при запуске.

Содержимое `/etc/nginx/sites-available/devops-site`:

```nginx
# Блок 1: перенаправление HTTP -> HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;

    return 301 https://$host$request_uri;
}

# Блок 2: ресурс по HTTPS
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;

    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;

    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

Активация (каждое изменение — только через `nginx -t && reload`, не `restart`):

```bash
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
sudo ss -tlnp | grep nginx       # 0.0.0.0:80, 0.0.0.0:443, [::]:80, [::]:443
```

Доверие к сертификату на хосте (копия по SSH — доверенный канал из раздела 4):

```bash
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
curl --cacert ~/devops.crt -I https://devops.local     # 200 OK без -k
```

Содержимое доставляется из каталога `site/` репозитория сценарием `scripts/deploy.sh`
(WSL 1 на хосте: `rsync -avz --delete --chmod=D755,F644`, одно SSH-соединение,
проверка `curl -f --cacert`). Без `--chmod` на сервер переносятся права рабочей копии
(в WSL на `/mnt/c` — 777), что позволяет `www-data` изменять файлы.

Проверка: раздел `[4] Веб-сервер` в `scripts/audit.sh`; порог срока действия
сертификата задаётся переменной `CERT_MIN_DAYS` (по умолчанию 30 дней).

## 9. Контейнеризация

| Параметр | Значение |
|---|---|
| Docker Engine | 29.9.2 из официального репозитория `download.docker.com` (пакет `docker.io` дистрибутива не используется) |
| Пакеты | `docker-ce`, `docker-ce-cli`, `containerd.io` 2.4.2, `docker-buildx-plugin`, `docker-compose-plugin` (Compose v5.6.1) |
| Группа `docker` | `devops` (у неё есть `sudo`; участник группы фактически получает права root) |
| Проект | `/home/devops/app` (владелец `devops`), доставляется из каталога `app/` репозитория |
| Файл `.env` | `/home/devops/app/.env`, `devops:devops`, 600; создаётся только на сервере, в репозитории — шаблон `.env.example` |
| Сервисы | `app` — образ `devops-app:1.0` (Flask + gunicorn, пользователь `app`, uid 999); `db` — `postgres:16-alpine` с проверкой `pg_isready` |
| Публикуемые порты | `127.0.0.1:5000 → app:5000`; порт 5432 СУБД не публикуется |
| Сеть | `app_backend` (bridge); приложение обращается к СУБД по имени `db` |
| Именованный том | `app_db_data` → `/var/lib/postgresql/data` |
| Обратный прокси | Nginx, `location /app/` в HTTPS-блоке `/etc/nginx/sites-available/devops-site` (раздел 8) |

Установка Docker Engine (по инструкции docs.docker.com/engine/install/ubuntu):

```bash
sudo apt-get update && sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops      # затем новая SSH-сессия
docker run --rm hello-world
```

Доставка проекта с хоста (WSL) и файл `.env` на сервере:

```bash
# [Хост] .env исключается: иначе --delete удалит его на сервере
rsync -avz --delete --exclude=.env app/ devops:app/

# [VM]
cd ~/app
cp .env.example .env
chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
docker compose up -d --build
docker compose ps                   # db — (healthy)
curl -s http://127.0.0.1:5000/      # Hello from Docker, Иус! Visits: N
```

Порт приложения публикуется только на `127.0.0.1`: опубликованный на `0.0.0.0` порт Docker
открывает собственными правилами iptables (цепочка `DOCKER` таблицы `nat`) в обход политики UFW
из раздела 6. `docker compose down` сохраняет том `app_db_data`, `docker compose down -v` удаляет
базу данных без возможности восстановления.

Расположение для приложения в HTTPS-блоке Nginx (копия конфигурации до изменения —
`/etc/nginx/sites-available/devops-site.bak-pr6`):

```nginx
    location /app/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

Завершающий `/` в `proxy_pass` заменяет префикс `/app/` на `/`. Проверка с хоста:

```bash
curl --cacert ~/devops.crt https://devops.local/app/          # Hello from Docker, ...
curl --cacert ~/devops.crt https://devops.local/app/health    # ok
curl --cacert ~/devops.crt -I https://devops.local/           # статический ресурс, 200 OK
```

Если контейнер приложения не принимает соединения, Nginx отвечает `502 Bad Gateway`, а в журнале
`devops-site.error.log` — `connect() failed (111: Connection refused) while connecting to upstream`.

Проверка: раздел `[5] Контейнеризация` в `scripts/audit.sh`.
