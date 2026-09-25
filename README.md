Мой репозиторий для скриптов автоматизации

# Ubuntu 24.04 Light Setup Script

Лёгкий скрипт первоначальной настройки свежего сервера Ubuntu 24.04.

### Что делает скрипт

- Обновляет систему
- Создаёт нового пользователя с правами `sudo`
- Отключает вход под `root` по SSH
- Меняет стандартный SSH-порт (по умолчанию на `4222`)
- Настраивает и включает фаервол UFW
- Включает автоматические обновления безопасности (`unattended-upgrades`)

Скрипт написан с акцентом на безопасность: новый порт открывается в фаерволе **до** перезапуска SSH, чтобы не потерять доступ к серверу.

# Fail2Ban Setup Script

Скрипт для быстрой установки и настройки Fail2Ban на Ubuntu 24.04 с рекомендуемыми параметрами безопасности.

### Что делает скрипт

- Устанавливает Fail2Ban
- Настраивает защиту SSH с оптимальными параметрами
- Использует UFW в качестве действия бана (совместимо с предыдущим скриптом настройки сервера)
- Включает защиту от повторных нарушителей (`recidive`)
- По умолчанию разрешает доступ со всех IP (белый список можно добавить позже)

### Параметры по умолчанию

| Параметр              | Значение | Описание                              |
|-----------------------|----------|---------------------------------------|
| `maxretry`            | 5        | Количество неудачных попыток          |
| `findtime`            | 10m      | Окно времени для подсчёта попыток     |
| `bantime`             | 1h       | Время бана                            |
| `bantime.increment`   | true     | Увеличение времени бана при повторах  |
| `bantime.maxtime`     | 1w       | Максимальное время бана               |
---

## Server Audit Script

Скрипт комплексного аудита безопасности сервера Ubuntu.

### Что проверяет

- Информация о системе (ОС, ядро, аптайм)
- Открытые порты (внешние и localhost)
- Запущенные службы
- Пользователи (обычные, sudo, UID 0)
- Конфигурация SSH (порт, root-login, password/pubkey auth)
- Статус фаервола UFW
- Статус Fail2Ban
- Права доступа к критическим файлам (`/etc/passwd`, `/etc/shadow`, `sshd_config`, `sudoers` и др.)
- Права на директории `~/.ssh`
- Состояние обновлений системы и `unattended-upgrades`
- World-writable файлы в системных директориях
- Пользователи с пустым паролем

В конце скрипт выдаёт структурированный список рекомендаций на основе найденных проблем.

### Быстрый запуск (рекомендуется)

Выполните на свежем сервере от пользователя `root`:


curl -sSL https://raw.githubusercontent.com/3Jackdaw91/my_freelance_scripts/main/setup_ubuntu_light.sh | bash

curl -sSL https://raw.githubusercontent.com/3Jackdaw91/my_freelance_scripts/main/setup_ubuntu_light.sh -o setup.sh
chmod +x setup.sh
sudo ./setup.sh

curl -sSL https://raw.githubusercontent.com/3Jackdaw91/my_freelance_scripts/main/setup_fail2ban.sh | sudo bash

curl -sSL https://raw.githubusercontent.com/3Jackdaw91/my_freelance_scripts/main/audit_server.sh -o audit.sh
chmod +x audit.sh
sudo ./audit.sh
