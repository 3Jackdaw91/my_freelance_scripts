#!/bin/bash
set -euo pipefail

# ======================== НАСТРОЙКИ ========================
NEW_USER="admin"          # Имя нового пользователя (поменяй при необходимости)
SSH_PORT=4222             # Новый SSH-порт
# ===========================================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Подготовка Ubuntu 24.04 ===${NC}"
echo -e "Новый пользователь : ${GREEN}${NEW_USER}${NC}"
echo -e "Новый SSH-порт     : ${GREEN}${SSH_PORT}${NC}"
echo

# Проверка root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Скрипт нужно запускать от root!${NC}"
   exit 1
fi

# Проверка, что порт свободен
if ss -tuln | grep -q ":${SSH_PORT} "; then
    echo -e "${RED}Порт ${SSH_PORT} уже занят! Выбери другой.${NC}"
    exit 1
fi

# 1. Обновление системы
echo -e "${YELLOW}[1/8] Обновление системы...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get autoremove -y -qq
apt-get autoclean -qq

# 2. Создание пользователя с sudo
echo -e "${YELLOW}[2/8] Создание пользователя ${NEW_USER}...${NC}"
if id "$NEW_USER" &>/dev/null; then
    echo "Пользователь ${NEW_USER} уже существует — пропускаю создание"
else
    adduser --disabled-password --gecos "" "$NEW_USER"
    echo -e "${GREEN}Пользователь создан. Сейчас зададим пароль:${NC}"
    passwd "$NEW_USER"
fi

usermod -aG sudo "$NEW_USER"
echo -e "${GREEN}Пользователь добавлен в группу sudo${NC}"

# 3. Настройка SSH (drop-in)
echo -e "${YELLOW}[3/8] Настройка SSH...${NC}"
mkdir -p /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/99-hardening.conf << EOF
# Автоматически создано скриптом настройки
Port ${SSH_PORT}
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
EOF

# Проверка синтаксиса
if ! sshd -t; then
    echo -e "${RED}Ошибка в конфигурации SSH! Откатываю изменения.${NC}"
    rm -f /etc/ssh/sshd_config.d/99-hardening.conf
    exit 1
fi
echo -e "${GREEN}Конфигурация SSH валидна${NC}"

# 4. Настройка UFW (сначала открываем порт!)
echo -e "${YELLOW}[4/8] Настройка фаервола UFW...${NC}"
apt-get install -y ufw > /dev/null

ufw default deny incoming
ufw default allow outgoing

# Открываем новый порт ДО включения фаервола и перезапуска SSH
ufw allow "${SSH_PORT}/tcp" comment 'SSH custom port'

# На всякий случай оставляем 22 (можно удалить позже после проверки)
ufw allow 22/tcp comment 'SSH old port - temporary'

echo -e "${GREEN}Правила UFW добавлены${NC}"

# 5. Включение UFW
echo -e "${YELLOW}[5/8] Включение UFW...${NC}"
ufw --force enable
ufw status verbose

# 6. Применение изменений SSH (Ubuntu 24.04 + socket activation)
echo -e "${YELLOW}[6/8] Перезапуск SSH (ssh.socket)...${NC}"
systemctl daemon-reload
systemctl restart ssh.socket

# Небольшая пауза
sleep 2

# 7. Автоматические обновления безопасности
echo -e "${YELLOW}[7/8] Настройка автоматических обновлений безопасности...${NC}"

apt-get install -y unattended-upgrades apt-listchanges > /dev/null

# Включаем автоматические обновления
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF

# Основная конфигурация unattended-upgrades (только security)
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
// Автоматически создано скриптом настройки Ubuntu 24.04

Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    // Раскомментируй следующую строку, если хочешь также получать обновления из -updates
    // "${distro_id}:${distro_codename}-updates";
};

// Автоматически удалять неиспользуемые зависимости
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Автоматическая очистка
Unattended-Upgrade::Automatic-Reboot "false";          // Не перезагружать автоматически
Unattended-Upgrade::Automatic-Reboot-Time "03:00";     // Если всё-таки включишь — в 3 часа ночи

// Логи
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";

// Отправлять отчёт только при ошибках (можно поменять на "always" или "on-change")
Unattended-Upgrade::Mail "";
Unattended-Upgrade::MailReport "on-change";

// Не останавливаться при ошибках отдельных пакетов
Unattended-Upgrade::Ignore-Errors "true";
EOF

# Включаем и запускаем сервис
systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

echo -e "${GREEN}Автоматические обновления безопасности настроены${NC}"

# 8. Проверка
echo -e "${YELLOW}[8/8] Финальная проверка...${NC}"
if ss -tuln | grep -q ":${SSH_PORT} "; then
    echo -e "${GREEN}SSH успешно слушает порт ${SSH_PORT}${NC}"
else
    echo -e "${RED}Внимание: порт ${SSH_PORT} не слушается! Проверь вручную.${NC}"
fi

echo
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}  Настройка завершена успешно!${NC}"
echo -e "${GREEN}==============================================${NC}"
echo
echo -e "${YELLOW}ВАЖНО — НЕ ЗАКРЫВАЙ ТЕКУЩУЮ СЕССИЮ!${NC}"
echo
echo "1. Открой НОВЫЙ терминал и проверь вход:"
echo -e "   ${GREEN}ssh -p ${SSH_PORT} ${NEW_USER}@IP_СЕРВЕРА${NC}"
echo
echo "2. Убедись, что можешь выполнить sudo:"
echo -e "   ${GREEN}sudo whoami${NC}   → должно вывести root"
echo
echo "3. Только после успешной проверки можно:"
echo "   - закрыть старую сессию"
echo "   - удалить временное правило для порта 22:"
echo -e "     ${GREEN}sudo ufw delete allow 22/tcp${NC}"
echo
echo -e "${YELLOW}Автоматические обновления:${NC}"
echo "  • Проверка каждый день"
echo "  • Устанавливаются только security-обновления"
echo "  • Автоматическая перезагрузка отключена"
echo "  • Логи: /var/log/unattended-upgrades/"
echo
echo -e "${YELLOW}Если сервер в облаке (AWS, Hetzner, DigitalOcean и т.д.) —${NC}"
echo -e "${YELLOW}обязательно открой порт ${SSH_PORT} в Security Group / Firewall панели провайдера!${NC}"
echo
