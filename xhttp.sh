#!/usr/bin/env bash
#
# System Required:  CentOS 7+, Debian9+, Ubuntu16+
# Description:      Скрипт для управления Xray
#
# Copyright (C) 2025 zxcvos
#
# Xray-script:
#   https://github.com/zxcvos/Xray-script
#
# Xray Official:
#   Xray-core: https://github.com/XTLS/Xray-core
#   REALITY: https://github.com/XTLS/REALITY
#   XHTTP: https://github.com/XTLS/Xray-core/discussions/4113
#
# Xray-examples:
#   https://github.com/chika0801/Xray-examples
#   https://github.com/lxhao61/integrated-examples
#   https://github.com/XTLS/Xray-core/discussions/4118

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

# цвета
readonly RED='\033[1;31;31m'
readonly GREEN='\033[1;31;32m'
readonly YELLOW='\033[1;31;33m'
readonly NC='\033[0m'

# директории
readonly CUR_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
readonly CUR_FILE="$(basename $0)"

# опции установки
declare INSTALL_OPTION=''

# указанная версия
declare SPECIFIED_VERSION=''

# статус
declare STATUS=''

# warp
declare WARP=''

# автоматизация
declare IS_AUTO=''

# обновление конфига
declare UPDATE_CONFIG=''

# sni конфиг
declare SNI_CONFIG=''

# xtls конфиг
declare XTLS_CONFIG='xhttp'

# URL загрузки
declare DOWNLOAD_URL=''

# порт xray
declare XRAY_PORT=443

# uuid xray
declare XRAY_UUID=''

# fallback uuid
declare FALLBACK_UUID=''

# seed kcp
declare KCP_SEED=''

# пароль trojan
declare TROJAN_PASSWORD=''

# целевой домен
declare TARGET_DOMAIN=''

# имена серверов
declare SERVER_NAMES=''

# приватный ключ
declare PRIVATE_KEY=''

# публичный ключ
declare PUBLIC_KEY=''

# short id
declare SHORT_IDS=''

# путь xhttp
declare XHTTP_PATH=''

# ссылка для分享
declare SHARE_LINK=''

# вывод статуса
function _input_tips() {
  printf "${GREEN}[Ввод] ${NC}"
  printf -- "%s" "$@"
}

function _info() {
  printf "${GREEN}[Инфо] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
}

function _warn() {
  printf "${YELLOW}[Предупреждение] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
}

function _error() {
  printf "${RED}[Ошибка] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
  exit 1
}

# утилиты
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

function _error_detect() {
  local cmd="$1"
  _info "${cmd}"
  eval ${cmd}
  if [[ $? -ne 0 ]]; then
    _error "Выполнение команды (${cmd}) не удалось, проверьте и попробуйте снова."
  fi
}

function _is_digit() {
  local input=${1}
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    return 0
  else
    return 1
  fi
}

function _version_ge() {
  test "$(echo "$@" | tr ' ' '\n' | sort -rV | head -n 1)" == "$1"
}

function _is_tls1_3_h2() {
  local check_url=$(echo $1 | grep -oE '[^/]+(\.[^/]+)+\b' | head -n 1)
  local check_num=$(echo QUIT | stdbuf -oL openssl s_client -connect "${check_url}:443" -tls1_3 -alpn h2 2>&1 | grep -Eoi '(TLSv1.3)|(^ALPN\s+protocol:\s+h2$)|(X25519)' | sort -u | wc -l)
  if [[ ${check_num} -eq 3 ]]; then
    return 0
  else
    return 1
  fi
}

function _is_network_reachable() {
  local url="$1"
  curl -s --head --connect-timeout 5 "$url" >/dev/null
  if [ $? -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

function _install() {
  local packages_name="$@"
  case "$(_os)" in
  centos)
    if _exists "dnf"; then
      dnf update -y
      dnf install -y dnf-plugins-core
      dnf update -y
      for package_name in ${packages_name}; do
        dnf install -y ${package_name}
      done
    else
      yum update -y
      yum install -y epel-release yum-utils
      yum update -y
      for package_name in ${packages_name}; do
        yum install -y ${package_name}
      done
    fi
    ;;
  ubuntu | debian)
    apt update -y
    for package_name in ${packages_name}; do
      apt install -y ${package_name}
    done
    ;;
  esac
}

function _systemctl() {
  local cmd="$1"
  local server_name="$2"
  case "${cmd}" in
  start)
    _info "Запуск службы ${server_name}"
    systemctl -q is-active ${server_name} || systemctl -q start ${server_name}
    systemctl -q is-enabled ${server_name} || systemctl -q enable ${server_name}
    sleep 2
    systemctl -q is-active ${server_name} && _info "Служба ${server_name} запущена" || _error "Не удалось запустить ${server_name}"
    ;;
  stop)
    _info "Остановка службы ${server_name}"
    systemctl -q is-active ${server_name} && systemctl -q stop ${server_name}
    systemctl -q is-enabled ${server_name} && systemctl -q disable ${server_name}
    sleep 2
    systemctl -q is-active ${server_name} || _info "Служба ${server_name} остановлена"
    ;;
  restart)
    _info "Перезапуск службы ${server_name}"
    systemctl -q is-active ${server_name} && systemctl -q restart ${server_name} || systemctl -q start ${server_name}
    systemctl -q is-enabled ${server_name} || systemctl -q enable ${server_name}
    sleep 2
    systemctl -q is-active ${server_name} && _info "Служба ${server_name} перезапущена" || _error "Не удалось запустить ${server_name}"
    ;;
  reload)
    _info "Перезагрузка службы ${server_name}"
    systemctl -q is-active ${server_name} && systemctl -q reload ${server_name} || systemctl -q start ${server_name}
    systemctl -q is-enabled ${server_name} || systemctl -q enable ${server_name}
    sleep 2
    systemctl -q is-active ${server_name} && _info "Служба ${server_name} перезагружена"
    ;;
  dr)
    _info "Перезагрузка конфигурации systemd"
    systemctl daemon-reload
    ;;
  esac
}

function download_github_files() {
  local conf_dir="${1:-/usr/local/xray-script}"
  local github_api="${2:-https://api.github.com/repos/lyekka/Xray-script/contents}"

  # Получение списка файлов/директорий через GitHub API
  local download_urls=$(curl -s ${github_api} | jq -r '.[] | select(.type=="file") | .download_url')
  local dirs=$(curl -s ${github_api} | jq -r '.[] | select(.type=="dir") | .name')

  # Создание директорий и рекурсивная загрузка файлов из поддиректорий
  for dir in $dirs; do
    mkdir -vp ${conf_dir}/${dir}
    download_github_files ${conf_dir}/${dir} ${github_api}/${dir}
  done

  # Загрузка файлов
  for download_url in $download_urls; do
    local file=${download_url##*/}
    echo "Загрузка ${file}..."
    wget --no-check-certificate -O "${conf_dir}/${file}" "${download_url}" || {
      echo "Ошибка загрузки: ${file}"
      continue
    }
    chmod 0644 "${conf_dir}/${file}"
  done

  echo "Файлы с GitHub загружены в ${conf_dir}"
}

function check_xray_script_dependencies() {
  local -a dependencies=(
    "ssl.sh|https://api.github.com/repos/lyekka/Xray-script/contents/ssl.sh"
    "nginx.sh|https://api.github.com/repos/lyekka/Xray-script/contents/nginx.sh"
    "docker.sh|https://api.github.com/repos/lyekka/Xray-script/contents/docker.sh"
  )

  local updated=false
  local target_dir="/usr/local/xray-script"

  # При первом использовании, если директория не существует, пропускаем проверку обновлений
  if [[ ! -d "$target_dir" ]]; then
    return
  fi

  for dep in "${dependencies[@]}"; do
    IFS='|' read -r filename api_url <<<"$dep"
    local local_file="${target_dir}/${filename}"
    local tmp_file="${local_file}.tmp"

    # Получаем размер удаленного файла
    local remote_size
    if ! remote_size=$(curl -fsSL "$api_url" | jq -r '.size'); then
      _info "Не удалось получить метаданные ${filename}, пропускаем проверку обновлений"
      continue
    fi

    # Получаем размер локального файла
    local local_size
    if ! local_size=$(stat -c %s "$local_file" 2>/dev/null); then
      _info "Не удалось определить размер локального файла ${filename}, пробуем перезагрузить"
      local_size=0
    fi

    # Сравниваем размеры файлов
    if [[ "$remote_size" != "$local_size" ]]; then
      _info "Обнаружено обновление для зависимости ${filename}"
      if wget -q --show-progress -O "$tmp_file" "https://raw.githubusercontent.com/lyekka/Xray-script/main/${filename}"; then
        mv "$tmp_file" "$local_file"
        updated=true
      else
        _info "Не удалось загрузить ${filename}, сохраняем текущую версию"
        rm -f "$tmp_file"
      fi
    fi
  done

  if $updated; then
    _info 'Зависимости успешно обновлены'
    sleep 2
  fi
}
function check_xray_script_version() {
  [[ -d /usr/local/xray-script ]] || return
  local url="https://api.github.com/repos/lyekka/Xray-script/contents/xhttp.sh"
  local local_size=$(stat -c %s "${CUR_DIR}/${CUR_FILE}")
  local remote_size=$(curl -fsSL "$url" | jq -r '.size')

  if [[ "${local_size}" != "${remote_size}" ]]; then
    _info 'Обнаружена новая версия скрипта, обновить?'
    _input_tips 'Обновить? [Y/n] '
    read -r is_update_script

    case "${is_update_script,,}" in
    n)
      _warn 'Рекомендуется обновить скрипт как можно скорее'
      sleep 2
      ;;
    *)
      _info "Загружается новая версия скрипта..."

      # Создание временного файла
      local tmp_script=$(mktemp)

      # Загрузка нового скрипта и проверка успешности
      if ! wget --no-check-certificate -O "$tmp_script" "https://raw.githubusercontent.com/lyekka/Xray-script/main/xhttp.sh"; then
        rm -rf "${tmp_script}"
        _warn "Не удалось загрузить новую версию скрипта, обновите вручную"
        _warn "echo 'wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/lyekka/Xray-script/main/xhttp.sh && bash ${HOME}/Xray-script.sh'"
        exit 1
      fi

      # Замена текущего скрипта
      mv -f "${tmp_script}" "${CUR_DIR}/${CUR_FILE}"
      chmod +x "${CUR_DIR}/${CUR_FILE}"

      _info "Скрипт обновлен, перезапуск..."

      # Повторный запуск нового скрипта с оригинальными аргументами
      exec bash "${CUR_DIR}/${CUR_FILE}" "$@"

      # Завершение текущего процесса
      exit 0
      ;;
    esac
  fi
}

# Проверка DNS-разрешения
function check_dns_resolution() {
  local domain=$1
  # Получение публичных IPv4 и IPv6 текущей машины
  local expected_ipv4="$(curl -fsSL ipv4.icanhazip.com)"
  local expected_ipv6="$(curl -fsSL ipv6.icanhazip.com)"
  local resolved=0
  # Использование dig для запроса DNS-записей домена
  local actual_ipv4="$(dig +short "${domain}")"
  local actual_ipv6="$(dig +short AAAA "${domain}")"
  # Проверка совпадения разрешенного IPv4 с публичным IPv4 машины
  if [[ "${actual_ipv4}" =~ "${expected_ipv4}" ]]; then
    resolved=1
  fi
  # Проверка совпадения разрешенного IPv6 с публичным IPv6 машины
  if [[ "${actual_ipv6}" =~ "${expected_ipv6}" ]]; then
    resolved=1
  fi
  # Если ни IPv4, ни IPv6 не разрешены корректно, вывести предупреждение
  if [[ ${resolved} -eq 0 ]]; then
    _warn "Домен ${domain} не разрешается в публичный IPv4 или IPv6 этой машины, возможны проблемы с получением SSL-сертификата"
  fi
}

function urlencode() {
  local input
  if [[ $# -eq 0 ]]; then
    input="$(cat)"
  else
    input="$1"
  fi

  local encoded=""
  local i c hex

  for ((i = 0; i < ${#input}; i++)); do
    c="${input:$i:1}"
    case $c in
    [a-zA-Z0-9.~_-])
      encoded+="$c"
      ;;
    *)
      printf -v hex "%02X" "'$c"
      encoded+="%$hex"
      ;;
    esac
  done
  echo "$encoded"
}

function get_char() {
  SAVEDSTTY=$(stty -g)
  stty -echo
  stty cbreak
  dd if=/dev/tty bs=1 count=1 2>/dev/null
  stty -raw
  stty echo
  stty $SAVEDSTTY
}

function check_os() {
  [[ -z "$(_os)" ]] && _error "Операционная система не поддерживается"
  case "$(_os)" in
  ubuntu)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 16 ]] && _error "Операционная система не поддерживается, пожалуйста, используйте Ubuntu 16+ и попробуйте снова."
    ;;
  debian)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 9 ]] && _error "Операционная система не поддерживается, пожалуйста, используйте Debian 9+ и попробуйте снова."
    ;;
  centos)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 7 ]] && _error "Операционная система не поддерживается, пожалуйста, используйте CentOS 7+ и попробуйте снова."
    ;;
  *)
    _error "Операционная система не поддерживается"
    ;;
  esac
}

function check_dependencies() {
  local missing_packages=()
  case "$(_os)" in
  centos)
    local packages=("ca-certificates" "openssl" "curl" "wget" "git" "jq" "tzdata" "qrencode" "crontabs" "util-linux" "iproute" "procps-ng")
    for pkg in "${packages[@]}"; do
      if ! rpm -q "$pkg" &>/dev/null; then
        missing_packages+=("$pkg")
      fi
    done
    ;;
  debian | ubuntu)
    local packages=("ca-certificates" "openssl" "curl" "wget" "git" "jq" "tzdata" "qrencode" "cron" "bsdmainutils" "iproute2" "procps")
    for pkg in "${packages[@]}"; do
      if ! dpkg -s "$pkg" &>/dev/null; then
        missing_packages+=("$pkg")
      fi
    done
    ;;
  esac
  [ ${#missing_packages[@]} -eq 0 ]
}

function install_dependencies() {
  _info "Загрузка необходимых зависимостей"
  _install "ca-certificates openssl curl wget git jq tzdata qrencode"
  case "$(_os)" in
  centos)
    _install "crontabs util-linux iproute procps-ng"
    ;;
  debian | ubuntu)
    _install "cron bsdmainutils iproute2 procps"
    ;;
  esac
}

function get_random_number() {
  local custom_min=${1}
  local custom_max=${2}
  if ((custom_min > custom_max)); then
    _error "Ошибка: минимальное значение не может быть больше максимального."
  fi
  local random_number=$(od -vAn -N2 -i /dev/urandom | awk '{print int($1 % ('$custom_max' - '$custom_min') + '$custom_min')}')
  echo $random_number
}

function get_random_port() {
  local random_number=$(get_random_number 1025 65536)
  echo $random_number
}

function validate_hex_input() {
  local input=$1
  if [[ $input =~ ^[0-9a-f]+$ ]] && ((${#input} % 2 == 0)) && ((${#input} <= 16)); then
    return 0
  else
    return 1
  fi
}

function check_xray_version_is_exists() {
  local xray_version_url="https://github.com/XTLS/Xray-core/releases/tag/v${1##*v}"
  local status_code=$(curl -o /dev/null -s -w '%{http_code}\n' "$xray_version_url")
  if [[ "$status_code" = "404" ]]; then
    _error "Не удалось найти указанную версию: $1"
  fi
}

function enable_warp() {
  bash /usr/local/xray-script/docker.sh --enable-warp
}

function disable_warp() {
  bash /usr/local/xray-script/docker.sh --disable-warp
}

function enable_nginx_cron() {
  local nginx_status=$(jq -r '.sni.status' /usr/local/xray-script/config.json)
  if [[ ${nginx_status} -eq 1 ]]; then
    chmod a+x /usr/local/xray-script/nginx.sh
    (
      crontab -l 2>/dev/null
      echo "0 3 * * * /usr/local/xray-script/nginx.sh -u -b >/dev/null 2>&1"
    ) | awk '!x[$0]++' | crontab -
    /usr/local/xray-script/update-dat.sh
  fi
}

function disable_nginx_cron() {
  crontab -l | grep -v "/usr/local/xray-script/nginx.sh -u -b >/dev/null 2>&1" | crontab -
}

function change_domain() {
  local nginx_status=$(jq -r '.sni.status' /usr/local/xray-script/config.json)
  if [[ ${nginx_status} -eq 1 ]]; then
    read_sni_cdn_domain
    jq --arg target "${reality_domain}" '.target = $target' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    _info "Целевой домен: ${reality_domain}"
    _info "CDN домен: ${cdn_domain}"
    SERVER_NAMES="$(echo '["'"${reality_domain}"'"]' | jq -r)"
    setup_ssl
  fi
}

function show_cloudreve_data() {
  local cloudreve_version=$(jq -r '.cloudreve.version' /usr/local/xray-script/config.json)
  local cloudreve_username=$(jq -r '.cloudreve.username' /usr/local/xray-script/config.json)
  local cloudreve_password=$(jq -r '.cloudreve.password' /usr/local/xray-script/config.json)
  if [[ -z "${cloudreve_version}" ]]; then
    return
  fi
  echo "Версия Cloudreve: ${cloudreve_version}"
  echo "Логин Cloudreve: ${cloudreve_username}"
  echo "Пароль Cloudreve: ${cloudreve_password}"
}

function reset_cloudreve_data() {
  bash /usr/local/xray-script/docker.sh --reset-cloudreve
  show_cloudreve_data
}

function enable_cron() {
  if ! [[ -f /usr/local/xray-script/update-dat.sh ]]; then
    wget --no-check-certificate -O /usr/local/xray-script/update-dat.sh https://raw.githubusercontent.com/lyekka/Xray-script/main/tool/update-dat.sh
    chmod a+x /usr/local/xray-script/update-dat.sh
    (
      crontab -l 2>/dev/null
      echo "30 6 * * * /usr/local/xray-script/update-dat.sh >/dev/null 2>&1"
    ) | awk '!x[$0]++' | crontab -
    /usr/local/xray-script/update-dat.sh
  fi
}

function disable_cron() {
  if [[ -f /usr/local/xray-script/update-dat.sh ]]; then
    crontab -l | grep -v "/usr/local/xray-script/update-dat.sh >/dev/null 2>&1" | crontab -
    rm -rf /usr/local/xray-script/update-dat.sh
  fi
}

# Функция добавления правил
function add_rule() {
  local CONFIG_FILE='/usr/local/etc/xray/config.json'
  local TMP_FILE='/usr/local/xray-script/tmp.json'
  local rule_tag=$1
  local domain_or_ip=$2
  local value=$(echo "$3" | tr ',' '\n' | jq -R . | jq -s .)
  local outboundTag=$4
  local position=$5   # Параметр позиции вставки: "before" или "after"
  local target_tag=$6 # Целевой ruleTag для указания позиции вставки

  # Чтение исходного массива правил
  local current_rules=$(jq '.routing.rules' "$CONFIG_FILE")

  # Проверка существования ruleTag
  local existing_rule=$(echo "$current_rules" | jq -r --arg ruleTag "$rule_tag" '.[] | select(.ruleTag == $ruleTag)')
  if [[ "$existing_rule" ]]; then
    # Если ruleTag существует, добавляем в domain или ip массив
    if [[ "$domain_or_ip" == "domain" ]]; then
      jq --arg ruleTag "$rule_tag" --argjson value "$value" '.routing.rules |= map(if .ruleTag == $ruleTag then .domain += $value | .domain |= unique else . end)' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
    elif [[ "$domain_or_ip" == "ip" ]]; then
      jq --arg ruleTag "$rule_tag" --argjson value "$value" '.routing.rules |= map(if .ruleTag == $ruleTag then .ip += $value | .ip |= unique else . end)' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
    fi
  else
    # Если ruleTag не существует, создаем новое правило
    new_rule="[{\"ruleTag\":\"$rule_tag\",\"$domain_or_ip\":$value,\"outboundTag\":\"$outboundTag\"}]"

    # Если указан target_tag и position
    if [[ -n "$target_tag" ]]; then
      # Проверяем существование целевого ruleTag
      local target_rule=$(echo "$current_rules" | jq -r --arg ruleTag "$target_tag" '.[] | select(.ruleTag == $ruleTag)')

      if [[ "$target_rule" ]]; then
        # Получаем позицию целевого ruleTag
        local target_index=$(echo "$current_rules" | jq -r --arg ruleTag "$target_tag" 'to_entries | map(select(.value.ruleTag == $ruleTag)) | .[0].key')
        if [[ "$position" == "before" ]]; then
          # Вставка перед target_tag
          jq --argjson target_index $target_index --argjson new_rule "$new_rule" '.routing.rules |= .[:$target_index] + $new_rule + .[$target_index:]' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
        elif [[ "$position" == "after" ]]; then
          # Вставка после target_tag
          jq --argjson target_index $((target_index + 1)) --argjson new_rule "$new_rule" '.routing.rules |= .[:$target_index] + $new_rule + .[$target_index:]' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
        else
          # Если position не "before" или "after", добавляем в конец
          jq --argjson new_rule "$new_rule" '.routing.rules += $new_rule' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
        fi
      else
        # Если target_tag не существует, добавляем в конец
        jq --argjson new_rule "$new_rule" '.routing.rules += $new_rule' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
      fi
    else
      if [[ -n "$position" && "$position" -ge 0 ]]; then
        # Если указана позиция вставки и она валидна (>=0), вставляем на указанную позицию
        jq --argjson position $position --argjson new_rule "$new_rule" '.routing.rules |= .[:$position] + $new_rule + .[$position:]' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
      else
        # Если позиция не указана или невалидна, добавляем в конец
        jq --argjson new_rule "$new_rule" '.routing.rules += $new_rule' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
      fi
    fi
  fi
}

function add_rule_warp_ip() {
  if [[ "${WARP}" -eq 1 ]]; then
    _warn 'Пользователи по умолчанию понимают правила добавления правил маршрутизации'
    _info 'Поддерживаются несколько значений, разделенных запятыми'
    _input_tips 'Введите IP-адреса для маршрутизации через WARP: '
    read -r rule_warp_ip
    if [[ -n "$rule_warp_ip" ]]; then
      add_rule "warp-ip" "ip" "$rule_warp_ip" "warp" "before" "ad-domain"
    fi
  else
    _error 'Включите WARP Proxy перед настройкой маршрутизации'
  fi
}

function add_rule_warp_domain() {
  if [[ "${WARP}" -eq 1 ]]; then
    _warn 'Пользователи по умолчанию понимают правила добавления правил маршрутизации'
    _info 'Поддерживаются несколько значений, разделенных запятыми'
    _input_tips 'Введите домены для маршрутизации через WARP: '
    read -r rule_warp_domain
    if [[ -n "$rule_warp_domain" ]]; then
      add_rule "warp-domain" "domain" "$rule_warp_domain" "warp" "before" "ad-domain"
    fi
  else
    _error 'Включите WARP Proxy перед настройкой маршрутизации'
  fi
}

function add_rule_block_ip() {
  _warn 'Пользователи по умолчанию понимают правила добавления правил маршрутизации'
  _info 'Поддерживаются несколько значений, разделенных запятыми'
  _input_tips 'Введите IP-адреса для блокировки: '
  read -r rule_block_ip
  if [[ -n "$rule_block_ip" ]]; then
    add_rule "block-ip" "ip" "$rule_block_ip" "block" "after" "private-ip"
  fi
}

function add_rule_block_domain() {
  _warn 'Пользователи по умолчанию понимают правила добавления правил маршрутизации'
  _info 'Поддерживаются несколько значений, разделенных запятыми'
  _input_tips 'Введите домены для блокировки: '
  read -r rule_domain_domain
  if [[ -n "$rule_domain_domain" ]]; then
    add_rule "block-domain" "domain" "$rule_domain_domain" "block" "after" "private-ip"
  fi
}

function add_rule_block_bt() {
  if [[ ${is_block_bt} =~ ^[Yy]$ ]]; then
    add_rule "bt" "protocol" "bittorrent" "block" 1
  fi
}

function add_rule_block_cn_ip() {
  if [[ ${is_block_cn_ip} =~ ^[Yy]$ ]]; then
    add_rule "cn-ip" "ip" "geoip:cn" "block" "after" "private-ip"
  fi
}

function add_rule_block_ads() {
  if [[ ${is_block_ads} =~ ^[Yy]$ ]]; then
    add_rule "ad-domain" "domain" "geosite:category-ads-all" "block"
  fi
}

function add_update_geodata() {
  if [[ ${is_update_geodata} =~ ^[Yy]$ ]]; then
    enable_cron
  fi
}

function read_block_bt() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    is_block_bt='Y'
  else
    _input_tips 'Блокировать bittorrent трафик? [y/N] '
    read -r is_block_bt
  fi
}

function read_block_cn_ip() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    is_block_cn_ip='Y'
  else
    _input_tips 'Блокировать китайские IP-адреса? [y/N] '
    read -r is_block_cn_ip
  fi
}

function read_block_ads() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    is_block_ads='Y'
  else
    _input_tips 'Блокировать рекламу? [y/N] '
    read -r is_block_ads
  fi
}

function read_update_geodata() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    is_update_geodata='Y'
  else
    _input_tips 'Включить автоматическое обновление geodata? [y/N] '
    read -r is_update_geodata
  fi
}

function read_port() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _info 'Диапазон портов: число от 1 до 65535. Если введенное значение вне диапазона, будет использовано значение по умолчанию'
  _input_tips 'Введите пользовательский порт (по умолчанию генерируется автоматически): '
  read -r in_port
}

function read_uuid() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _info 'Пользовательский UUID. Если формат не соответствует стандарту, будет использовано преобразование UUIDv5 через xray uuid -i "ваша_строка"'
  _input_tips 'Введите пользовательский UUID (по умолчанию генерируется автоматически): '
  read -r in_uuid
}

function read_seed() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _input_tips 'Введите пользовательский seed (по умолчанию генерируется автоматически): '
  read -r in_seed
}

function read_password() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _input_tips 'Введите пользовательский пароль (по умолчанию генерируется автоматически): '
  read -r in_password
}

function read_domain() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _info "Если введенный домен существует в serverNames.json как ключ, будут использованы соответствующие данные"
  until [[ ${is_domain} =~ ^[Yy]$ ]]; do
    _input_tips 'Введите пользовательский домен (по умолчанию генерируется автоматически): '
    read -r in_domain
    if [[ -z "${in_domain}" ]]; then
      break
    fi
    check_domain=$(echo ${in_domain} | grep -oE '[^/]+(\.[^/]+)+\b' | head -n 1)
    if ! _is_network_reachable "${check_domain}"; then
      _warn "\"${check_domain}\" недоступен"
      continue
    fi
    if ! _is_tls1_3_h2 "${check_domain}"; then
      _warn "\"${check_domain}\" не поддерживает TLSv1.3 или h2, либо Client Hello не X25519"
      _info "Если вы уверены, что \"${check_domain}\" поддерживает TLSv1.3(h2) и X25519, возможна ошибка определения"
      _input_tips 'Подтвердить поддержку [y/N] '
      read -r is_support
      if [[ ${is_support} =~ ^[Yy]$ ]]; then
        break
      else
        continue
      fi
    fi
    is_domain='Y'
  done
  in_domain=${check_domain}
}

function read_sni_cdn_domain() {
  _input_tips 'Введите домен (REALITY): '
  read -r reality_domain
  check_dns_resolution ${reality_domain}
  _info 'Если домен CDN не указан, по умолчанию будет использован тот же домен, что и для REALITY'
  _input_tips 'Введите домен (CDN): '
  read -r cdn_domain
  if [[ -z ${cdn_domain} ]]; then
    cdn_domain=${reality_domain}
  else
    check_dns_resolution ${cdn_domain}
  fi
}

function read_zero_ssl_account_email() {
  _info 'Этот email используется для регистрации в ZeroSSL. Если не указан, будет использован пример из acme.sh: my@example.com'
  _input_tips 'Введите email: '
  read -r account_email
}

function read_short_ids() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _info 'shortId: символы от 0 до f, длина кратна 2, максимальная длина - 16'
  _info 'Если ввести число от 0 до 8, будет сгенерирован shortId длиной от 0 до 16'
  _info 'Поддерживаются несколько значений, разделенных запятыми'
  _input_tips 'Введите пользовательский shortId (по умолчанию генерируется автоматически): '
  read -r in_short_id
}

function read_path() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _input_tips 'Введите пользовательский path (по умолчанию генерируется автоматически): '
  read -r in_path
}

function generate_port() {
  local input=${1}
  if ! _is_digit "${input}" || [[ ${input} -lt 1 || ${input} -gt 65535 ]]; then
    case ${XTLS_CONFIG} in
    mkcp) input=$(get_random_port) ;;
    *) input=443 ;;
    esac
  fi
  echo ${input}
}

function generate_uuid() {
  local input="${1}"
  local uuid=""
  if [[ -z "${input}" ]]; then
    uuid=$(xray uuid)
  elif printf "%s" "${input}" | grep -Eq '^[0-9a-fA-F]{8}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{12}$'; then
    uuid="${input}"
  else
    uuid=$(xray uuid -i "${input}")
  fi
  echo "${uuid}"
}

function generate_password() {
  local seed="${1}"
  local length="${2}"
  if [[ -z "${length}" ]]; then
    length=16
  fi
  if [[ -z "${seed}" ]]; then
    seed=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' | head -c $length)
  fi
  echo "${seed}"
}

function generate_target() {
  local target=${1}
  if [[ -z "${target}" ]]; then
    local length=$(jq -r '. | length' /usr/local/xray-script/serverNames.json)
    local random_number=$(get_random_number 0 ${length})
    target=$(jq '. | keys | .[]' /usr/local/xray-script/serverNames.json | shuf | jq -s -r --argjson i ${random_number} '.[$i]')
  fi
  jq --arg target "${target}" '.target = $target' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  echo "${target}:443"
}

function generate_server_names() {
  local target=${1%:443}
  local local_target=$(jq --arg key "${target}" '. | has($key)' /usr/local/xray-script/serverNames.json)
  if [[ "${local_target}" == "false" ]]; then
    local all_sns=$(xray tls ping ${target} | sed -n '/with SNI/,$p' | sed -En 's/\[(.*)\]/\1/p' | sed -En 's/Allowed domains:\s*//p' | jq -R -c 'split(" ")' | jq --arg sni "${target}" '. += [$sni]')
    local sns=$(echo ${all_sns} | jq 'map(select(test("^[^*]+$"; "g")))' | jq -c 'map(select(test("^((?!cloudflare|akamaized|edgekey|edgesuite|cloudfront|azureedge|msecnd|edgecastcdn|fastly|googleusercontent|kxcdn|maxcdn|stackpathdns|stackpathcdn|policy|privacy).)*$"; "ig")))' | jq 'unique')
  fi
  jq --arg key "${target}" --argjson serverNames "${sns:-[]}" '
  if . | has($key) then
    .
  else
    . += { ($key): $serverNames }
  end
' /usr/local/xray-script/serverNames.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/serverNames.json
  local server_names="$(jq --arg key "${target}" '.[$key]' /usr/local/xray-script/serverNames.json)"
  echo "${server_names}"
}

function generate_xray_x25519() {
  local xray_x25519=$(xray x25519)
  PRIVATE_KEY=$(echo ${xray_x25519} | awk '{print $3}')
  PUBLIC_KEY=$(echo ${xray_x25519} | awk '{print $6}')
  jq --arg privateKey "${PRIVATE_KEY}" '.privateKey = $privateKey' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  jq --arg publicKey "${PUBLIC_KEY}" '.publicKey = $publicKey' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
}

function generate_short_id() {
  local input=$1
  local trimmed_input=$(echo "$input" | xargs)
  if [[ $trimmed_input =~ ^[0-8]$ ]]; then
    echo "$(openssl rand -hex ${trimmed_input})"
  elif validate_hex_input "$trimmed_input"; then
    echo "$trimmed_input"
  else
    _error "'$trimmed_input' недопустимый ввод."
  fi
}

function generate_short_ids() {
  IFS=',' read -r -a inputs <<<"$1"
  result=()
  if [[ -z "$inputs" ]]; then
    inputs=(4 8)
  fi
  for input in "${inputs[@]}"; do
    short_id=$(generate_short_id "$input")
    result+=("$short_id")
  done
  local short_ids=$(printf '%s\n' "${result[@]}" | jq -R . | jq -s .)
  echo "${short_ids}"
}

function generate_path() {
  local input="${1}"
  if [[ -z "${input}" ]]; then
    local package_name=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
    local service_name=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
    local method_name=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
    echo "/${package_name}.${service_name}.${method_name}"
  else
    echo "/${input#/}"
  fi
}

function get_xray_config_data() {
  # Проверка необходимости сброса конфигурации
  if [[ "${STATUS}" -ne 1 ]]; then
    read_block_bt
    read_block_cn_ip
    read_block_ads
    read_update_geodata
  fi

  # Проверка предыдущей конфигурации sni
  local nginx_status=$(jq -r '.sni.status' /usr/local/xray-script/config.json)
  if [[ ${nginx_status} -eq 1 && 'sni' != ${XTLS_CONFIG} ]]; then
    stop_renew_ssl
    if _exists "docker"; then
      bash /usr/local/xray-script/docker.sh --purge-cloudreve
    fi
    _systemctl stop nginx
    jq '.sni.status = 0' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    jq '.sni.domain = ""' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    jq '.sni.cdn = ""' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  fi

  # Настройка порта
  if [[ 'sni' == ${XTLS_CONFIG} ]]; then
    _info 'Порт для конфигурации SNI нельзя изменить, по умолчанию 443'
    XRAY_PORT=443
  else
    read_port
    XRAY_PORT=$(generate_port "${in_port}")
  fi
  _info "port: ${XRAY_PORT}"

  # Настройки домена
  case ${XTLS_CONFIG} in
  xhttp | vision | trojan | fallback)
    read_domain
    TARGET_DOMAIN="$(generate_target "${in_domain}")"
    _info "target: ${TARGET_DOMAIN}"
    SERVER_NAMES="$(generate_server_names "${TARGET_DOMAIN}")"
    _info "server names: ${SERVER_NAMES}"
    ;;
  sni)
    [[ -e "${HOME}/.acme.sh/acme.sh" ]] || read_zero_ssl_account_email
    read_sni_cdn_domain
    jq --arg target "${reality_domain}" '.target = $target' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    _info "target: ${reality_domain}"
    _info "cdn: ${cdn_domain}"
    SERVER_NAMES="$(echo '["'"${reality_domain}"'"]' | jq -r)"
    _info "server names: ${SERVER_NAMES}"
    ;;
  esac

  # Общие настройки для всех конфигураций
  jq --argjson port "${XRAY_PORT}" '.port = $port' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  read_uuid
  XRAY_UUID="$(generate_uuid "${in_uuid}")"
  _info "UUID: ${XRAY_UUID}"
  jq --arg uuid "${XRAY_UUID}" '.uuid = $uuid' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json

  # Настройки шифрования в зависимости от конфигурации
  case ${XTLS_CONFIG} in
  mkcp)
    read_seed
    KCP_SEED="$(generate_password "${in_seed}")"
    _info "seed: ${KCP_SEED}"
    jq --arg seed "${KCP_SEED}" '.kcp = $seed' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    ;;
  trojan)
    read_password
    TROJAN_PASSWORD="$(generate_password "${in_password}")"
    _info "password: ${TROJAN_PASSWORD}"
    jq --arg trojan "${TROJAN_PASSWORD}" '.trojan = $trojan' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    ;;
  fallback)
    _info "Настройка fallback UUID"
    read_uuid
    FALLBACK_UUID="$(generate_uuid "${in_uuid}")"
    _info "fallback UUID: ${FALLBACK_UUID}"
    jq --arg uuid "${FALLBACK_UUID}" '.fallback = $uuid' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    ;;
  sni)
    _info "Настройка sni UUID"
    read_uuid
    SNI_UUID="$(generate_uuid "${in_uuid}")"
    _info "sni UUID: ${SNI_UUID}"
    jq --arg uuid "${SNI_UUID}" '.sni.uuid = $uuid' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    ;;
  esac

  # Настройка path для XHTTP
  case ${XTLS_CONFIG} in
  xhttp | trojan | fallback | sni)
    read_path
    XHTTP_PATH="$(generate_path "${in_path}")"
    _info "path: ${XHTTP_PATH}"
    jq --arg path "${XHTTP_PATH}" '.path = $path' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    ;;
  esac

  # Настройки REALITY
  case ${XTLS_CONFIG} in
  xhttp | vision | trojan | fallback | sni)
    generate_xray_x25519
    read_short_ids
    SHORT_IDS="$(generate_short_ids "${in_short_id}")"
    _info "shortIds: ${SHORT_IDS}"
    _info "private key: ${PRIVATE_KEY}"
    _info "public key: ${PUBLIC_KEY}"
    jq --argjson shortIds "${SHORT_IDS}" '.shortIds = $shortIds' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    ;;
  esac
}

function get_xtls_download_url() {
  local url="https://api.github.com/repos/lyekka/Xray-script/contents/XTLS"
  DOWNLOAD_URL=$(curl -fsSL "$url" | jq -r --arg target "${XTLS_CONFIG}" '.[] | select((.name | ascii_downcase | sub("\\.json$"; "")) == $target) | .download_url')
}

function set_mkcp_data() {
  jq --argjson port "${XRAY_PORT}" '.inbounds[1].port = $port' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg uuid "${XRAY_UUID}" '.inbounds[1].settings.clients[0].id = $uuid' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg seed "${KCP_SEED}" '.inbounds[1].streamSettings.kcpSettings.seed = $seed' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
}

function get_mkcp_data() {
  # -- протокол --
  local protocol=$(jq -r '.inbounds[1].protocol' /usr/local/etc/xray/config.json)
  # -- UUID --
  local uuid=$(jq -r '.inbounds[1].settings.clients[0].id' /usr/local/etc/xray/config.json)
  # -- удаленный хост --
  local remote_host=$(curl -fsSL ipv4.icanhazip.com)
  # -- порт --
  local port=$(jq -r '.inbounds[1].port' /usr/local/etc/xray/config.json)
  # -- тип --
  local type=$(jq -r '.inbounds[1].streamSettings.network' /usr/local/etc/xray/config.json)
  # -- сид --
  local seed=$(jq -r '.inbounds[1].streamSettings.kcpSettings.seed' /usr/local/etc/xray/config.json)
  # -- тег --
  local tag=$(jq -r '.tag' /usr/local/xray-script/config.json)
  # -- ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ --
  SHARE_LINK="${protocol}://${uuid}@${remote_host}:${port}?type=${type}&seed=${seed}#${tag}"
}

function set_vision_data() {
  jq --argjson port "${XRAY_PORT}" '.inbounds[1].port = $port' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg uuid "${XRAY_UUID}" '.inbounds[1].settings.clients[0].id = $uuid' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg target "${TARGET_DOMAIN}" '.inbounds[1].streamSettings.realitySettings.target = $target' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson serverNames "${SERVER_NAMES}" '.inbounds[1].streamSettings.realitySettings.serverNames = $serverNames' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg privateKey "${PRIVATE_KEY}" '.inbounds[1].streamSettings.realitySettings.privateKey = $privateKey' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson shortIds "${SHORT_IDS}" '.inbounds[1].streamSettings.realitySettings.shortIds = $shortIds' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
}

function get_vision_data() {
  # -- протокол --
  local protocol=$(jq -r '.inbounds[1].protocol' /usr/local/etc/xray/config.json)
  # -- UUID --
  local uuid=$(jq -r '.inbounds[1].settings.clients[0].id' /usr/local/etc/xray/config.json)
  # -- удаленный хост --
  local remote_host=$(curl -fsSL ipv4.icanhazip.com)
  # -- порт --
  local port=$(jq -r '.inbounds[1].port' /usr/local/etc/xray/config.json)
  # -- тип --
  local type=$(jq -r '.inbounds[1].streamSettings.network' /usr/local/etc/xray/config.json)
  # -- поток --
  local flow=$(jq -r '.inbounds[1].settings.clients[0].flow' /usr/local/etc/xray/config.json)
  # -- безопасность --
  local security=$(jq -r '.inbounds[1].streamSettings.security' /usr/local/etc/xray/config.json)
  # -- имя сервера --
  local server_names_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames | length' /usr/local/etc/xray/config.json)
  local server_names_random=$(get_random_number 0 ${server_names_length})
  local server_name=$(jq '.inbounds[1].streamSettings.realitySettings.serverNames | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${server_names_random} '.[$i]')
  # -- публичный ключ --
  local public_key=$(jq -r '.publicKey' /usr/local/xray-script/config.json)
  # -- короткий ID --
  local short_ids_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds | length' /usr/local/etc/xray/config.json)
  local short_ids_random=$(get_random_number 0 ${short_ids_length})
  local short_id=$(jq '.inbounds[1].streamSettings.realitySettings.shortIds | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${short_ids_random} '.[$i]')
  # -- тег --
  local tag=$(jq -r '.tag' /usr/local/xray-script/config.json)
  # -- ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ --
  SHARE_LINK="${protocol}://${uuid}@${remote_host}:${port}?type=${type}&flow=${flow}&security=${security}&sni=${server_name}&pbk=${public_key}&sid=${short_id}&spx=%2F&fp=chrome#${tag}"
}

function set_xhttp_data() {
  jq --argjson port "${XRAY_PORT}" '.inbounds[1].port = $port' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg uuid "${XRAY_UUID}" '.inbounds[1].settings.clients[0].id = $uuid' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg target "${TARGET_DOMAIN}" '.inbounds[1].streamSettings.realitySettings.target = $target' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson serverNames "${SERVER_NAMES}" '.inbounds[1].streamSettings.realitySettings.serverNames = $serverNames' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg privateKey "${PRIVATE_KEY}" '.inbounds[1].streamSettings.realitySettings.privateKey = $privateKey' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson shortIds "${SHORT_IDS}" '.inbounds[1].streamSettings.realitySettings.shortIds = $shortIds' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg path "${XHTTP_PATH}" '.inbounds[1].streamSettings.xhttpSettings.path = $path' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
}

function get_xhttp_data() {
  # -- протокол --
  local protocol=$(jq -r '.inbounds[1].protocol' /usr/local/etc/xray/config.json)
  # -- UUID --
  local uuid=$(jq -r '.inbounds[1].settings.clients[0].id' /usr/local/etc/xray/config.json)
  # -- удаленный хост --
  local remote_host=$(curl -fsSL ipv4.icanhazip.com)
  # -- порт --
  local port=$(jq -r '.inbounds[1].port' /usr/local/etc/xray/config.json)
  # -- тип --
  local type=$(jq -r '.inbounds[1].streamSettings.network' /usr/local/etc/xray/config.json)
  # -- безопасность --
  local security=$(jq -r '.inbounds[1].streamSettings.security' /usr/local/etc/xray/config.json)
  # -- имя сервера --
  local server_names_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames | length' /usr/local/etc/xray/config.json)
  local server_names_random=$(get_random_number 0 ${server_names_length})
  local server_name=$(jq '.inbounds[1].streamSettings.realitySettings.serverNames | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${server_names_random} '.[$i]')
  # -- публичный ключ --
  local public_key=$(jq -r '.publicKey' /usr/local/xray-script/config.json)
  # -- короткий ID --
  local short_ids_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds | length' /usr/local/etc/xray/config.json)
  local short_ids_random=$(get_random_number 0 ${short_ids_length})
  local short_id=$(jq '.inbounds[1].streamSettings.realitySettings.shortIds | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${short_ids_random} '.[$i]')
  # -- путь --
  local path=$(jq -r '.inbounds[1].streamSettings.xhttpSettings.path' /usr/local/etc/xray/config.json)
  # -- тег --
  local tag=$(jq -r '.tag' /usr/local/xray-script/config.json)
  # -- ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ --
  SHARE_LINK="${protocol}://${uuid}@${remote_host}:${port}?type=${type}&security=${security}&sni=${server_name}&pbk=${public_key}&sid=${short_id}&path=%2F${path#/}&spx=%2F&fp=chrome#${tag}"
}

function set_trojan_data() {
  jq --argjson port "${XRAY_PORT}" '.inbounds[1].port = $port' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg password "${TROJAN_PASSWORD}" '.inbounds[1].settings.clients[0].password = $password' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg target "${TARGET_DOMAIN}" '.inbounds[1].streamSettings.realitySettings.target = $target' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson serverNames "${SERVER_NAMES}" '.inbounds[1].streamSettings.realitySettings.serverNames = $serverNames' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg privateKey "${PRIVATE_KEY}" '.inbounds[1].streamSettings.realitySettings.privateKey = $privateKey' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson shortIds "${SHORT_IDS}" '.inbounds[1].streamSettings.realitySettings.shortIds = $shortIds' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg path "${XHTTP_PATH}" '.inbounds[1].streamSettings.xhttpSettings.path = $path' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
}

function get_trojan_data() {
  # -- протокол --
  local protocol=$(jq -r '.inbounds[1].protocol' /usr/local/etc/xray/config.json)
  # -- пароль --
  local password=$(jq -r '.inbounds[1].settings.clients[0].password' /usr/local/etc/xray/config.json)
  # -- удаленный хост --
  local remote_host=$(curl -fsSL ipv4.icanhazip.com)
  # -- порт --
  local port=$(jq -r '.inbounds[1].port' /usr/local/etc/xray/config.json)
  # -- тип --
  local type=$(jq -r '.inbounds[1].streamSettings.network' /usr/local/etc/xray/config.json)
  # -- безопасность --
  local security=$(jq -r '.inbounds[1].streamSettings.security' /usr/local/etc/xray/config.json)
  # -- имя сервера --
  local server_names_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames | length' /usr/local/etc/xray/config.json)
  local server_names_random=$(get_random_number 0 ${server_names_length})
  local server_name=$(jq '.inbounds[1].streamSettings.realitySettings.serverNames | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${server_names_random} '.[$i]')
  # -- публичный ключ --
  local public_key=$(jq -r '.publicKey' /usr/local/xray-script/config.json)
  # -- короткий ID --
  local short_ids_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds | length' /usr/local/etc/xray/config.json)
  local short_ids_random=$(get_random_number 0 ${short_ids_length})
  local short_id=$(jq '.inbounds[1].streamSettings.realitySettings.shortIds | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${short_ids_random} '.[$i]')
  # -- путь --
  local path=$(jq -r '.inbounds[1].streamSettings.xhttpSettings.path' /usr/local/etc/xray/config.json)
  # -- тег --
  local tag=$(jq -r '.tag' /usr/local/xray-script/config.json)
  # -- ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ --
  SHARE_LINK="${protocol}://${password}@${remote_host}:${port}?type=${type}&security=${security}&sni=${server_name}&pbk=${public_key}&sid=${short_id}&path=%2F${path#/}&spx=%2F&fp=chrome#${tag}"
}

function set_fallback_data() {
  jq --argjson port "${XRAY_PORT}" '.inbounds[1].port = $port' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg uuid "${XRAY_UUID}" '.inbounds[1].settings.clients[0].id = $uuid' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg target "${TARGET_DOMAIN}" '.inbounds[1].streamSettings.realitySettings.target = $target' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson serverNames "${SERVER_NAMES}" '.inbounds[1].streamSettings.realitySettings.serverNames = $serverNames' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg privateKey "${PRIVATE_KEY}" '.inbounds[1].streamSettings.realitySettings.privateKey = $privateKey' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson shortIds "${SHORT_IDS}" '.inbounds[1].streamSettings.realitySettings.shortIds = $shortIds' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg uuid "${FALLBACK_UUID}" '.inbounds[2].settings.clients[0].id = $uuid' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg path "${XHTTP_PATH}" '.inbounds[2].streamSettings.xhttpSettings.path = $path' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
}

function get_fallback_xhttp_data() {
  # -- протокол --
  local protocol=$(jq -r '.inbounds[2].protocol' /usr/local/etc/xray/config.json)
  # -- UUID --
  local uuid=$(jq -r '.inbounds[2].settings.clients[0].id' /usr/local/etc/xray/config.json)
  # -- удаленный хост --
  local remote_host=$(curl -fsSL ipv4.icanhazip.com)
  # -- порт --
  local port=$(jq -r '.inbounds[1].port' /usr/local/etc/xray/config.json)
  # -- тип --
  local type=$(jq -r '.inbounds[2].streamSettings.network' /usr/local/etc/xray/config.json)
  # -- безопасность --
  local security=$(jq -r '.inbounds[1].streamSettings.security' /usr/local/etc/xray/config.json)
  # -- имя сервера --
  local server_names_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames | length' /usr/local/etc/xray/config.json)
  local server_names_random=$(get_random_number 0 ${server_names_length})
  local server_name=$(jq '.inbounds[1].streamSettings.realitySettings.serverNames | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${server_names_random} '.[$i]')
  # -- публичный ключ --
  local public_key=$(jq -r '.publicKey' /usr/local/xray-script/config.json)
  # -- короткий ID --
  local short_ids_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds | length' /usr/local/etc/xray/config.json)
  local short_ids_random=$(get_random_number 0 ${short_ids_length})
  local short_id=$(jq '.inbounds[1].streamSettings.realitySettings.shortIds | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${short_ids_random} '.[$i]')
  # -- путь --
  local path=$(jq -r '.inbounds[2].streamSettings.xhttpSettings.path' /usr/local/etc/xray/config.json)
  # -- тег --
  local tag='fallback_xhttp'
  # -- ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ --
  SHARE_LINK="${protocol}://${uuid}@${remote_host}:${port}?type=${type}&security=${security}&sni=${server_name}&pbk=${public_key}&sid=${short_id}&path=%2F${path#/}&spx=%2F&fp=chrome#${tag}"
}

function set_sni_data() {
  jq --arg uuid "${XRAY_UUID}" '.inbounds[1].settings.clients[0].id = $uuid' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson serverNames "${SERVER_NAMES}" '.inbounds[1].streamSettings.realitySettings.serverNames = $serverNames' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg privateKey "${PRIVATE_KEY}" '.inbounds[1].streamSettings.realitySettings.privateKey = $privateKey' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson shortIds "${SHORT_IDS}" '.inbounds[1].streamSettings.realitySettings.shortIds = $shortIds' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg uuid "${SNI_UUID}" '.inbounds[2].settings.clients[0].id = $uuid' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg path "${XHTTP_PATH}" '.inbounds[2].streamSettings.xhttpSettings.path = $path' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
}

function get_sni_data() {
  local sni_type="$1"
  local sni_security="$2"
  local extra="$3"
  # -- протокол --
  local protocol=$(jq -r '.inbounds[1].protocol' /usr/local/etc/xray/config.json)
  # -- UUID --
  local uuid=$(jq -r '.inbounds[1].settings.clients[0].id' /usr/local/etc/xray/config.json)
  [[ 'xhttp' == "${sni_type}" ]] && uuid=$(jq -r '.inbounds[2].settings.clients[0].id' /usr/local/etc/xray/config.json)
  # -- удаленный хост --
  local remote_host=$(curl -fsSL ipv4.icanhazip.com)
  # -- порт --
  local port=$(jq -r '.port' /usr/local/xray-script/config.json)
  # -- тип --
  local type=$(jq -r '.inbounds[1].streamSettings.network' /usr/local/etc/xray/config.json)
  [[ 'xhttp' == "${sni_type}" ]] && type=$(jq -r '.inbounds[2].streamSettings.network' /usr/local/etc/xray/config.json)
  # -- поток --
  local flow=$(jq -r '.inbounds[1].settings.clients[0].flow' /usr/local/etc/xray/config.json)
  # -- безопасность --
  local security=$(jq -r '.inbounds[1].streamSettings.security' /usr/local/etc/xray/config.json)
  [[ 'cdn' == "${sni_security}" ]] && security='tls'
  # -- имя сервера --
  local server_names_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames | length' /usr/local/etc/xray/config.json)
  local server_names_random=$(get_random_number 0 ${server_names_length})
  local server_name=$(jq '.inbounds[1].streamSettings.realitySettings.serverNames | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${server_names_random} '.[$i]')
  [[ 'cdn' == "${sni_security}" ]] && server_name=$(jq -r '.sni.cdn' /usr/local/xray-script/config.json)
  # -- публичный ключ --
  local public_key=$(jq -r '.publicKey' /usr/local/xray-script/config.json)
  # -- короткий ID --
  local short_ids_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds | length' /usr/local/etc/xray/config.json)
  local short_ids_random=$(get_random_number 0 ${short_ids_length})
  local short_id=$(jq '.inbounds[1].streamSettings.realitySettings.shortIds | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${short_ids_random} '.[$i]')
  # -- путь --
  local path=$(jq -r '.inbounds[2].streamSettings.xhttpSettings.path' /usr/local/etc/xray/config.json)
  # -- тег --
  local tag='vision_reality'
  [[ 'xhttp' == "${sni_type}" ]] && tag='xhttp_reality'
  [[ 'cdn' == "${sni_security}" ]] && tag='xhttp_cdn'
  # -- ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ --
  SHARE_LINK="${protocol}://${uuid}@${remote_host}:${port}?type=${type}&flow=${flow}&security=${security}&sni=${server_name}&pbk=${public_key}&sid=${short_id}&spx=%2F&fp=chrome#${tag}"
  [[ 'xhttp' == "${sni_type}" ]] && SHARE_LINK="${protocol}://${uuid}@${remote_host}:${port}?type=${type}&security=${security}&sni=${server_name}&pbk=${public_key}&sid=${short_id}&path=%2F${path#/}&spx=%2F&fp=chrome#${tag}"
  [[ 'cdn' == "${sni_security}" ]] && SHARE_LINK="${protocol}://${uuid}@${remote_host}:${port}?type=${type}&security=${security}&sni=${server_name}&host=${server_name}&alpn=h2&pbk=${public_key}&path=%2F${path#/}&spx=%2F&fp=chrome#${tag}"
  if [[ 'extra' == "${extra}" ]]; then
    extra_encoded=$(get_sni_extra_encoded ${path} ${sni_security})
    SHARE_LINK="${protocol}://${uuid}@${remote_host}:${port}?type=${type}&security=${security}&sni=${server_name}&pbk=${public_key}&sid=${short_id}&path=%2F${path#/}&spx=%2F&fp=chrome&extra=${extra_encoded}#reality_up_cdn_down"
    [[ 'cdn' == "${sni_security}" ]] && SHARE_LINK="${protocol}://${uuid}@${remote_host}:${port}?type=${type}&security=${security}&sni=${server_name}&host=${server_name}&alpn=h2&pbk=${public_key}&path=%2F${path#/}&spx=%2F&fp=chrome&extra=${extra_encoded}#cdn_up_reality_down"
  fi
}

function get_sni_extra_encoded() {
  local sni_path="$1"
  local sni_security="$2"
  local server_name=$(jq -r '.sni.cdn' /usr/local/xray-script/config.json)
  local encoded=$(
    cat <<EOF | urlencode
{
    "downloadSettings": {
        "address": "${server_name}",
        "port": 443,
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
            "serverName": "${server_name}",
            "allowInsecure": false,
            "alpn": [
                "h2"
            ],
            "fingerprint": "chrome"
        },
        "xhttpSettings": {
            "host": "${server_name}",
            "path": "${sni_path}",
            "mode": "auto"
        }
    }
}
EOF
  )
  if [[ 'cdn' == "${sni_security}" ]]; then
    server_name=$(jq -r '.sni.domain' /usr/local/xray-script/config.json)
    # -- публичный ключ --
    local public_key=$(jq -r '.publicKey' /usr/local/xray-script/config.json)
    # -- короткий ID --
    local short_ids_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds | length' /usr/local/etc/xray/config.json)
    local short_ids_random=$(get_random_number 0 ${short_ids_length})
    local short_id=$(jq '.inbounds[1].streamSettings.realitySettings.shortIds | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${short_ids_random} '.[$i]')
    encoded=$(
      cat <<EOF | urlencode
{
    "downloadSettings": {
        "address": "${server_name}",
        "port": 443,
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
            "show": false,
            "serverName": "${server_name}",
            "fingerprint": "chrome",
            "publicKey": "${public_key}",
            "shortId": "${short_id}",
            "spiderX": "/"
        },
        "xhttpSettings": {
            "host": "",
            "path": "${sni_path}",
            "mode": "auto"
        }
    }
}
EOF
    )
  fi
  echo "$encoded"
}

function set_routing_and_outbounds() {
  if [[ "${STATUS}" -eq 1 ]]; then
    local routing=$(jq -r '.' /usr/local/xray-script/routing.json)
    jq --argjson routing "${routing}" '.routing = $routing' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  else
    jq --argjson status 1 '.status = $status' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  fi
  if [[ "${WARP}" -eq 1 ]]; then
    local outbounds='[{"tag":"warp","protocol":"socks","settings":{"servers":[{"address":"172.17.0.2","port":40001}]}}]'
    jq --argjson outbounds $outbounds '.outbounds += $outbounds' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  fi
}

function setup_xray_config_data() {
  get_xtls_download_url
  wget --no-check-certificate -O /usr/local/xray-script/xtls.json ${DOWNLOAD_URL}
  case ${XTLS_CONFIG} in
  mkcp) set_mkcp_data ;;
  vision) set_vision_data ;;
  xhttp) set_xhttp_data ;;
  trojan) set_trojan_data ;;
  fallback) set_fallback_data ;;
  sni) set_sni_data ;;
  esac
  set_routing_and_outbounds
  mv -f /usr/local/xray-script/xtls.json /usr/local/etc/xray/config.json
  add_rule_block_bt
  add_rule_block_cn_ip
  add_rule_block_ads
  add_update_geodata
  [[ 'sni' == ${XTLS_CONFIG} ]] && {
    bash /usr/local/xray-script/ssl.sh --install --email "${account_email:-my@example.com}"
    if [[ 'cloudreve' == ${SNI_CONFIG} ]]; then
      bash /usr/local/xray-script/docker.sh --install-cloudreve
    fi
    setup_nginx
    setup_nginx_config_data
    setup_ssl
    show_cloudreve_data
    _systemctl restart nginx
  }
  restart_xray
}

function setup_nginx() {
  local nginx_status=$(jq -r '.sni.nginx' /usr/local/xray-script/config.json)
  [[ ${nginx_status} -ne 1 ]] && {
    bash /usr/local/xray-script/nginx.sh -i -b
    jq '.sni.nginx = 1' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  }
}

function setup_nginx_config_data() {
  [[ -f /usr/local/nginx/conf/nginxconfig.txt ]] || {
    mkdir -vp /usr/local/nginx/conf/nginxconfig.io
    mkdir -vp /usr/local/nginx/conf/modules-enabled
    mkdir -vp /usr/local/nginx/conf/sites-available
    mkdir -vp /usr/local/nginx/conf/sites-enabled
    mkdir -vp /var/log/nginx
    download_github_files '/usr/local/nginx/conf' 'https://api.github.com/repos/lyekka/Xray-script/contents/nginx/conf'
    rm -rf /usr/local/nginx/conf/limit.conf
  }
}

function stop_renew_ssl() {
  # Остановка обновления SSL сертификатов для старых доменов
  local old_domain=$(jq -r '.sni.old.domain' /usr/local/xray-script/config.json)
  local old_cdn=$(jq -r '.sni.old.cdn' /usr/local/xray-script/config.json)

  # Остановка продления старого REALITY-домена и очистка конфигурации
  if [[ -n "${old_domain}" ]]; then
    _info "Обработка старого REALITY домена: ${old_domain}"

    if [[ -d "/usr/local/nginx/conf/certs/${old_domain}" ]]; then
      _warn "Остановка обновления SSL сертификата для ${old_domain}..."
      if bash /usr/local/xray-script/ssl.sh -s -d "${old_domain}"; then
        _info "Обновление SSL сертификата успешно остановлено."
      else
        _error "Не удалось остановить обновление SSL сертификата."
      fi
      rm -rf /usr/local/nginx/conf/sites-{available,enabled}/${old_domain}.conf
      jq '.sni.old.domain = ""' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    fi
  fi

  # Остановка продления старого CDN-домена и очистка конфигурации
  if [[ -n "${old_cdn}" && "${old_cdn}" != "${old_domain}" ]]; then
    _info "Обработка старого CDN домена: ${old_cdn}"

    if [[ -d "/usr/local/nginx/conf/certs/${old_cdn}" ]]; then
      _warn "Остановка обновления SSL сертификата для ${old_cdn}..."
      if bash /usr/local/xray-script/ssl.sh -s -d "${old_cdn}"; then
        _info "Обновление SSL сертификата успешно остановлено."
      else
        _error "Не удалось остановить обновление SSL сертификата."
      fi
      rm -rf /usr/local/nginx/conf/sites-{available,enabled}/${old_cdn}.conf
      jq '.sni.old.cdn = ""' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    fi
  elif [[ "${old_cdn}" == "${old_domain}" ]]; then
    jq '.sni.old.cdn = ""' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  fi
}

function setup_ssl() {
  stop_renew_ssl
  # Настройка конфига nginx для нового домена
  wget --no-check-certificate -O /usr/local/nginx/conf/modules-enabled/stream.conf https://raw.githubusercontent.com/lyekka/Xray-script/main/nginx/conf/modules-enabled/stream.conf
  sed -i "s| example.com| ${reality_domain}|g" /usr/local/nginx/conf/modules-enabled/stream.conf
  sed -i "s|# cdn.example.com|# ${cdn_domain}|g" /usr/local/nginx/conf/modules-enabled/stream.conf

  wget --no-check-certificate -O /usr/local/nginx/conf/sites-available/${reality_domain}.conf https://raw.githubusercontent.com/lyekka/Xray-script/main/nginx/conf/sites-available/example.com.conf
  sed -i "s|example.com|${reality_domain}|g" /usr/local/nginx/conf/sites-available/${reality_domain}.conf
  sed -i "s|/yourpath|${XHTTP_PATH}|g" /usr/local/nginx/conf/sites-available/${reality_domain}.conf

  [[ ${reality_domain} == ${cdn_domain} ]] || {
    wget --no-check-certificate -O /usr/local/nginx/conf/sites-available/${cdn_domain}.conf https://raw.githubusercontent.com/lyekka/Xray-script/main/nginx/conf/sites-available/example.com.conf
    sed -i '/# h3/,/# h2/{/# h2/!d;}' /usr/local/nginx/conf/sites-available/${cdn_domain}.conf
    sed -i 's|cloudreve.sock|cdn_xhttp.sock|' /usr/local/nginx/conf/sites-available/${cdn_domain}.conf
    sed -i "s|example.com|${cdn_domain}|g" /usr/local/nginx/conf/sites-available/${cdn_domain}.conf
    sed -i 's|# ||g' /usr/local/nginx/conf/modules-enabled/stream.conf
    sed -i "s|/yourpath|${XHTTP_PATH}|g" /usr/local/nginx/conf/sites-available/${cdn_domain}.conf
  }

  [[ 'cloudreve' == ${SNI_CONFIG} ]] || {
    sed -i '/^[[:space:]]*location \/[[:space:]]*{/,/^[[:space:]]*#[[:space:]]*add/ { s/^/#/; }' /usr/local/nginx/conf/sites-available/${reality_domain}.conf
    sed -i '/^[[:space:]]*location \/[[:space:]]*{/,/^[[:space:]]*#[[:space:]]*add/ { s/^/#/; }' /usr/local/nginx/conf/sites-available/${cdn_domain}.conf
  }

  # Запрос SSL-сертификата для нового домена
  bash /usr/local/xray-script/ssl.sh -i -d ${reality_domain} || _error 'Прерывание установки'
  [[ ${reality_domain} == ${cdn_domain} ]] || {
    bash /usr/local/xray-script/ssl.sh -i -d ${cdn_domain} || _error 'Прерывание установки'
    ln -sf /usr/local/nginx/conf/sites-available/${cdn_domain}.conf /usr/local/nginx/conf/sites-enabled/${cdn_domain}.conf
  }
  ln -sf /usr/local/nginx/conf/sites-available/${reality_domain}.conf /usr/local/nginx/conf/sites-enabled/${reality_domain}.conf

  _info "SSL-сертификат успешно получен, перезапуск Nginx"
  _systemctl restart nginx

  # Обновление информации sni.old в конфиге
  jq --arg target "${reality_domain}" '.sni.old.domain = $target' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  jq --arg target "${cdn_domain}" '.sni.old.cdn = $target' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  # Обновление информации sni в конфиге
  jq --arg target "${reality_domain}" '.sni.domain = $target' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  jq --arg target "${cdn_domain}" '.sni.cdn = $target' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  jq '.sni.status = 1' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
}

function setup_xray_config() {
  get_xray_config_data
  setup_xray_config_data
}

function install_xray() {
  _error_detect 'bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root ${INSTALL_OPTION}'
}

function purge_xray() {
  rm -rf /usr/local/xray-script
  _error_detect 'bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge'
}

function start_xray() {
  _systemctl start xray
}

function stop_xray() {
  _systemctl stop xray
}

function restart_xray() {
  _systemctl restart xray
}

function view_xray_config() {
  local remote_host=$(curl -fsSL ipv4.icanhazip.com)
  local port=$(jq -r '.port' /usr/local/xray-script/config.json)
  _warn 'Убедитесь, что порт открыт'
  _info "Ссылка для проверки открытого порта: https://tcp.ping.pe/${remote_host}:${port}"
  _info "На основе существующего конфига автоматически генерируются ссылки для обмена и QR-коды с рандомными serverName и shortId"
  _info "Ссылки основаны на 【Предложении по стандарту VMessAEAD/VLESS】 и 【v2rayN/NG обмене серверами】. Если другие клиенты не работают, измените параметры вручную."
  _info "QR-коды для разделения uplink/downlink слишком большие и не отображаются."
  echo
  echo 'Нажмите любую клавишу для продолжения... или Ctrl+C для отмены'
  local char=$(get_char)
  echo
  XTLS_CONFIG=$(jq -r '.tag' /usr/local/xray-script/config.json)
  case ${XTLS_CONFIG} in
  mkcp) get_mkcp_data ;;
  vision) get_vision_data ;;
  xhttp) get_xhttp_data ;;
  trojan) get_trojan_data ;;
  fallback)
    # vision
    get_vision_data
    _info "XTLS(Vision)+Reality прямое подключение"
    _info "Ссылка для обмена: ${SHARE_LINK}"
    echo ${SHARE_LINK} | qrencode -t ansiutf8
    echo
    # xhttp
    get_fallback_xhttp_data
    _info "xhttp+Reality прямое подключение"
    ;;
  sni)
    # vision
    get_sni_data
    _info "XTLS(Vision)+Reality прямое подключение"
    _info "Ссылка для обмена: ${SHARE_LINK}"
    echo ${SHARE_LINK} | qrencode -t ansiutf8
    echo
    # xhttp
    get_sni_data 'xhttp'
    _info "xhttp+Reality прямое подключение"
    _info "Ссылка для обмена: ${SHARE_LINK}"
    echo ${SHARE_LINK} | qrencode -t ansiutf8
    echo
    # reality up cdn down
    get_sni_data 'xhttp' 'reality' 'extra'
    _info "Uplink xhttp+Reality | Downlink xhttp+TLS+CDN"
    _info "Ссылка для обмена: ${SHARE_LINK}"
    echo
    # cdn up reality down
    get_sni_data 'xhttp' 'cdn' 'extra'
    _info "Uplink xhttp+TLS+CDN | Downlink xhttp+Reality"
    _info "Ссылка для обмена: ${SHARE_LINK}"
    echo
    # cdn
    get_sni_data 'xhttp' 'cdn'
    _info "xhttp+TLS через CDN"
    ;;
  esac
  _info "Ссылка для обмена: ${SHARE_LINK}"
  echo ${SHARE_LINK} | qrencode -t ansiutf8
  echo
}

function view_xray_traffic() {
  [[ -f /usr/local/xray-script/traffic.sh ]] || wget --no-check-certificate -O /usr/local/xray-script/traffic.sh https://raw.githubusercontent.com/lyekka/Xray-script/main/tool/traffic.sh
  bash /usr/local/xray-script/traffic.sh
}

# Процесс установки
function installation_processes() {
  _input_tips 'Выберите действие: '
  read -r choose
  case ${choose} in
  2) IS_AUTO='N' ;;
  *) IS_AUTO='Y' ;;
  esac
}

# Управление установкой Xray
function xray_installation_processes() {
  _input_tips 'Выберите действие: '
  read -r choose
  case ${choose} in
  1) INSTALL_OPTION="--version $(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[0].tag_name')" ;;
  3)
    _input_tips 'Введите версию (например v1.0.0): '
    read -r specified_version
    check_xray_version_is_exists "${specified_version}"
    SPECIFIED_VERSION="${specified_version}"
    INSTALL_OPTION="--version v${SPECIFIED_VERSION##*v}"
    ;;
  4)
    local nginx_status=$(jq -r '.sni.status' /usr/local/xray-script/config.json)
    if [[ ${nginx_status} -eq 1 ]]; then
      bash /usr/local/xray-script/nginx.sh -u -b
    fi
    exit 0
    ;;
  *) INSTALL_OPTION='' ;;
  esac
}

# Управление конфигурацией
function config_processes() {
  _input_tips 'Выберите действие: '
  read -r choose
  case ${choose} in
  1)
    UPDATE_CONFIG='Y'
    if [[ "${STATUS}" -eq 1 ]]; then
      _input_tips 'Использовать новую конфигурацию? [y/N] '
      read -r is_new_config
      if [[ ${is_new_config} =~ ^[Yy]$ ]]; then
        STATUS=0
      fi
    fi
    xray_config_management
    ;;
  2) enable_warp ;;
  3) disable_warp ;;
  4) enable_nginx_cron ;;
  5) disable_nginx_cron ;;
  6) enable_cron ;;
  7) disable_cron ;;
  8) add_rule_warp_ip ;;
  9) add_rule_warp_domain ;;
  10) add_rule_block_ip ;;
  11) add_rule_block_domain ;;
  12) change_domain ;;
  13) reset_cloudreve_data ;;
  *) exit ;;
  esac
}

# Настройка SNI
function sni_config_processes() {
  _input_tips 'Выберите действие: '
  read -r choose
  case ${choose} in
  2) SNI_CONFIG='cloudreve' ;;
  esac
}

# Обновление конфигурации Xray
function xray_config_processes() {
  _input_tips 'Выберите действие: '
  read -r choose
  case ${choose} in
  1) XTLS_CONFIG='mkcp' ;;
  2) XTLS_CONFIG='vision' ;;
  4) XTLS_CONFIG='trojan' ;;
  5) XTLS_CONFIG='fallback' ;;
  6)
    XTLS_CONFIG='sni'
    sni_config_management
    ;;
  *) XTLS_CONFIG='xhttp' ;;
  esac
  
  jq --arg tag "${XTLS_CONFIG}" '.tag = $tag' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  
  if [[ "${STATUS}" -eq 1 ]]; then
    rm -rf /usr/local/xray-script/routing.json
    jq -r '.routing' /usr/local/etc/xray/config.json >/usr/local/xray-script/routing.json
  fi
}

# Обработка главного меню
function main_processes() {
  _input_tips 'Выберите действие: '
  read -r choose

  [[ ${choose} -eq 0 ]] && exit 0

  if ! check_dependencies; then
    install_dependencies
  fi

  if ! [[ -d /usr/local/xray-script ]]; then
    mkdir -p /usr/local/xray-script
    wget --no-check-certificate -O /usr/local/xray-script/nginx.sh https://raw.githubusercontent.com/lyekka/Xray-script/main/nginx.sh
    wget --no-check-certificate -O /usr/local/xray-script/ssl.sh https://raw.githubusercontent.com/lyekka/Xray-script/main/ssl.sh
    wget --no-check-certificate -q -O /usr/local/xray-script/docker.sh https://raw.githubusercontent.com/lyekka/Xray-script/main/docker.sh
    wget --no-check-certificate -q -O /usr/local/xray-script/config.json https://raw.githubusercontent.com/lyekka/Xray-script/refs/heads/main/XTLS/config.json
    wget --no-check-certificate -q -O /usr/local/xray-script/serverNames.json https://raw.githubusercontent.com/lyekka/Xray-script/refs/heads/main/XTLS/serverNames.json
  fi
  STATUS=$(jq -r '.status' /usr/local/xray-script/config.json)
  WARP=$(jq -r '.warp' /usr/local/xray-script/config.json)

  case ${choose} in
  1)
    installation_management
    if ! [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
      xray_installation_management
      xray_config_management
    fi
    install_xray
    setup_xray_config
    view_xray_config
    ;;
  2)
    xray_installation_management
    install_xray
    ;;
  3)
    # Остановка регулярных задач
    disable_cron
    disable_nginx_cron
    # Отключение WARP и службы Cloudreve
    disable_warp
    bash /usr/local/xray-script/docker.sh --purge-cloudreve
    # Прекращение обновления сертификатов и удаление acme.sh
    stop_renew_ssl
    bash /usr/local/xray-script/ssl.sh -p
    # Удаление nginx
    bash /usr/local/xray-script/nginx.sh -p
    # Удаление xray
    purge_xray
    ;;
  4) start_xray ;;
  5) stop_xray ;;
  6) restart_xray ;;
  7) view_xray_config ;;
  8) view_xray_traffic ;;
  9)
    config_management
    if [[ ${UPDATE_CONFIG} =~ ^[Yy]$ ]]; then
      setup_xray_config
      view_xray_config
    else
      restart_xray
    fi
    ;;
  *) exit 0 ;;
  esac
}

function print_banner() {
  case $(($(get_random_number 0 100) % 2)) in
  0) echo "IBtbMDsxOzM1Ozk1bV8bWzA7MTszMTs5MW1fG1swbSAgIBtbMDsxOzMyOzkybV9fG1swbSAgG1swOzE7MzQ7OTRtXxtbMG0gICAgG1swOzE7MzE7OTFtXxtbMG0gICAbWzA7MTszMjs5Mm1fG1swOzE7MzY7OTZtX18bWzA7MTszNDs5NG1fXxtbMDsxOzM1Ozk1bV9fG1swbSAgIBtbMDsxOzMzOzkzbV8bWzA7MTszMjs5Mm1fXxtbMDsxOzM2Ozk2bV9fG1swOzE7MzQ7OTRtX18bWzBtICAgG1swOzE7MzE7OTFtX18bWzA7MTszMzs5M218G1swbSAbWzA7MTszMjs5Mm18XxtbMDsxOzM2Ozk2bV8bWzBtICAgG1swOzE7MzU7OTVtX18bWzA7MTszMTs5MW18G1swbSAbWzA7MTszMzs5M218G1swbSAgG1swOzE7MzI7OTJtXxtbMDsxOzM2Ozk2bV8bWzBtIBtbMDsxOzM0Ozk0bVwbWzBtIAogIBtbMDsxOzMyOzkybVwbWzBtIBtbMDsxOzM2Ozk2bVYbWzBtIBtbMDsxOzM0Ozk0bS8bWzBtICAbWzA7MTszNTs5NW18G1swbSAbWzA7MTszMTs5MW18G1swOzE7MzM7OTNtX18bWzA7MTszMjs5Mm18G1swbSAbWzA7MTszNjs5Nm18G1swbSAgICAbWzA7MTszNTs5NW18G1swbSAbWzA7MTszMTs5MW18G1swbSAgICAgICAbWzA7MTszNDs5NG18G1swbSAbWzA7MTszNTs5NW18G1swbSAgICAbWzA7MTszMjs5Mm18G1swbSAbWzA7MTszNjs5Nm18XxtbMDsxOzM0Ozk0bV8pG1swbSAbWzA7MTszNTs5NW18G1swbQogICAbWzA7MTszNjs5Nm0+G1swbSAbWzA7MTszNDs5NG08G1swbSAgIBtbMDsxOzMxOzkxbXwbWzBtICAbWzA7MTszMjs5Mm1fXxtbMG0gIBtbMDsxOzM0Ozk0bXwbWzBtICAgIBtbMDsxOzMxOzkxbXwbWzBtIBtbMDsxOzMzOzkzbXwbWzBtICAgICAgIBtbMDsxOzM1Ozk1bXwbWzBtIBtbMDsxOzMxOzkxbXwbWzBtICAgIBtbMDsxOzM2Ozk2bXwbWzBtICAbWzA7MTszNDs5NG1fG1swOzE7MzU7OTVtX18bWzA7MTszMTs5MW0vG1swbSAKICAbWzA7MTszNDs5NG0vG1swbSAbWzA7MTszNTs5NW0uG1swbSAbWzA7MTszMTs5MW1cG1swbSAgG1swOzE7MzM7OTNtfBtbMG0gG1swOzE7MzI7OTJtfBtbMG0gIBtbMDsxOzM0Ozk0bXwbWzBtIBtbMDsxOzM1Ozk1bXwbWzBtICAgIBtbMDsxOzMzOzkzbXwbWzBtIBtbMDsxOzMyOzkybXwbWzBtICAgICAgIBtbMDsxOzMxOzkxbXwbWzBtIBtbMDsxOzMzOzkzbXwbWzBtICAgIBtbMDsxOzM0Ozk0bXwbWzBtIBtbMDsxOzM1Ozk1bXwbWzBtICAgICAKIBtbMDsxOzM0Ozk0bS8bWzA7MTszNTs5NW1fLxtbMG0gG1swOzE7MzE7OTFtXBtbMDsxOzMzOzkzbV9cG1swbSAbWzA7MTszMjs5Mm18G1swOzE7MzY7OTZtX3wbWzBtICAbWzA7MTszNTs5NW18XxtbMDsxOzMxOzkxbXwbWzBtICAgIBtbMDsxOzMyOzkybXwbWzA7MTszNjs5Nm1ffBtbMG0gICAgICAgG1swOzE7MzM7OTNtfBtbMDsxOzMyOzkybV98G1swbSAgICAbWzA7MTszNTs5NW18XxtbMDsxOzMxOzkxbXwbWzBtICAgICAKCkNvcHlyaWdodCAoQykgenhjdm9zIHwgaHR0cHM6Ly9naXRodWIuY29tL3p4Y3Zvcy9YcmF5LXNjcmlwdAoK" | base64 --decode ;;
  1) echo "IBtbMDsxOzM0Ozk0bV9fG1swbSAgIBtbMDsxOzM0Ozk0bV9fG1swbSAgG1swOzE7MzQ7OTRtXxtbMG0gICAgG1swOzE7MzQ7OTRtXxtbMG0gICAbWzA7MzRtX19fX19fXxtbMG0gICAbWzA7MzRtX19fG1swOzM3bV9fX18bWzBtICAgG1swOzM3bV9fX19fG1swbSAgCiAbWzA7MTszNDs5NG1cG1swbSAbWzA7MTszNDs5NG1cG1swbSAbWzA7MTszNDs5NG0vG1swbSAbWzA7MTszNDs5NG0vG1swbSAbWzA7MzRtfBtbMG0gG1swOzM0bXwbWzBtICAbWzA7MzRtfBtbMG0gG1swOzM0bXwbWzBtIBtbMDszNG18X18bWzBtICAgG1swOzM3bV9ffBtbMG0gG1swOzM3bXxfXxtbMG0gICAbWzA7MzdtX198G1swbSAbWzA7MzdtfBtbMG0gIBtbMDsxOzMwOzkwbV9fG1swbSAbWzA7MTszMDs5MG1cG1swbSAKICAbWzA7MzRtXBtbMG0gG1swOzM0bVYbWzBtIBtbMDszNG0vG1swbSAgG1swOzM0bXwbWzBtIBtbMDszNG18X198G1swbSAbWzA7MzdtfBtbMG0gICAgG1swOzM3bXwbWzBtIBtbMDszN218G1swbSAgICAgICAbWzA7MzdtfBtbMG0gG1swOzE7MzA7OTBtfBtbMG0gICAgG1swOzE7MzA7OTBtfBtbMG0gG1swOzE7MzA7OTBtfF9fKRtbMG0gG1swOzE7MzA7OTBtfBtbMG0KICAgG1swOzM0bT4bWzBtIBtbMDszNG08G1swbSAgIBtbMDszN218G1swbSAgG1swOzM3bV9fG1swbSAgG1swOzM3bXwbWzBtICAgIBtbMDszN218G1swbSAbWzA7MzdtfBtbMG0gICAgICAgG1swOzE7MzA7OTBtfBtbMG0gG1swOzE7MzA7OTBtfBtbMG0gICAgG1swOzE7MzA7OTBtfBtbMG0gIBtbMDsxOzM0Ozk0bV9fXy8bWzBtIAogIBtbMDszN20vG1swbSAbWzA7MzdtLhtbMG0gG1swOzM3bVwbWzBtICAbWzA7MzdtfBtbMG0gG1swOzM3bXwbWzBtICAbWzA7MzdtfBtbMG0gG1swOzE7MzA7OTBtfBtbMG0gICAgG1swOzE7MzA7OTBtfBtbMG0gG1swOzE7MzA7OTBtfBtbMG0gICAgICAgG1swOzE7MzA7OTBtfBtbMG0gG1swOzE7MzQ7OTRtfBtbMG0gICAgG1swOzE7MzQ7OTRtfBtbMG0gG1swOzE7MzQ7OTRtfBtbMG0gICAgIAogG1swOzM3bS9fLxtbMG0gG1swOzM3bVxfXBtbMG0gG1swOzE7MzA7OTBtfF98G1swbSAgG1swOzE7MzA7OTBtfF98G1swbSAgICAbWzA7MTszMDs5MG18X3wbWzBtICAgICAgIBtbMDsxOzM0Ozk0bXxffBtbMG0gICAgG1swOzE7MzQ7OTRtfF8bWzA7MzRtfBtbMG0gICAgIAoKQ29weXJpZ2h0IChDKSB6eGN2b3MgfCBodHRwczovL2dpdGh1Yi5jb20venhjdm9zL1hyYXktc2NyaXB0Cgo=" | base64 --decode ;;
  esac
}

function print_script_status() {
  local xray_version="${RED}Не установлен${NC}"
  local script_xray_config="${RED}Не настроен${NC}"
  local warp_status="${RED}Не запущен${NC}"
  if _exists "xray"; then
    xray_version="${GREEN}v$(xray version | awk '$1=="Xray" {print $2}')${NC}"
    if _exists "jq" && [[ -d /usr/local/xray-script ]]; then
      case $(jq -r '.tag' /usr/local/xray-script/config.json) in
      fallback) script_xray_config='VLESS+Vision+REALITY+XHTTP' ;;
      *) script_xray_config=$(jq -r '.inbounds[1].tag' /usr/local/etc/xray/config.json) ;;
      esac
      script_xray_config="${GREEN}${script_xray_config}${NC}"
    fi
  fi
  if _exists "docker" && docker ps | grep -q xray-script-warp; then
    warp_status="${GREEN}Запущен${NC}"
  fi
  echo -e "-------------------------------------------"
  echo -e "Xray       : ${xray_version}"
  echo -e "CONFIG     : ${script_xray_config}"
  echo -e "WARP Proxy : ${warp_status}"
  echo -e "-------------------------------------------"
  echo
}

function installation_management() {
  clear
  echo -e "----------------- Процесс установки ----------------"
  echo -e "${GREEN}1.${NC} Полностью автоматический (${GREEN}по умолчанию${NC})"
  echo -e "${GREEN}2.${NC} Пользовательский"
  echo -e "-------------------------------------------"
  echo -e "1.Стабильная версия, XHTTP, блокировка bt, cn, рекламы, автообновление geodata"
  echo -e "2.Выбор версии и конфигурации вручную"
  echo -e "-------------------------------------------"
  installation_processes
}

function xray_installation_management() {
  clear
  echo -e "----------------- Управление установкой ----------------"
  echo -e "${GREEN}1.${NC} Последняя версия"
  echo -e "${GREEN}2.${NC} Стабильная версия (${GREEN}по умолчанию${NC})"
  echo -e "${GREEN}3.${NC} Выбор версии вручную"
  echo -e "${GREEN}4.${NC} Обновить nginx"
  echo -e "-------------------------------------------"
  echo -e "1.Последняя версия включает ${YELLOW}pre-release${NC} сборки"
  echo -e "2.Стабильная версия - последняя ${YELLOW}не pre-release${NC} сборка"
  echo -e "3.Ручной выбор версии может вызвать ${RED}проблемы совместимости${NC}"
  echo -e "4.Обновление nginx ${RED}доступно только для SNI конфигурации${NC}"
  echo -e "-------------------------------------------"
  xray_installation_processes
}

function config_management() {
  clear
  echo -e "----------------- Управление конфигурацией ----------------"
  echo -e "${GREEN} 1.${NC} Обновить конфигурацию"
  echo -e "${GREEN} 2.${NC} Включить WARP Proxy"
  echo -e "${GREEN} 3.${NC} Выключить WARP Proxy"
  echo -e "${GREEN} 4.${NC} Включить автообновление nginx"
  echo -e "${GREEN} 5.${NC} Выключить автообновление nginx"
  echo -e "${GREEN} 6.${NC} Включить автообновление geodata"
  echo -e "${GREEN} 7.${NC} Выключить автообновление geodata"
  echo -e "${GREEN} 8.${NC} Добавить маршрутизацию по IP для WARP"
  echo -e "${GREEN} 9.${NC} Добавить маршрутизацию по доменам для WARP"
  echo -e "${GREEN}10.${NC} Добавить блокировку по IP"
  echo -e "${GREEN}11.${NC} Добавить блокировку по доменам"
  echo -e "${GREEN}12.${NC} Изменить доменное имя"
  echo -e "${GREEN}13.${NC} Сбросить данные администратора Cloudreve"
  echo -e "-------------------------------------------"
  echo -e "1.Обновление всей конфигурации. Для частичных изменений редактируйте файлы вручную"
  echo -e "2-3.WARP Proxy развертывается через Docker, при включении Docker будет установлен автоматически"
  echo -e "2-3.Подробнее о WARP Proxy: https://github.com/haoel/haoel.github.io?tab=readme-ov-file#1043-docker-%E4%BB%A3%E7%90%86"
  echo -e "2-3.При каждом включении WARP Proxy создается новый аккаунт, ${RED}частая смена может привести к блокировке IP Cloudflare${NC}"
  echo -e "4-5.Включение/выключение автообновления nginx, ${RED}только для SNI конфигурации${NC}"
  echo -e "6-7.Geodata предоставляется https://github.com/Loyalsoldier/v2ray-rules-dat"
  echo -e "8.(${RED}требуется включенный WARP${NC})Добавляет маршрутизацию IP через WARP в ruleTag warp-ip"
  echo -e "9.(${RED}требуется включенный WARP${NC})Добавляет маршрутизацию доменов через WARP в ruleTag warp-domain"
  echo -e "10.Добавляет блокировку IP в ruleTag block-ip"
  echo -e "11.Добавляет блокировку доменов в ruleTag block-domain"
  echo -e "12.Изменение домена для SNI маршрутизации, ${RED}только для SNI конфигурации${NC}"
  echo -e "13.Сброс базы данных Cloudreve, ${RED}только для SNI конфигурации${NC}"
  echo -e "-------------------------------------------"
  config_processes
}

function sni_config_management() {
  clear
  echo -e "----------------- Настройка SNI ----------------"
  echo -e "${GREEN}1.${NC} Использовать стандартную страницу Nginx (${GREEN}по умолчанию${NC})"
  echo -e "${GREEN}2.${NC} Использовать Cloudreve"
  echo -e "-------------------------------------------"
  echo -e "1.Не настраивать маскировочный сайт, использовать стандартную страницу"
  echo -e "2.Использовать персональное облачное хранилище для маскировки"
  echo -e "-------------------------------------------"
  sni_config_processes
}

function xray_config_management() {
  clear
  echo -e "----------------- Обновление конфигурации ----------------"
  echo -e "${GREEN}1.${NC} VLESS+mKCP+seed"
  echo -e "${GREEN}2.${NC} VLESS+Vision+REALITY"
  echo -e "${GREEN}3.${NC} VLESS+XHTTP+REALITY(${GREEN}по умолчанию${NC})"
  echo -e "${GREEN}4.${NC} Trojan+XHTTP+REALITY"
  echo -e "${GREEN}5.${NC} VLESS+Vision+REALITY+VLESS+XHTTP+REALITY"
  echo -e "${GREEN}6.${NC} SNI+VLESS+Vision+REALITY+VLESS+XHTTP+REALITY"
  echo -e "-------------------------------------------"
  echo -e "1.mKCP ${YELLOW}жертвует пропускной способностью${NC} для ${GREEN}снижения задержки${NC}. При передаче одинакового объема данных ${RED}mKCP обычно потребляет больше трафика, чем TCP${NC}"
  echo -e "2.XTLS(Vision) ${GREEN}решает проблему TLS в TLS${NC}"
  echo -e "3.XHTTP ${GREEN}универсальное решение${NC} для всех сценариев (подробнее: https://github.com/XTLS/Xray-core/discussions/4113)"
  echo -e "3.1.XHTTP по умолчанию поддерживает мультиплексирование, ${GREEN}имеет меньшую задержку, чем Vision${NC}, но ${YELLOW}уступает в скорости при многопоточном тестировании${NC}"
  echo -e "3.2.${RED}Клиенты v2rayN&G имеют глобальную настройку mux.cool - перед использованием XHTTP отключите ее, иначе не получится подключиться к новому серверу Xray${NC}"
  echo -e "4.Замена VLESS на Trojan"
  echo -e "5.Использование VLESS+Vision+REALITY с переходом на VLESS+XHTTP ${GREEN}с общим портом 443${NC}"
  echo -e "6.SNI-разделение трафика через Nginx для ${GREEN}совместного использования порта 443${NC}, позволяющее одновременно использовать прямое подключение REALITY и подключение через CDN"
  echo -e "-------------------------------------------"
  xray_config_processes
}

function main() {
  check_os
  check_xray_script_dependencies
  check_xray_script_version
  clear
  print_banner
  print_script_status
  echo -e "--------------- Xray-script ---------------"
  echo -e " Версия      : ${GREEN}v2024-12-31${NC}"
  echo -e " Описание   : Скрипт управления Xray"
  echo -e "----------------- Управление установкой ----------------"
  echo -e "${GREEN}1.${NC} Полная установка"
  echo -e "${GREEN}2.${NC} Только установка/обновление"
  echo -e "${GREEN}3.${NC} Удаление"
  echo -e "----------------- Управление операциями ----------------"
  echo -e "${GREEN}4.${NC} Запуск"
  echo -e "${GREEN}5.${NC} Остановка"
  echo -e "${GREEN}6.${NC} Перезапуск"
  echo -e "----------------- Управление конфигурацией ----------------"
  echo -e "${GREEN}7.${NC} Ссылка для分享 и QR-код"
  echo -e "${GREEN}8.${NC} Статистика"
  echo -e "${GREEN}9.${NC} Управление конфигурацией"
  echo -e "-------------------------------------------"
  echo -e "${RED}0.${NC} Выход"
  main_processes
}

[[ $EUID -ne 0 ]] && _error "Пожалуйста, запустите скрипт с правами root"

main