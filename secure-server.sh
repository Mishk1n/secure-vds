#!/bin/bash

set -e
echo "========================================="
echo "Автоматическая настройка безопасности VDS"
echo "========================================="
echo

if [ "$EUID" -ne 0 ]; then
    echo "Запустите скрипт от root"
    exit 1
fi

# Цветной вывод
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_pass() { echo -e "${BLUE}[PASSWORD]${NC} $1"; }

# Запрашиваем имя пользователя
echo -e "${BLUE}Введите имя пользователя для создания:${NC}"
read -p "> " USERNAME

# Проверка на пустое имя
if [ -z "$USERNAME" ]; then
    log_error "Имя пользователя не может быть пустым!"
    exit 1
fi

# Проверка на существование пользователя
if id "$USERNAME" &>/dev/null; then
    log_warn "Пользователь $USERNAME уже существует"
    echo -e "${YELLOW}Хотите сбросить пароль для этого пользователя? (y/n)${NC}"
    read -p "> " RESET_PASS
    if [[ ! "$RESET_PASS" =~ ^[Yy]$ ]]; then
        log_error "Скрипт остановлен. Запустите с другим именем пользователя"
        exit 1
    fi
fi

# Запрашиваем порт SSH
echo -e "${BLUE}Введите порт для SSH (по умолчанию 4243):${NC}"
read -p "> " SSH_PORT_INPUT
SSH_PORT=${SSH_PORT_INPUT:-4243}

# Проверка порта
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    log_error "Неверный номер порта. Использую порт 4243"
    SSH_PORT=4243
fi

# Генерируем случайный пароль
USER_PASSWORD="$(openssl rand -base64 16 | tr -d '=' | head -c 16)"

log_info "Настройка безопасности для пользователя: $USERNAME"
log_info "SSH порт: $SSH_PORT"

# Обновляем систему
log_info "Обновление системы..."
apt update && apt upgrade -y

# Устанавливаем необходимые пакеты (без mailutils)
log_info "Установка пакетов безопасности..."
apt install -y ufw fail2ban rkhunter lynis unattended-upgrades sudo geoip-bin geoip-database curl whois

# Получаем IP адреса сервера
SERVER_IPV4=$(curl -4 -s ifconfig.me 2>/dev/null || echo "не доступен")
SERVER_IPV6=$(curl -6 -s ifconfig.me 2>/dev/null || echo "не доступен")

# Создаём пользователя (если не существует)
if ! id "$USERNAME" &>/dev/null; then
    log_info "Создание пользователя $USERNAME"
    useradd -m -s /bin/bash -G sudo "$USERNAME"
    
    # Устанавливаем пароль
    echo "$USERNAME:$USER_PASSWORD" | chpasswd
    # Принуждаем сменить пароль при первом входе
    chage -d 0 "$USERNAME"
    
    log_pass "Пользователь $USERNAME создан"
    log_pass "Временный пароль: $USER_PASSWORD"
    log_warn "Смените пароль при первом входе!"
else
    log_warn "Пользователь $USERNAME уже существует"
    # Сбрасываем пароль
    echo "$USERNAME:$USER_PASSWORD" | chpasswd
    chage -d 0 "$USERNAME"
    log_pass "Новый временный пароль: $USER_PASSWORD"
fi

# Сохраняем пароль в файл (только для информации)
cat > /root/credentials.txt <<EOF
=== ДАННЫЕ ДЛЯ ВХОДА НА СЕРВЕР ===
Сервер: $SERVER_IPV4
Порт SSH: $SSH_PORT
Пользователь: $USERNAME
Пароль: $USER_PASSWORD
Время создания: $(date)
===================================
⚠️  Этот файл будет удалён через 5 минут
EOF

chmod 600 /root/credentials.txt

# Показываем данные для входа
echo
log_info "========================================="
log_info "ДАННЫЕ ДЛЯ ПОДКЛЮЧЕНИЯ (СОХРАНИТЕ ИХ):"
log_info "========================================="
echo "IP адрес: $SERVER_IPV4"
echo "SSH порт: $SSH_PORT"
echo "Пользователь: $USERNAME"
echo "Пароль: $USER_PASSWORD"
echo
log_warn "Этот пароль будет показан только один раз!"
log_info "========================================="
echo

# Бэкап SSH конфига
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)

# Настройка SSH (парольный вход, без ключей)
log_info "Настройка SSH на порт $SSH_PORT..."
cat > /etc/ssh/sshd_config <<EOF
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
AllowUsers $USERNAME
MaxAuthTries 5
MaxSessions 2
ClientAliveInterval 300
ClientAliveCountMax 2
Protocol 2
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

# Проверка конфига
if sshd -t 2>/dev/null; then
    log_info "SSH конфигурация валидна"
else
    log_error "Ошибка в SSH конфигурации!"
    sshd -t
    exit 1
fi

# Настройка UFW с защитой от блокировки
log_info "Настройка UFW..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Открываем новый порт
ufw allow ${SSH_PORT}/tcp comment 'SSH port'

# Если старый порт 22 ещё используется, временно оставляем
if ss -tln | grep -q ":22 "; then
    ufw allow 22/tcp comment 'Temp SSH fallback'
fi

# Веб-порты
ufw allow 80/tcp
ufw allow 443/tcp

# Активируем UFW
ufw --force enable

log_info "UFW настроен и активен"

# Настройка Fail2Ban
log_info "Настройка Fail2Ban..."
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
banaction = ufw
banaction_allports = ufw

[sshd]
enabled = true
port = $SSH_PORT
logpath = %(sshd_log)s
maxretry = 3
bantime = 3600
EOF

# Увеличиваем лимит файлов для Fail2Ban
if ! grep -q "ulimit -n 65535" /etc/default/fail2ban 2>/dev/null; then
    echo "ulimit -n 65535" >> /etc/default/fail2ban
fi

systemctl enable fail2ban
systemctl restart fail2ban

# СОЗДАНИЕ СКРИПТА МОНИТОРИНГА GEOIP
log_info "Создание скрипта мониторинга GeoIP..."

cat > /usr/local/bin/geoip-monitor.sh <<'EOF'
#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Определяем лог-файл в зависимости от ОС
LOG_FILE=""
if [ -f /var/log/auth.log ]; then
    LOG_FILE="/var/log/auth.log"
elif [ -f /var/log/secure ]; then
    LOG_FILE="/var/log/secure"
else
    echo "Лог-файл не найден"
    exit 1
fi

# Файл для хранения уже забаненых IP
BANNED_IP_FILE="/var/log/banned_ips.txt"
touch "$BANNED_IP_FILE"

# Лог файл для алертов
ALERT_LOG="/var/log/geoip-alerts.log"

# Список стран для автоматической блокировки
BLOCK_COUNTRIES=("China" "Russia" "North Korea" "Iran" "Syria" "Vietnam" "Afghanistan" "Somalia" "Iraq" "Libya")

# Функция блокировки IP (поддержка IPv4 и IPv6)
block_ip() {
    local ip="$1"
    local reason="$2"
    
    # Проверяем, не заблокирован ли уже
    if grep -q "^${ip}$" "$BANNED_IP_FILE" 2>/dev/null; then
        return 0
    fi
    
    # Блокируем через UFW (работает и с IPv4, и с IPv6)
    ufw deny from "$ip" to any comment "GeoIP block: $reason" 2>/dev/null
    
    # Дополнительная блокировка через iptables/ip6tables для надёжности
    if [[ "$ip" =~ .*:.* ]]; then
        # IPv6
        ip6tables -A INPUT -s "$ip" -j DROP 2>/dev/null
    else
        # IPv4
        iptables -A INPUT -s "$ip" -j DROP 2>/dev/null
    fi
    
    # Добавляем в fail2ban
    fail2ban-client set sshd banip "$ip" 2>/dev/null || true
    
    # Запоминаем заблокированный IP
    echo "$ip" >> "$BANNED_IP_FILE"
    
    return 0
}

# Функция проверки в странах блокировки
should_block_country() {
    local country="$1"
    for block in "${BLOCK_COUNTRIES[@]}"; do
        if [[ "$country" == *"$block"* ]]; then
            return 0
        fi
    done
    return 1
}

echo "$(date) - GeoIP мониторинг запущен (IPv4+IPv6)" | tee -a "$ALERT_LOG"

# Мониторинг в реальном времени
tail -F "$LOG_FILE" 2>/dev/null | grep --line-buffered "Failed password" | while read line; do
    # Извлекаем IP (поддержка IPv4 и IPv6)
    ip=$(echo "$line" | grep -oP '((\d+\.\d+\.\d+\.\d+)|([a-fA-F0-9:]+:+)+[a-fA-F0-9]+)' | head -1)
    [ -z "$ip" ] && continue
    
    # Извлекаем имя пользователя
    user=$(echo "$line" | grep -oP 'for \K[^ ]+' | head -1)
    
    # Извлекаем время
    time=$(echo "$line" | cut -d' ' -f1-3)
    
    # Определяем страну по IP
    country=$(geoiplookup "$ip" 2>/dev/null | grep -oP 'GeoIP Country Edition: \K.*' | cut -d',' -f1 | xargs)
    
    if [ -z "$country" ]; then
        # Fallback: пытаемся определить через whois
        country=$(whois "$ip" 2>/dev/null | grep -i "country:" | head -1 | awk '{print $2}' | tr '[:lower:]' '[:upper:]')
        [ -z "$country" ] && country="Unknown"
    fi
    
    # Проверяем, блокировать ли эту страну
    BLOCK_THIS=0
    if should_block_country "$country"; then
        BLOCK_THIS=1
    fi
    
    # Проверяем, не забанен ли уже этот IP
    if grep -q "^${ip}$" "$BANNED_IP_FILE" 2>/dev/null; then
        continue
    fi
    
    # Формируем сообщение об алерте
    if [ $BLOCK_THIS -eq 1 ]; then
        ALERT_MSG="[КРИТИЧЕСКИЙ] $time | IP: $ip | Страна: $country | Пользователь: $user | ДЕЙСТВИЕ: БЛОКИРОВКА"
        # Блокируем IP
        block_ip "$ip" "$country"
    else
        ALERT_MSG="[ПРЕДУПРЕЖДЕНИЕ] $time | IP: $ip | Страна: $country | Пользователь: $user | ДЕЙСТВИЕ: МОНИТОРИНГ"
    fi
    
    # Выводим в консоль (цветной)
    if [ $BLOCK_THIS -eq 1 ]; then
        echo -e "${RED}$ALERT_MSG${NC}"
    else
        echo -e "${YELLOW}$ALERT_MSG${NC}"
    fi
    
    # Логируем в файл
    echo "$ALERT_MSG" >> "$ALERT_LOG"
done
EOF

# Делаем скрипт исполняемым
chmod +x /usr/local/bin/geoip-monitor.sh

# Создаем systemd сервис для GeoIP монитора
log_info "Создание systemd сервиса для GeoIP монитора..."

cat > /etc/systemd/system/geoip-monitor.service <<EOF
[Unit]
Description=GeoIP SSH Brute Force Monitor (IPv4+IPv6)
After=network.target ssh.service ufw.service
Wants=ssh.service

[Service]
Type=simple
ExecStart=/usr/local/bin/geoip-monitor.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Активируем сервис
systemctl daemon-reload
systemctl enable geoip-monitor.service
systemctl start geoip-monitor.service

# Создаем скрипт для статического анализа логов
cat > /usr/local/bin/geoip-scan.sh <<'EOF'
#!/bin/bash

# Статический анализ логов за последний час
LOG_FILE=""
if [ -f /var/log/auth.log ]; then
    LOG_FILE="/var/log/auth.log"
elif [ -f /var/log/secure ]; then
    LOG_FILE="/var/log/secure"
else
    exit 1
fi

ALERT_LOG="/var/log/geoip-alerts.log"
BANNED_IP_FILE="/var/log/banned_ips.txt"

# Анализируем неудачные попытки за последний час
echo "=== GeoIP сканирование $(date) ===" >> "$ALERT_LOG"

grep "Failed password" "$LOG_FILE" | grep "$(date +%b\ %_d)" | tail -100 | while read line; do
    ip=$(echo "$line" | grep -oP '((\d+\.\d+\.\d+\.\d+)|([a-fA-F0-9:]+:+)+[a-fA-F0-9]+)' | head -1)
    [ -z "$ip" ] && continue
    
    # Пропускаем уже забаненые
    if grep -q "^${ip}$" "$BANNED_IP_FILE" 2>/dev/null; then
        continue
    fi
    
    country=$(geoiplookup "$ip" 2>/dev/null | grep -oP 'GeoIP Country Edition: \K.*' | cut -d',' -f1 | xargs)
    
    # Блокируем IP из нежелательных стран
    if [[ "$country" == *"China"* ]] || [[ "$country" == *"Russia"* ]] || [[ "$country" == *"North Korea"* ]] || [[ "$country" == *"Iran"* ]]; then
        ufw deny from "$ip" to any comment "GeoIP scan block" 2>/dev/null
        echo "$ip" >> "$BANNED_IP_FILE"
        echo "Блокирован IP $ip из страны $country" >> "$ALERT_LOG"
        logger -t "geoip-scan" "Блокирован $ip из $country"
    fi
done
EOF

chmod +x /usr/local/bin/geoip-scan.sh

# Добавляем в cron (каждый час)
(crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/geoip-scan.sh") | crontab -

# Создаем скрипт статистики
cat > /usr/local/bin/geoip-stats.sh <<'EOF'
#!/bin/bash
echo "=== GEOIP СТАТИСТИКА АТАК ==="
echo ""
echo "Топ-10 стран по количеству атак:"
grep "Страна:" /var/log/geoip-alerts.log 2>/dev/null | awk -F'Страна: ' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -rn | head -10
echo ""
echo "Топ-10 IP атакующих:"
grep -oP 'IP: \K[0-9a-f:.]+' /var/log/geoip-alerts.log 2>/dev/null | sort | uniq -c | sort -rn | head -10
echo ""
echo "Всего заблокировано IP:"
cat /var/log/banned_ips.txt 2>/dev/null | wc -l
echo ""
echo "Статус GeoIP сервиса:"
systemctl is-active geoip-monitor
echo ""
echo "Последние 5 алертов:"
tail -5 /var/log/geoip-alerts.log 2>/dev/null
EOF

chmod +x /usr/local/bin/geoip-stats.sh

# Дополнительные проверки безопасности
log_info "Дополнительные настройки..."

# Увеличиваем лимиты системы
cat >> /etc/security/limits.conf <<EOF
* soft nproc 100
* hard nproc 150
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF

# Настройка автоматических обновлений
log_info "Настройка автообновлений..."
cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
EOF

# Настройка логирования
cat > /etc/logrotate.d/geoip-alerts <<EOF
/var/log/geoip-alerts.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 0640 root root
}
EOF

# Защита от брутфорса SSH (дополнительно)
log_info "Настройка защиты SSH сокета..."
# Создаем директорию для оверрайдов, если её нет
mkdir -p /etc/systemd/system/ssh.socket.d/

# Создаем конфиг оверрайда
cat > /etc/systemd/system/ssh.socket.d/override.conf <<EOF
[Socket]
Accept=no
MaxConnectionsPerSource=4
MaxConnectionsPerSourceStartPeriod=10
EOF

# Применяем настройки
systemctl daemon-reload
systemctl restart ssh.socket 2>/dev/null || true

# Перезапускаем SSH для применения
systemctl restart ssh 2>/dev/null || systemctl restart sshd

# Планируем удаление файла с паролем через 5 минут
(
    sleep 300
    rm -f /root/credentials.txt
) &

# Финальный отчёт
echo
log_info "========================================="
log_info "Настройка завершена успешно!"
log_info "========================================="
echo
log_info "ДАННЫЕ ДЛЯ ПОДКЛЮЧЕНИЯ (СОХРАНИТЕ ИХ):"
log_info "-----------------------------------------"
echo -e "${GREEN}SSH порт:${NC} $SSH_PORT"
echo -e "${GREEN}Пользователь:${NC} $USERNAME"
echo -e "${GREEN}Пароль:${NC} $USER_PASSWORD"
echo -e "${GREEN}IPv4 адрес:${NC} $SERVER_IPV4"
if [ "$SERVER_IPV6" != "не доступен" ]; then
    echo -e "${GREEN}IPv6 адрес:${NC} $SERVER_IPV6"
fi
log_info "-----------------------------------------"
echo
log_info "КОНФИГУРАЦИЯ БЕЗОПАСНОСТИ:"
echo -e "${GREEN}✓${NC} Root вход: запрещён"
echo -e "${GREEN}✓${NC} Парольный вход: разрешён (с принудительной сменой)"
echo -e "${GREEN}✓${NC} Fail2Ban: активен (3 попытки = бан на 1 час)"
echo -e "${GREEN}✓${NC} GeoIP мониторинг: АКТИВЕН (IPv4+IPv6)"
echo -e "${GREEN}✓${NC} Автоматическая блокировка: Китай, Россия, Сев. Корея, Иран, Сирия, Вьетнам, Афганистан, Сомали, Ирак, Ливия"
echo -e "${GREEN}✓${NC} UFW: активен, порты 80,443,${SSH_PORT} открыты"
echo -e "${GREEN}✓${NC} Защита SSH сокета: активна (ограничение коннектов)"
echo
log_info "ПОЛЕЗНЫЕ КОМАНДЫ:"
echo "  GeoIP алерты:      tail -f /var/log/geoip-alerts.log"
echo "  GeoIP статистика:  geoip-stats"
echo "  Статус GeoIP:      systemctl status geoip-monitor"
echo "  Статус Fail2Ban:   fail2ban-client status sshd"
echo "  Проверка UFW:      ufw status verbose"
echo "  Заблокированные IP: cat /var/log/banned_ips.txt"
echo
log_warn "ВАЖНО:"
echo "1. Файл с паролем сохранён в /root/credentials.txt и будет автоматически удалён через 5 минут"
echo "2. Не закрывайте эту сессию, пока не проверите новое подключение!"
echo "3. При первом входе система попросит сменить пароль"
echo
log_info "Проверьте подключение:"
echo -e "${BLUE}ssh -p $SSH_PORT $USERNAME@$SERVER_IPV4${NC}"
echo
if [ "$SERVER_IPV6" != "не доступен" ]; then
    echo -e "${BLUE}ssh -p $SSH_PORT $USERNAME@$SERVER_IPV6${NC}"
    echo
fi
log_warn "Если подключение не работает, проверьте:"
echo "  - ufw status verbose"
echo "  - ss -tlnp | grep $SSH_PORT"
echo "  - systemctl status ssh"