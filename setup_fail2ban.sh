#!/bin/bash
set -euo pipefail

# ======================== НАСТРОЙКИ ========================
SSH_PORT=4222             # Укажи свой SSH-порт (тот же, что использовал в setup_ubuntu_light.sh)
# ===========================================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Установка и настройка Fail2Ban ===${NC}"
echo -e "SSH-порт: ${GREEN}${SSH_PORT}${NC}"
echo

# Проверка root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Скрипт нужно запускать от root (через sudo)!${NC}"
   exit 1
fi

# 1. Установка
echo -e "${YELLOW}[1/4] Установка Fail2Ban...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y fail2ban > /dev/null
echo -e "${GREEN}Fail2Ban установлен${NC}"

# 2. Создание конфигурации
echo -e "${YELLOW}[2/4] Создание конфигурации...${NC}"

cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Локальные адреса (никогда не банить)
ignoreip = 127.0.0.1/8 ::1

# Основные параметры безопасности
bantime  = 1h
findtime = 10m
maxretry = 5

# Увеличение времени бана для повторных нарушителей
bantime.increment = true
bantime.factor    = 2
bantime.maxtime   = 1w

# Используем UFW (совместимо с предыдущим скриптом настройки)
banaction = ufw
backend   = systemd

[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
backend  = systemd
maxretry = 5
findtime = 10m
bantime  = 1h

# Дополнительная защита от злостных нарушителей
[recidive]
enabled  = true
logpath  = /var/log/fail2ban.log
banaction = ufw
bantime  = 1w
findtime = 1d
maxretry = 3
EOF

echo -e "${GREEN}Конфигурация создана: /etc/fail2ban/jail.local${NC}"

# 3. Запуск и включение
echo -e "${YELLOW}[3/4] Запуск Fail2Ban...${NC}"
systemctl enable fail2ban
systemctl restart fail2ban

# Небольшая пауза
sleep 2

# 4. Проверка
echo -e "${YELLOW}[4/4] Проверка статуса...${NC}"
if systemctl is-active --quiet fail2ban; then
    echo -e "${GREEN}Fail2Ban успешно запущен${NC}"
else
    echo -e "${RED}Ошибка запуска Fail2Ban!${NC}"
    systemctl status fail2ban --no-pager
    exit 1
fi

echo
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}  Fail2Ban успешно настроен!${NC}"
echo -e "${GREEN}==============================================${NC}"
echo
echo "Текущий статус SSH-защиты:"
fail2ban-client status sshd
echo
echo -e "${YELLOW}Полезные команды:${NC}"
echo "  • Статус всех тюрем:     sudo fail2ban-client status"
echo "  • Статус SSH:            sudo fail2ban-client status sshd"
echo "  • Разбанить IP:          sudo fail2ban-client set sshd unbanip IP_АДРЕС"
echo "  • Добавить IP в белый список:"
echo "      отредактируй файл /etc/fail2ban/jail.local"
echo "      в секции [DEFAULT] добавь IP в ignoreip"
echo "      затем: sudo systemctl restart fail2ban"
echo
