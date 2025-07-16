#!/usr/bin/env bash
#
# System Required:  CentOS 7+, Debian 10+, Ubuntu 20+
# Description:      SSL management script
#
# Copyright (C) 2025 zxcvos
#
# Оптимизировано AI(Qwen2.5-Max-QwQ)
#
# acme.sh: https://github.com/acmesh-official/acme.sh

# Цветовые определения
readonly RED='\033[1;31;31m'
readonly GREEN='\033[1;31;32m'
readonly YELLOW='\033[1;31;33m'
readonly NC='\033[0m'

# Регулярное выражение для опциональных параметров
readonly OP_REGEX='(^--(help|update|purge|issue|(stop-)?renew|check-cron|info|www|domain|email|nginx|webroot|tls)$)|(^-[upirscdenwt]$)'

# Действие пользователя
declare action=''

# Опциональные значения
declare -a domains=()
declare account_email=''
declare nginx_config_path=''
declare acme_webroot_path=''
declare ssl_cert_path=''

# Функции вывода статуса
function print_info() {
  printf "${GREEN}[INFO] ${NC}%s\n" "$*"
}

function print_warn() {
  printf "${YELLOW}[WARN] ${NC}%s\n" "$*"
}

function print_error() {
  printf "${RED}[ERROR] ${NC}%s\n" "$*"
  exit 1
}

# Установка acme.sh
function install_acme_sh() {
  [[ -e "${HOME}/.acme.sh/acme.sh" ]] && exit 0
  print_info "Установка acme.sh..."
  curl https://get.acme.sh | sh -s email=${account_email} || print_error "Ошибка установки acme.sh."
  "${HOME}/.acme.sh/acme.sh" --upgrade --auto-upgrade || print_error "Ошибка настройки автообновления acme.sh."
  "${HOME}/.acme.sh/acme.sh" --set-default-ca --server zerossl || print_error "Ошибка установки CA по умолчанию."
}

# Обновление acme.sh
function update_acme_sh() {
  print_info "Обновление acme.sh..."
  "${HOME}/.acme.sh/acme.sh" --upgrade || print_error "Ошибка обновления acme.sh."
}

# Удаление acme.sh
function purge_acme_sh() {
  print_info "Удаление acme.sh..."
  "${HOME}/.acme.sh/acme.sh" --upgrade --auto-upgrade 0 || print_error "Ошибка отключения автообновления acme.sh."
  "${HOME}/.acme.sh/acme.sh" --uninstall || print_error "Ошибка удаления acme.sh."
  rm -rf "${HOME}/.acme.sh" "${acme_webroot_path}" "${nginx_config_path}/certs"
}

# Выпуск сертификата
function issue_certificate() {
  print_info "Выпуск SSL сертификата..."

  # Создание необходимых директорий
  [[ -d "${acme_webroot_path}" ]] || mkdir -vp "${acme_webroot_path}" || print_error "Не удалось создать директорию верификации ACME: ${acme_webroot_path}"
  [[ -d "${ssl_cert_path}" ]] || mkdir -vp "${ssl_cert_path}" || print_error "Не удалось создать директорию SSL сертификатов: ${ssl_cert_path}"

  # Резервное копирование оригинальной конфигурации
  mv -f /usr/local/nginx/conf/nginx.conf /usr/local/nginx/conf/nginx.conf.bak

  # Создание специальной конфигурации для запроса сертификата
  cat >/usr/local/nginx/conf/nginx.conf <<EOF
user                 root;
pid                  /run/nginx.pid;
worker_processes     1;
events {
    worker_connections  1024;
}
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    server {
        listen       80;
        location ^~ /.well-known/acme-challenge/ {
            root /var/www/_zerossl;
        }
    }
}
EOF

  # Проверка работы Nginx
  if systemctl is-active --quiet nginx; then
    nginx -t && systemctl reload nginx || print_error "Ошибка запуска Nginx, проверьте конфигурацию."
  else
    nginx -t && systemctl start nginx || print_error "Ошибка запуска Nginx, проверьте конфигурацию."
  fi

  # Выпуск сертификата
  "${HOME}/.acme.sh/acme.sh" --issue $(printf -- " -d %s" "${domains[@]}") \
    --webroot "${acme_webroot_path}" \
    --keylength ec-256 \
    --accountkeylength ec-256 \
    --server zerossl \
    --ocsp

  if [[ $? -ne 0 ]]; then
    print_warn "Первая попытка выпуска не удалась, пробуем в режиме отладки..."
    "${HOME}/.acme.sh/acme.sh" --issue $(printf -- " -d %s" "${domains[@]}") \
      --webroot "${acme_webroot_path}" \
      --keylength ec-256 \
      --accountkeylength ec-256 \
      --server zerossl \
      --ocsp \
      --debug
    # Восстановление оригинальной конфигурации
    mv -f /usr/local/nginx/conf/nginx.conf.bak /usr/local/nginx/conf/nginx.conf
    print_error "Ошибка запроса ECC сертификата."
  fi

  # Восстановление оригинальной конфигурации
  mv -f /usr/local/nginx/conf/nginx.conf.bak /usr/local/nginx/conf/nginx.conf

  # Перезагрузка nginx
  nginx -t && systemctl reload nginx || print_error "Ошибка запуска Nginx, проверьте конфигурацию."

  # Установка сертификата
  "${HOME}/.acme.sh/acme.sh" --install-cert --ecc $(printf -- " -d %s" "${domains[@]}") \
    --key-file "${ssl_cert_path}/privkey.pem" \
    --fullchain-file "${ssl_cert_path}/fullchain.pem" \
    --reloadcmd "nginx -t && systemctl reload nginx" || print_error "Ошибка установки сертификата."
}

# Обновление сертификатов
function renew_certificates() {
  print_info "Принудительное обновление всех SSL сертификатов..."
  "${HOME}/.acme.sh/acme.sh" --cron --force || print_error "Ошибка обновления."
}

# Остановка обновления сертификатов
function stop_renew_certificates() {
  print_info "Остановка обновления указанных SSL сертификатов..."
  "${HOME}/.acme.sh/acme.sh" --remove $(printf -- " -d %s" "${domains[@]}") --ecc || print_error "Ошибка остановки обновления."
  rm -rf $(printf -- " ${HOME}/.acme.sh/%s_ecc" "${domains[@]}")
  rm -rf $(printf -- " ${nginx_config_path}/certs/%s" "${domains[@]}")
}

# Проверка cron задач
function check_cron_jobs() {
  print_info "Проверка настроек автоматического обновления..."
  "${HOME}/.acme.sh/acme.sh" --cron --home "${HOME}/.acme.sh" || print_error "Ошибка проверки cron задач."
}

# Отображение информации о сертификате
function show_certificate_info() {
  print_info "Отображение информации о SSL сертификате..."
  "${HOME}/.acme.sh/acme.sh" --info $(printf -- " -d %s" "${domains[@]}") || print_error "Ошибка получения информации о сертификате."
}

# Поиск директории конфигурации nginx
function find_nginx_config() {
  if [[ -d /etc/nginx ]]; then
    echo "/etc/nginx"
  elif [[ -d /usr/local/nginx/conf ]]; then
    echo "/usr/local/nginx/conf"
  else
    print_error "Директория конфигурации Nginx не найдена"
  fi
}

# Отображение справки
function show_help() {
  cat <<EOF
Использование: $0 [команда] [опции]

Команды:
  --install           Установка acme.sh
  -u, --update        Обновление acme.sh
  -p, --purge         Удаление acme.sh и связанных директорий
  -i, --issue         Выпуск/обновление SSL сертификата
  -r, --renew         Принудительное обновление всех SSL сертификатов
  -s, --stop-renew    Остановка обновления указанных SSL сертификатов
  -c, --check-cron    Проверка настроек автоматического обновления
      --info          Отображение информации о SSL сертификате

Опции:
  -d, --domain        Указание домена (можно использовать несколько раз)
  -n, --nginx         Указание пути к конфигурации Nginx
  -w, --webroot       Указание пути к директории верификации ACME
  -t, --tls           Указание пути к директории SSL сертификатов (по умолчанию на основе первого домена)
  -h, --help          Отображение этой справки
EOF
  exit 0
}

# Разбор параметров
while [[ $# -gt 0 ]]; do
  case "$1" in
  --install)
    action="install"
    ;;
  -u | --update)
    action="update"
    ;;
  -p | --purge)
    action="purge"
    ;;
  -i | --issue)
    action="issue"
    ;;
  -r | --renew)
    action="renew"
    ;;
  -s | --stop-renew)
    action="stop"
    ;;
  -c | --check-cron)
    action="check"
    ;;
  --info)
    action="info"
    ;;
  -d | --domain)
    shift
    [[ -z "$1" || "$1" =~ ${OP_REGEX} ]] && print_error "Не указан корректный домен"
    domains+=("$1")
    ;;
  -e | --email)
    shift
    [[ -z "$1" || "$1" =~ ${OP_REGEX} ]] && print_error "Не указана почта"
    account_email="$1"
    ;;
  -n | --nginx)
    shift
    [[ -z "$1" || "$1" =~ ${OP_REGEX} ]] && print_error "Не указан корректный путь к конфигурации Nginx"
    nginx_config_path="$1"
    ;;
  -w | --webroot)
    shift
    [[ -z "$1" || "$1" =~ ${OP_REGEX} ]] && print_error "Не указан корректный путь к директории верификации ACME"
    acme_webroot_path="$1"
    ;;
  -t | --tls)
    shift
    [[ -z "$1" || "$1" =~ ${OP_REGEX} ]] && print_error "Не указан корректный путь к директории SSL сертификатов"
    ssl_cert_path="$1"
    ;;
  -h | --help)
    show_help
    ;;
  *)
    print_error "Неверная опция: '$1'. Используйте '$0 -h/--help' для просмотра справки."
    ;;
  esac
  shift
done

# Проверка параметров
[[ -z ${action} ]] && print_error "Не указано действие. Используйте --help для просмотра справки"

# Инициализация значений по умолчанию
nginx_config_path=${nginx_config_path:-$(find_nginx_config)}
account_email=${account_email:-my@example.com}
acme_webroot_path=${acme_webroot_path:-/var/www/_zerossl}
ssl_cert_path=${ssl_cert_path:-${nginx_config_path}/certs/${domains[0]:-default}}

# Проверка установки acme.sh
if [[ ! -e "${HOME}/.acme.sh/acme.sh" && 'install' != ${action} ]]; then
  print_error "Сначала установите acme.sh используя '$0 --install [--email my@email.com]'"
fi

# Выполнение действия
case "${action}" in
install) install_acme_sh ;;
update) update_acme_sh ;;
purge) purge_acme_sh ;;
issue) issue_certificate ;;
renew) renew_certificates ;;
stop) stop_renew_certificates ;;
check) check_cron_jobs ;;
info) show_certificate_info ;;
esac