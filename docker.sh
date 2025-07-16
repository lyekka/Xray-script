#!/usr/bin/env bash
#
# System Required:  CentOS 7+, Debian 10+, Ubuntu 20+
# Description:      Скрипт для управления Docker
#
# Copyright (C) 2025 zxcvos
#
# оптимизировано AI(Qwen2.5-Max-QwQ)
#
# Xray-script:
#   https://github.com/zxcvos/Xray-script
#
# docker-install:
#   https://github.com/docker/docker-install
#
# Cloudflare WARP:
#   https://github.com/haoel/haoel.github.io?tab=readme-ov-file#1043-docker-прокси
#   https://github.com/e7h4n/cloudflare-warp
#
# Cloudreve:
#   https://cloudreve.org

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

# Определение цветов
readonly RED='\033[1;31;31m'
readonly GREEN='\033[1;31;32m'
readonly YELLOW='\033[1;31;33m'
readonly NC='\033[0m'

# Директории
readonly CUR_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
readonly CUR_FILE="$(basename $0)"

# Функции вывода статуса
function print_info() {
  printf "${GREEN}[Информация] ${NC}%s\n" "$*"
}

function print_warn() {
  printf "${YELLOW}[Предупреждение] ${NC}%s\n" "$*"
}

function print_error() {
  printf "${RED}[Ошибка] ${NC}%s\n" "$*"
  exit 1
}

# Вспомогательные функции
function _exists() {
  local cmd="$1"
  if eval type type >/dev/null 2>&1; then
    eval type "$cmd" >/dev/null 2>&1
  elif command >/dev/null 2>&1; then
    command -v "$cmd" >/dev/null 2>&1
  else
    which "$cmd" >/dev/null 2>&1
  fi
  local rt=$?
  return ${rt}
}

function _os() {
  local os=""
  [[ -f "/etc/debian_version" ]] && source /etc/os-release && os="${ID}" && printf -- "%s" "${os}" && return
  [[ -f "/etc/redhat-release" ]] && os="centos" && printf -- "%s" "${os}" && return
}

function _os_full() {
  [[ -f /etc/redhat-release ]] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
  [[ -f /etc/os-release ]] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
  [[ -f /etc/lsb-release ]] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

function _os_ver() {
  local main_ver="$(echo $(_os_full) | grep -oE "[0-9.]+")"
  printf -- "%s" "${main_ver%%.*}"
}

# Проверка ОС
function check_os() {
  [[ -z "$(_os)" ]] && print_error "Неподдерживаемая операционная система."
  case "$(_os)" in
  ubuntu)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 20 ]] && print_error "Неподдерживаемая ОС, переключитесь на Ubuntu 20+ и повторите попытку."
    ;;
  debian)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 10 ]] && print_error "Неподдерживаемая ОС, переключитесь на Debian 10+ и повторите попытку."
    ;;
  centos)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 7 ]] && print_error "Неподдерживаемая ОС, переключитесь на CentOS 7+ и повторите попытку."
    ;;
  *)
    print_error "Неподдерживаемая операционная система."
    ;;
  esac
}

# Установка Docker
function install_docker() {
  if ! _exists "docker"; then
    wget -O /usr/local/xray-script/install-docker.sh https://get.docker.com
    if [[ "$(_os)" == "centos" && "$(_os_ver)" -eq 8 ]]; then
      sed -i 's|$sh_c "$pkg_manager install -y -q $pkgs"| $sh_c "$pkg_manager install -y -q $pkgs --allowerasing"|' /usr/local/xray-script/install-docker.sh
    fi
    sh /usr/local/xray-script/install-docker.sh --dry-run
    sh /usr/local/xray-script/install-docker.sh
  fi
}

# Получение IP контейнера Docker
function get_container_ip() {
  docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"
}

# Сборка образа WARP
function build_warp() {
  if ! docker images --format "{{.Repository}}" | grep -q xray-script-warp; then
    print_info 'Сборка образа WARP'
    mkdir -p /usr/local/xray-script/warp
    mkdir -p ${HOME}/.warp
    wget -O /usr/local/xray-script/warp/Dockerfile https://raw.githubusercontent.com/lyekka/Xray-script/main/cloudflare-warp/Dockerfile || print_error "Ошибка загрузки Dockerfile для WARP"
    wget -O /usr/local/xray-script/warp/startup.sh https://raw.githubusercontent.com/lyekka/Xray-script/main/cloudflare-warp/startup.sh || print_error "Ошибка загрузки startup.sh для WARP"
    docker build -t xray-script-warp /usr/local/xray-script/warp || print_error "Ошибка сборки образа WARP"
  fi
}

# Запуск контейнера WARP
function enable_warp() {
  if ! docker ps --format "{{.Names}}" | grep -q "^xray-script-warp\$"; then
    print_info 'Запуск контейнера WARP'
    docker run -d --restart=always --name=xray-script-warp -v "${HOME}/.warp":/var/lib/cloudflare-warp:rw xray-script-warp || print_error "Ошибка запуска контейнера WARP"
    # Обновление конфигурации
    local container_ip=$(get_container_ip xray-script-warp)
    local socks_config='[{"tag":"warp","protocol":"socks","settings":{"servers":[{"address":"'"${container_ip}"'","port":40001}]}}]'
    jq --argjson socks_config $socks_config '.outbounds += $socks_config' /usr/local/etc/xray/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/etc/xray/config.json
    jq --argjson warp 1 '.warp = $warp' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    print_info "Контейнер WARP включен (IP: ${container_ip})"
  fi
}

# Остановка контейнера WARP
function disable_warp() {
  if docker ps --format "{{.Names}}" | grep -q "^xray-script-warp\$"; then
    print_warn 'Остановка контейнера WARP'
    docker stop xray-script-warp
    docker rm xray-script-warp
    docker image rm xray-script-warp
    rm -rf /usr/local/xray-script/warp
    rm -rf ${HOME}/.warp
    # Очистка конфигурации
    jq 'del(.outbounds[] | select(.tag == "warp")) | del(.routing.rules[] | select(.outboundTag == "warp"))' /usr/local/etc/xray/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/etc/xray/config.json
    jq --argjson warp 0 '.warp = $warp' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    print_info "Контейнер WARP остановлен"
  fi
}

# Установка Cloudreve
function install_cloudreve() {
  if ! docker ps --format "{{.Names}}" | grep -q "^cloudreve\$"; then
    print_info "Создание директорий для Cloudreve."
    mkdir -vp /usr/local/cloudreve &&
      mkdir -vp /usr/local/cloudreve/cloudreve/{uploads,avatar} &&
      touch /usr/local/cloudreve/cloudreve/conf.ini &&
      touch /usr/local/cloudreve/cloudreve/cloudreve.db &&
      mkdir -vp /usr/local/cloudreve/aria2/config &&
      mkdir -vp /usr/local/cloudreve/data/aria2 &&
      chmod -R 777 /usr/local/cloudreve/data/aria2
    print_info "Загрузка docker-compose.yaml для управления Cloudreve."
    wget -O /usr/local/cloudreve/docker-compose.yaml https://raw.githubusercontent.com/lyekka/Xray-script/main/cloudreve/docker-compose.yaml
    print_info "Запуск сервиса Cloudreve"
    cd /usr/local/cloudreve
    docker compose up -d
    sleep 5
  fi
}

# Получение информации о Cloudreve
function get_cloudreve_info() {
  if docker ps --format "{{.Names}}" | grep -q "^cloudreve\$"; then
    local cloudreve_version="$(docker logs cloudreve | grep -Eoi "v[0-9]+.[0-9]+.[0-9]+" | cut -c2-)"
    local cloudreve_username="$(docker logs cloudreve | grep Admin | awk '{print $NF}' | head -1)"
    local cloudreve_password="$(docker logs cloudreve | grep Admin | awk '{print $NF}' | tail -1)"
    jq --arg version "${cloudreve_version}" '.cloudreve.version = $version' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    jq --arg username "${cloudreve_username}" '.cloudreve.username = $username' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    jq --arg password "${cloudreve_password}" '.cloudreve.password = $password' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  fi
}

# Сброс информации Cloudreve
function reset_cloudreve_info() {
  if docker ps --format "{{.Names}}" | grep -q "^cloudreve\$"; then
    print_info "Сброс информации Cloudreve"
    cd /usr/local/cloudreve
    docker compose down
    rm -rf /usr/local/cloudreve/cloudreve/cloudreve.db
    touch /usr/local/cloudreve/cloudreve/cloudreve.db
    docker compose up -d
    sleep 5
    get_cloudreve_info
  fi
}

# Удаление Cloudreve
function purge_cloudreve() {
  if docker ps --format "{{.Names}}" | grep -q "^cloudreve\$"; then
    print_warn "Остановка сервиса Cloudreve"
    cd /usr/local/cloudreve
    docker compose down
    cd ${HOME}
    rm -rf /usr/local/cloudreve
  fi
}

# Отображение справки
function show_help() {
  cat <<EOF
Использование: $0 [опции]

Опции:
  --enable-warp           Включить Cloudflare WARP прокси
  --disable-warp          Выключить Cloudflare WARP прокси
  --install-cloudreve     Установить облачное хранилище Cloudreve
  --reset-cloudreve       Сбросить информацию администратора Cloudreve
  --purge-cloudreve       Удалить Cloudreve и данные
  -h, --help              Показать справку
EOF
  exit 0
}

# Обработка параметров
while [[ $# -gt 0 ]]; do
  case "$1" in
  --enable-warp)
    action="enable_warp"
    ;;
  --disable-warp)
    action="disable_warp"
    ;;
  --install-cloudreve)
    action="install_cloudreve"
    ;;
  --reset-cloudreve)
    action="reset_cloudreve_info"
    ;;
  --purge-cloudreve)
    action="purge_cloudreve"
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

check_os
install_docker

# Выполнение действия
case "${action}" in
enable_warp)
  build_warp
  enable_warp
  ;;
disable_warp) disable_warp ;;
install_cloudreve)
  install_cloudreve
  get_cloudreve_info
  ;;
reset_cloudreve_info) reset_cloudreve_info ;;
purge_cloudreve) purge_cloudreve ;;
esac