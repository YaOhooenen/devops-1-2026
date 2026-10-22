#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

# TODO 1: значение port отлично от 22 (sshd может слушать несколько портов, проверяются все)
ssh_ports="$(sudo sshd -T | awk '/^port /{print $2}' | paste -sd, -)"
if [[ -n "$ssh_ports" && ",$ssh_ports," != *",22,"* ]]; then
    port_ok="yes"
else
    port_ok="no (port: ${ssh_ports:-нет})"
fi
check "Порт SSH отличен от 22 (текущий: ${ssh_ports:-нет})" "yes" "$port_ok"

# TODO 2: значение maxauthtries равно 3
check "MaxAuthTries равно 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"

# TODO 3: политика по умолчанию для входящего трафика равна deny
# Строка вида: Default: deny (incoming), allow (outgoing), disabled (routed)
check "Входящий трафик по умолчанию: deny" "deny" "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
SITE_DIR="/var/www/devops-site"
CERT="/etc/ssl/certs/devops.crt"
TLS_KEY="/etc/ssl/private/devops.key"
CERT_MIN_DAYS="${CERT_MIN_DAYS:-30}"    # порог можно завысить для проверки: CERT_MIN_DAYS=400
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
check "Конфигурация nginx корректна (nginx -t)" "0" "$(sudo nginx -t >/dev/null 2>&1; echo $?)"
check "Сертификат действителен ещё не менее ${CERT_MIN_DAYS} дн." "0" \
      "$(openssl x509 -in "$CERT" -noout -checkend $((CERT_MIN_DAYS * 86400)) >/dev/null; echo $?)"
check "В ${SITE_DIR} нет файлов, доступных для записи всем" "" \
      "$(find "$SITE_DIR" -perm -o+w | paste -sd' ' -)"
check "Права закрытого ключа TLS равны 600" "600" "$(sudo stat -c '%a' "$TLS_KEY")"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
