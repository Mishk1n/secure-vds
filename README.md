# 🔒 Secure Server Setup Script

Скрипт автоматической настройки безопасности VDS сервера с GeoIP мониторингом и защитой от брутфорса.

## 📦 Требования

- **ОС**: Ubuntu 20.04/22.04/24.04 или Debian 11/12
- **Права**: root доступ
- **Интернет**: для установки пакетов и определения внешнего IP

## 🚀 Запуск

```bash
# Дайте права на выполнение
chmod +x secure-server.sh

# Запустите от root
sudo ./secure-server.sh
```

## ⌨️ Интерактивный ввод
Введите имя пользователя для создания:
> john

Введите порт для SSH (по умолчанию 4243):
> 4243

## 📋 Сохраните данные
```
=========================================
ДАННЫЕ ДЛЯ ПОДКЛЮЧЕНИЯ (СОХРАНИТЕ ИХ):
=========================================
IP адрес: 10.55.111.202
SSH порт: 4243
Пользователь: john
Пароль: TcuKtjuacuKscuKa
=========================================
```
⚠️ ВАЖНО: Пароль показывается только один раз! Сохраните его надёжно.

## 📝 Что делает скрипт
### 🔧 Настройка SSH
- Изменяет порт на указанный (по умолчанию 4243)
- Запрещает вход под root
- Разрешает только парольный вход (без ключей)
> Для улучшения безопастности используйте ключи

- Ограничивает количество попыток (5)
- Ограничивает количество сессий (2)
### 🔥 Настройка UFW
- Закрывает все входящие порты по умолчанию
- Открывает порты: SSH (4243), HTTP (80), HTTPS (443)
- Автоматически блокирует подозрительные IP
### 🛡️ Настройка Fail2Ban
- Банит IP после 5 неудачных попыток входа
- Время бана: 1 час
- Использует UFW для блокировки
### 🌍 GeoIP мониторинг
- Отслеживает все неудачные попытки входа в реальном времени. 
- Определяет страну по IP адресу. 
- Автоматически блокирует IP из нежелательных стран:
№	Страна
1.	Китай (China)
2.	Россия (Russia)
3.	Северная Корея (North Korea)
4.	Иран (Iran)
5.	Сирия (Syria)
6.	Вьетнам (Vietnam)
7.	Афганистан (Afghanistan)
8.	Сомали (Somalia)
9.	Ирак (Iraq)
10.	Ливия (Libya)
### 🔄 Автоматические обновления
- Ежедневное обновление списка пакетов
- Автоматическая установка обновлений безопасности
- Еженедельная очистка кэша

## 💡 Полезные команды
### 📝 Подключение к серверу
```bash
# Первое подключение (пароль будет запрошен)
ssh -p 4243 john@5.42.106.202
# При первом входе система попросит сменить пароль
# Введите старый пароль, затем новый дважды
```
### 📊 Мониторинг GeoIP
```bash
# Просмотр GeoIP алертов в реальном времени
tail -f /var/log/geoip-alerts.log
# Статистика атак
geoip-stats
# Просмотр заблокированных IP
cat /var/log/banned_ips.txt
# Статус GeoIP сервиса
systemctl status geoip-monitor
# Перезапуск GeoIP монитора
systemctl restart geoip-monitor
# Логи GeoIP монитора
journalctl -u geoip-monitor -f
```
### 🛡️ Управление Fail2Ban
```bash
# Статус Fail2Ban
fail2ban-client status
# Статус SSH защиты
fail2ban-client status sshd
# Список забаненых IP
fail2ban-client banned
# Разблокировать IP
fail2ban-client set sshd unbanip 192.168.1.100
# Перезапустить Fail2Ban
systemctl restart fail2ban
```
### 🔥 Управление UFW
```bash
# Статус UFW (с правилами)
ufw status verbose
# Добавить разрешение на порт
ufw allow 8080/tcp
# Удалить правило
ufw delete allow 8080/tcp
# Заблокировать конкретный IP
ufw deny from 1.2.3.4
# Разблокировать IP
ufw delete deny from 1.2.3.4
# Перезагрузить UFW
ufw reload
```
### 🔍 Проверка безопасности
```bash
# Проверка руткитов
rkhunter --check --skip-keypress
# Аудит безопасности
lynis audit system
# Проверка открытых портов
ss -tlnp
# Проверка подключений
netstat -an | grep :4243
# Просмотр последних неудачных входов
tail -50 /var/log/auth.log | grep "Failed password"
```
### ⚙️ Системные команды
```bash
# Просмотр системных логов SSH
tail -f /var/log/auth.log | grep sshd
# Перезапуск SSH
systemctl restart ssh
# Проверка конфигурации SSH
sshd -t
# Просмотр лимитов
ulimit -a
# Информация о сервере
uname -a
uptime
df -h
free -h
```
### 🌍 GeoIP команды
```bash
# Определить страну по IP
geoiplookup 8.8.8.8

# Определить страну по IPv6
geoiplookup 2001:4860:4860::8888

# Ручная проверка IP через whois
whois 1.2.3.4 | grep -i country
```
### 📊 Мониторинг
#### Лог файлы
```
Файл	                        Описание
/var/log/geoip-alerts.log	    Лог GeoIP алертов
/var/log/banned_ips.txt	      Список заблокированных IP
/var/log/auth.log	            Лог авторизации (Ubuntu)
/var/log/secure	              Лог авторизации (CentOS)
/var/log/fail2ban.log	        Лог Fail2Ban
```
#### Cron задачи
```bash
# Просмотр cron задач
crontab -l

# GeoIP сканирование каждый час
0 * * * * /usr/local/bin/geoip-scan.sh
```

#### Скрипты
```
Скрипт	                            Описание
/usr/local/bin/geoip-monitor.sh	    Основной мониторинг в реальном времени
/usr/local/bin/geoip-scan.sh	      Сканирование логов каждый час
/usr/local/bin/geoip-stats.sh	      Статистика атак
```
### 🔧 Устранение проблем
#### Не удаётся подключиться по SSH
```bash
# В текущей открытой сессии проверьте:
# 1. Слушает ли SSH нужный порт
ss -tlnp | grep 4243
# 2. Статус UFW
ufw status verbose
# 3. Статус SSH
systemctl status ssh
# Временно отключить UFW для теста
ufw disable
# Включить обратно
ufw enable
# Если порт не слушает - проверьте конфиг
cat /etc/ssh/sshd_config | grep Port
systemctl restart ssh
```
#### GeoIP не блокирует IP
```bash
# Проверить работу GeoIP
geoiplookup 8.8.8.8
# Проверить статус сервиса
systemctl status geoip-monitor
# Посмотреть ошибки
journalctl -u geoip-monitor -n 50
# Перезапустить сервис
systemctl restart geoip-monitor
# Проверить логи
tail -f /var/log/geoip-alerts.log
```
#### Забыли пароль
```bash
# Восстановление доступа через root сессию
# (если текущая сессия открыта)
# Сбросить пароль пользователя
passwd john
# Принудительно сменить пароль при входе
chage -d 0 john
```
#### Fail2Ban не блокирует
```bash
# Проверить статус
fail2ban-client status sshd
# Проверить логи
tail -f /var/log/fail2ban.log
# Перезапустить
systemctl restart fail2ban
# Проверить правила UFW
ufw status verbose | grep deny
```
#### Высокая нагрузка на сервер
```bash
# Просмотр процессов
htop
# Ограничение числа соединений (уже настроено)
cat /etc/systemd/system/ssh.socket.d/override.conf
# Настройка лимитов
cat /etc/security/limits.conf
```
### 🛡️ Безопасность
#### Рекомендации
- Смените пароль при первом входе!
- Не передавайте временный пароль третьим лицам
- Регулярно проверяйте логи GeoIP
- Периодически запускайте rkhunter и lynis
- Следите за свободным местом на диске
- Регулярно обновляйте систему вручную:
```bash
apt update && apt upgrade -y
```
#### Дополнительная настройка
Изменение списка блокируемых стран
```bash
# Редактируйте файл мониторинга
nano /usr/local/bin/geoip-monitor.sh
# Найдите строку:
BLOCK_COUNTRIES=("China" "Russia" ...)
# Добавьте или удалите страны
# Перезапустите сервис
systemctl restart geoip-monitor
```
Добавление своих портов в UFW
```bash
# Например для MySQL
ufw allow 3306/tcp
# Для Docker
ufw allow 2375/tcp
```
Проверка после установки
```bash
# 1. Проверка открытых портов
nmap localhost
# 2. Проверка GeoIP
geoip-stats
# 3. Проверка Fail2Ban
fail2ban-client status sshd
# 4. Проверка автообновлений
cat /etc/apt/apt.conf.d/20auto-upgrades
# 5. Проверка логов
tail -20 /var/log/geoip-alerts.log
```
### 📞 Поддержка
При возникновении проблем:
- Проверьте логи: /var/log/geoip-alerts.log
- Проверьте статус сервисов: systemctl status geoip-monitor fail2ban ssh ufw
- Убедитесь, что текущая SSH сессия открыта для аварийного доступа
- Проверьте конфигурационные файлы на ошибки
#### ⚠️ ВАЖНО: Никогда не закрывайте текущую SSH сессию, пока не проверите новое подключение!
