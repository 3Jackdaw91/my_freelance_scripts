#!/bin/bash
set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Проверка root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Скрипт нужно запускать с правами root (sudo)!${NC}"
   exit 1
fi

RECOMMENDATIONS=()

print_header() {
    echo
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
}

print_ok() {
    echo -e "  ${GREEN}[OK]${NC} $1"
}

print_warn() {
    echo -e "  ${YELLOW}[!]${NC} $1"
    RECOMMENDATIONS+=("$1")
}

print_bad() {
    echo -e "  ${RED}[!!]${NC} $1"
    RECOMMENDATIONS+=("$1")
}

print_info() {
    echo -e "  ${CYAN}[i]${NC} $1"
}

echo -e "${BOLD}Аудит безопасности сервера — $(date)${NC}"
echo -e "Хост: $(hostname) | IP: $(hostname -I | awk '{print $1}')"

# ============================================================
print_header "1. Информация о системе"
# ============================================================
echo -e "  ОС:           $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
echo -e "  Ядро:         $(uname -r)"
echo -e "  Архитектура:  $(uname -m)"
echo -e "  Аптайм:       $(uptime -p)"
echo -e "  Дата:         $(date)"

# ============================================================
print_header "2. Открытые порты (слушающие)"
# ============================================================
echo -e "${CYAN}Порты, слушающие на всех интерфейсах (0.0.0.0 / ::):${NC}"
ss -tulnp | grep -E '0\.0\.0\.0|::' | grep LISTEN || echo "  Нет открытых внешних портов"

echo
echo -e "${CYAN}Порты, слушающие только на localhost:${NC}"
ss -tulnp | grep -E '127\.0\.0\.1|::1' | grep LISTEN || echo "  Нет"

# Рекомендация
EXTERNAL_PORTS=$(ss -tulnp | grep -E '0\.0\.0\.0|::' | grep LISTEN | wc -l)
if [[ $EXTERNAL_PORTS -gt 5 ]]; then
    print_warn "Много внешних открытых портов ($EXTERNAL_PORTS). Проверьте необходимость каждого."
fi

# ============================================================
print_header "3. Запущенные службы"
# ============================================================
echo -e "${CYAN}Активные службы:${NC}"
systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print "  •", $1}' | head -30

RUNNING_COUNT=$(systemctl list-units --type=service --state=running --no-legend | wc -l)
print_info "Всего запущено служб: $RUNNING_COUNT"

# ============================================================
print_header "4. Пользователи и доступ"
# ============================================================
echo -e "${CYAN}Пользователи с UID ≥ 1000 (обычные):${NC}"
awk -F: '$3 >= 1000 && $3 < 65534 {printf "  • %-15s UID=%-5s Shell=%s\n", $1, $3, $7}' /etc/passwd

echo
echo -e "${CYAN}Пользователи в группе sudo:${NC}"
getent group sudo | cut -d: -f4 | tr ',' '\n' | sed 's/^/  • /' || echo "  Нет"

echo
echo -e "${CYAN}Пользователи с UID 0 (root-права):${NC}"
awk -F: '$3 == 0 {print "  •", $1}' /etc/passwd

ROOT_USERS=$(awk -F: '$3 == 0 {print $1}' /etc/passwd | wc -l)
if [[ $ROOT_USERS -gt 1 ]]; then
    print_bad "Обнаружено больше одного пользователя с UID 0!"
fi

# ============================================================
print_header "5. Конфигурация SSH"
# ============================================================
SSHD_CONFIG=$(sshd -T 2>/dev/null)

PORT=$(echo "$SSHD_CONFIG" | grep -i "^port " | awk '{print $2}')
PERMIT_ROOT=$(echo "$SSHD_CONFIG" | grep -i "^permitrootlogin " | awk '{print $2}')
PASSWORD_AUTH=$(echo "$SSHD_CONFIG" | grep -i "^passwordauthentication " | awk '{print $2}')
PUBKEY_AUTH=$(echo "$SSHD_CONFIG" | grep -i "^pubkeyauthentication " | awk '{print $2}')

echo -e "  Порт SSH:                  ${BOLD}$PORT${NC}"
echo -e "  PermitRootLogin:           ${BOLD}$PERMIT_ROOT${NC}"
echo -e "  PasswordAuthentication:    ${BOLD}$PASSWORD_AUTH${NC}"
echo -e "  PubkeyAuthentication:      ${BOLD}$PUBKEY_AUTH${NC}"

[[ "$PORT" == "22" ]] && print_warn "SSH использует стандартный порт 22. Рекомендуется сменить."
[[ "$PERMIT_ROOT" != "no" && "$PERMIT_ROOT" != "prohibit-password" ]] && print_bad "Вход под root по SSH разрешён!"
[[ "$PASSWORD_AUTH" == "yes" ]] && print_warn "Парольная аутентификация SSH включена. Лучше использовать только ключи."
[[ "$PUBKEY_AUTH" != "yes" ]] && print_bad "Аутентификация по ключам отключена!"

# ============================================================
print_header "6. Фаервол (UFW)"
# ============================================================
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status | head -1)
    echo -e "  Статус: $UFW_STATUS"
    if echo "$UFW_STATUS" | grep -qi "inactive"; then
        print_bad "UFW выключен!"
    else
        print_ok "UFW активен"
        echo
        ufw status verbose | sed 's/^/  /'
    fi
else
    print_warn "UFW не установлен"
fi

# ============================================================
print_header "7. Fail2Ban"
# ============================================================
if systemctl is-active --quiet fail2ban 2>/dev/null; then
    print_ok "Fail2Ban запущен"
    echo
    fail2ban-client status 2>/dev/null | sed 's/^/  /' || true
    echo
    if fail2ban-client status sshd &>/dev/null; then
        fail2ban-client status sshd 2>/dev/null | sed 's/^/  /'
    fi
else
    print_warn "Fail2Ban не установлен или не запущен"
fi

# ============================================================
print_header "8. Критические права доступа"
# ============================================================
check_perm() {
    local file=$1
    local expected=$2
    if [[ -e "$file" ]]; then
        local actual
        actual=$(stat -c "%a" "$file")
        if [[ "$actual" == "$expected" ]]; then
            print_ok "$file → $actual (ожидалось $expected)"
        else
            print_warn "$file → $actual (рекомендуется $expected)"
        fi
    fi
}

check_perm "/etc/passwd" "644"
check_perm "/etc/shadow" "640"
check_perm "/etc/group" "644"
check_perm "/etc/gshadow" "640"
check_perm "/etc/ssh/sshd_config" "600"
check_perm "/etc/sudoers" "440"

# Проверка домашних .ssh
echo
echo -e "${CYAN}Проверка ~/.ssh директорий:${NC}"
for dir in /home/*/.ssh /root/.ssh; do
    if [[ -d "$dir" ]]; then
        PERM=$(stat -c "%a" "$dir")
        OWNER=$(stat -c "%U" "$dir")
        if [[ "$PERM" == "700" ]]; then
            print_ok "$dir → $PERM (владелец: $OWNER)"
        else
            print_warn "$dir → $PERM (должно быть 700, владелец: $OWNER)"
        fi
    fi
done

# ============================================================
print_header "9. Обновления системы"
# ============================================================
echo -e "${CYAN}Последнее обновление пакетов:${NC}"
if [[ -f /var/log/apt/history.log ]]; then
    grep -E "Start-Date|Upgrade|Install" /var/log/apt/history.log | tail -10 | sed 's/^/  /'
else
    print_info "Лог apt не найден"
fi

echo
if command -v unattended-upgrade &>/dev/null; then
    if systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then
        print_ok "Автоматические обновления безопасности включены"
    else
        print_warn "unattended-upgrades установлен, но не включён"
    fi
else
    print_warn "Автоматические обновления безопасности не настроены"
fi

# Проверка доступных обновлений
UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "Listing" | wc -l)
if [[ $UPDATES -gt 0 ]]; then
    print_warn "Доступно обновлений: $UPDATES"
else
    print_ok "Система актуальна (нет ожидающих обновлений)"
fi

# ============================================================
print_header "10. Дополнительные проверки"
# ============================================================

# World-writable файлы в важных директориях
WW_COUNT=$(find /etc /usr /bin /sbin /lib -xdev -type f -perm -0002 2>/dev/null | wc -l)
if [[ $WW_COUNT -gt 0 ]]; then
    print_warn "Найдено world-writable файлов в системных директориях: $WW_COUNT"
else
    print_ok "World-writable файлов в системных директориях не найдено"
fi

# Пустые пароли
EMPTY_PASS=$(awk -F: '($2 == "") {print $1}' /etc/shadow | wc -l)
if [[ $EMPTY_PASS -gt 0 ]]; then
    print_bad "Обнаружены пользователи с пустым паролем!"
else
    print_ok "Пользователей с пустым паролем нет"
fi

# ============================================================
print_header "ИТОГОВЫЕ РЕКОМЕНДАЦИИ"
# ============================================================

if [[ ${#RECOMMENDATIONS[@]} -eq 0 ]]; then
    echo -e "${GREEN}Критических замечаний не обнаружено. Сервер выглядит хорошо настроенным.${NC}"
else
    echo -e "${YELLOW}Обнаружены следующие моменты, требующие внимания:${NC}"
    echo
    for i in "${!RECOMMENDATIONS[@]}"; do
        echo -e "  $((i+1)). ${RECOMMENDATIONS[$i]}"
    done
fi

echo
echo -e "${BOLD}Аудит завершён: $(date)${NC}"
echo
