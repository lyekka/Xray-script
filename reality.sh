#!/usr/bin/env bash
#
# System Required:  CentOS 7+, Debian9+, Ubuntu16+
# Description:      Скрипт управления Xray
#
# Copyright (C) 2023 zxcvos
#
# Xray-script: https://github.com/zxcvos/Xray-script
# Xray-core: https://github.com/XTLS/Xray-core
# REALITY: https://github.com/XTLS/REALITY
# Xray-examples: https://github.com/chika0801/Xray-examples
# Docker cloudflare-warp: https://github.com/e7h4n/cloudflare-warp
# Cloudflare Warp: https://github.com/haoel/haoel.github.io#943-docker-%D0%BF%D1%80%D0%BE%D0%BA%D1%81%D0%B8

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

# Цвета
readonly RED='\033[1;31;31m'
readonly GREEN='\033[1;31;32m'
readonly YELLOW='\033[1;31;33m'
readonly NC='\033[0m'

# Управление конфигурацией
readonly xray_config_manage='/usr/local/etc/xray-script/xray_config_manage.sh'

declare domain
declare domain_path
declare new_port

# Функции вывода статуса
function _info() {
  printf "${GREEN}[ИНФО] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
}

function _warn() {
  printf "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
}

function _error() {
  printf "${RED}[ОШИБКА] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
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

function _error_detect() {
  local cmd="$1"
  _info "${cmd}"
  eval ${cmd}
  if [[ $? -ne 0 ]]; then
    _error "Ошибка выполнения команды (${cmd}), проверьте и попробуйте снова."
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

function _is_tlsv1_3_h2() {
  local check_url=$(echo $1 | grep -oE '[^/]+(\.[^/]+)+\b' | head -n 1)
  local check_num=$(echo QUIT | stdbuf -oL openssl s_client -connect "${check_url}:443" -tls1_3 -alpn h2 2>&1 | grep -Eoi '(TLSv1.3)|(^ALPN\s+protocol:\s+h2$)|(X25519)' | sort -u | wc -l)
  if [[ ${check_num} -eq 3 ]]; then
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
    systemctl -q is-active ${server_name} && _info "Служба ${server_name} запущена" || _error "Ошибка запуска ${server_name}"
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
    systemctl -q is-active ${server_name} && _info "Служба ${server_name} перезапущена" || _error "Ошибка запуска ${server_name}"
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

function _print_list() {
  local p_list=($@)
  for ((i = 1; i <= ${#p_list[@]}; i++)); do
    hint="${p_list[$i - 1]}"
    echo -e "${GREEN}${i}${NC}) ${hint}"
  done
}

function select_data() {
  local data_list=($(awk -v FS=',' '{for (i=1; i<=NF; i++) arr[i]=$i} END{for (i in arr) print arr[i]}' <<<"${1}"))
  local index_list=($(awk -v FS=',' '{for (i=1; i<=NF; i++) arr[i]=$i} END{for (i in arr) print arr[i]}' <<<"${2}"))
  local result_list=()
  if [[ ${#index_list[@]} -ne 0 ]]; then
    for i in "${index_list[@]}"; do
      if _is_digit "${i}" && [ ${i} -ge 1 ] && [ ${i} -le ${#data_list[@]} ]; then
        i=$((i - 1))
        result_list+=("${data_list[${i}]}")
      fi
    done
  else
    result_list=("${data_list[@]}")
  fi
  if [[ ${#result_list[@]} -eq 0 ]]; then
    result_list=("${data_list[@]}")
  fi
  echo "${result_list[@]}"
}

function select_dest() {
  local dest_list=($(jq '.xray.serverNames | keys_unsorted' /usr/local/etc/xray-script/config.json | grep -Eoi '".*"' | sed -En 's|"(.*)"|\1|p'))
  local cur_dest=$(jq -r '.xray.dest' /usr/local/etc/xray-script/config.json)
  local pick_dest=""
  local all_sns=""
  local sns=""
  local prompt="Выберите dest, текущий по умолчанию \"${cur_dest}\", для ручного ввода выберите 0: "
  until [[ ${is_dest} =~ ^[Yy]$ ]]; do
    echo -e "---------------- Список dest ----------------"
    _print_list "${dest_list[@]}"
    read -p "${prompt}" pick
    if [[ "${pick}" == "" && "${cur_dest}" != "" ]]; then
      pick_dest=${cur_dest}
      break
    fi
    if ! _is_digit "${pick}" || [[ "${pick}" -lt 0 || "${pick}" -gt ${#dest_list[@]} ]]; then
      prompt="Ошибка ввода, введите число от 0 до ${#dest_list[@]}: "
      continue
    fi
    if [[ "${pick}" == "0" ]]; then
      _warn "Если ввести существующий в списке домен, serverNames будет изменен"
      _warn "При использовании своего домена убедитесь в его доступности внутри страны"
      read_domain
      _info "Проверка поддержки TLSv1.3 и h2 для \"${domain}\""
      if ! _is_tlsv1_3_h2 "${domain}"; then
        _warn "\"${domain}\" не поддерживает TLSv1.3 или h2, либо Client Hello не X25519"
        continue
      fi
      _info "\"${domain}\" поддерживает TLSv1.3 и h2"
      _info "Получение Allowed domains"
      pick_dest=${domain}
      all_sns=$(xray tls ping ${pick_dest} | sed -n '/with SNI/,$p' | sed -En 's/\[(.*)\]/\1/p' | sed -En 's/Allowed domains:\s*//p' | jq -R -c 'split(" ")' | jq --arg sni "${pick_dest}" '. += [$sni]')
      sns=$(echo ${all_sns} | jq 'map(select(test("^[^*]+$"; "g")))' | jq -c 'map(select(test("^((?!cloudflare|akamaized|edgekey|edgesuite|cloudfront|azureedge|msecnd|edgecastcdn|fastly|googleusercontent|kxcdn|maxcdn|stackpathdns|stackpathcdn).)*$"; "ig")))')
      _info "SNI до фильтрации"
      _print_list $(echo ${all_sns} | jq -r '.[]')
      _info "SNI после фильтрации"
      _print_list $(echo ${sns} | jq -r '.[]')
      read -p "Выберите serverName через запятую, по умолчанию все: " pick_num
      sns=$(select_data "$(awk 'BEGIN{ORS=","} {print}' <<<"$(echo ${sns} | jq -r -c '.[]')")" "${pick_num}" | jq -R -c 'split(" ")')
      _info "Для добавления serverNames отредактируйте /usr/local/etc/xray-script/config.json"
    else
      pick_dest="${dest_list[${pick} - 1]}"
    fi
    read -r -p "Использовать dest: \"${pick_dest}\" [y/n] " is_dest
    prompt="Выберите dest, текущий по умолчанию \"${cur_dest}\", для ручного ввода выберите 0: "
    echo -e "--------------------------------------------"
  done
  _info "Изменение конфигурации"
  [[ "${domain_path}" != "" ]] && pick_dest="${pick_dest}${domain_path}"
  if echo ${pick_dest} | grep -q '/$'; then
    pick_dest=$(echo ${pick_dest} | sed -En 's|/+$||p')
  fi
  [[ "${sns}" != "" ]] && jq --argjson sn "{\"${pick_dest}\": ${sns}}" '.xray.serverNames += $sn' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
  jq --arg dest "${pick_dest}" '.xray.dest = $dest' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
}
function read_domain() {
  until [[ ${is_domain} =~ ^[Yy]$ ]]; do
    read -p "Введите домен: " domain
    check_domain=$(echo ${domain} | grep -oE '[^/]+(\.[^/]+)+\b' | head -n 1)
    read -r -p "Подтвердите домен: \"${check_domain}\" [y/n] " is_domain
  done
  domain_path=$(echo "${domain}" | sed -En "s|.*${check_domain}(/.*)?|\1|p")
  domain=${check_domain}
}

function read_port() {
  local prompt="${1}"
  local cur_port="${2}"
  until [[ ${is_port} =~ ^[Yy]$ ]]; do
    echo "${prompt}"
    read -p "Введите порт (1-65535), по умолчанию оставить текущий: " new_port
    if [[ "${new_port}" == "" || ${new_port} -eq ${cur_port} ]]; then
      new_port=${cur_port}
      _info "Оставляем текущий порт: ${cur_port}"
      break
    fi
    if ! _is_digit "${new_port}" || [[ ${new_port} -lt 1 || ${new_port} -gt 65535 ]]; then
      prompt="Ошибка, порт должен быть числом от 1 до 65535"
      continue
    fi
    read -r -p "Подтвердите порт: \"${new_port}\" [y/n] " is_port
    prompt="${1}"
  done
}

function read_uuid() {
  _info 'Введите кастомный UUID (если формат неверный, будет сгенерирован UUIDv5)'
  read -p "Введите UUID или оставьте пустым для автогенерации: " in_uuid
}

function check_os() {
  [[ -z "$(_os)" ]] && _error "Неподдерживаемая ОС"
  case "$(_os)" in
  ubuntu)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 16 ]] && _error "Требуется Ubuntu 16+"
    ;;
  debian)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 9 ]] && _error "Требуется Debian 9+"
    ;;
  centos)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 7 ]] && _error "Требуется CentOS 7+"
    ;;
  *)
    _error "Неподдерживаемая ОС"
    ;;
  esac
}

function install_dependencies() {
  _info "Установка зависимостей"
  _install "ca-certificates openssl curl wget jq tzdata"
  case "$(_os)" in
  centos)
    _install "crontabs util-linux iproute procps-ng"
    ;;
  debian | ubuntu)
    _install "cron bsdmainutils iproute2 procps"
    ;;
  esac
}

function install_update_xray() {
  _info "Установка/обновление Xray"
  _error_detect 'bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root --beta'
  jq --arg ver "$(xray version | head -n 1 | cut -d \( -f 1 | grep -Eoi '[0-9.]*')" '.xray.version = $ver' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
  wget -O /usr/local/etc/xray-script/update-dat.sh https://raw.githubusercontent.com/lyekka/Xray-script/main/tool/update-dat.sh
  chmod a+x /usr/local/etc/xray-script/update-dat.sh
  (crontab -l 2>/dev/null; echo "30 22 * * * /usr/local/etc/xray-script/update-dat.sh >/dev/null 2>&1") | awk '!x[$0]++' | crontab -
  /usr/local/etc/xray-script/update-dat.sh
}

function purge_xray() {
  _info "Удаление Xray"
  crontab -l | grep -v "/usr/local/etc/xray-script/update-dat.sh >/dev/null 2>&1" | crontab -
  _systemctl "stop" "xray"
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
  rm -rf /etc/systemd/system/xray.service
  rm -rf /etc/systemd/system/xray@.service
  rm -rf /usr/local/bin/xray
  rm -rf /usr/local/etc/xray
  rm -rf /usr/local/share/xray
  rm -rf /var/log/xray
}

function service_xray() {
  _info "Настройка службы xray"
  wget -O ${HOME}/xray.service https://raw.githubusercontent.com/lyekka/Xray-script/main/service/xray.service
  mv -f ${HOME}/xray.service /etc/systemd/system/xray.service
  _systemctl dr
}

function config_xray() {
  _info "Настройка config.json"
  "${xray_config_manage}" --path ${HOME}/config.json --download
  local xray_x25519=$(xray x25519)
  local xs_private_key=$(echo ${xray_x25519} | awk '{print $3}')
  local xs_public_key=$(echo ${xray_x25519} | awk '{print $6}')
  # Xray-script config.json
  jq --arg privateKey "${xs_private_key}" '.xray.privateKey = $privateKey' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
  jq --arg publicKey "${xs_public_key}" '.xray.publicKey = $publicKey' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
  # Xray-core config.json
  "${xray_config_manage}" --path ${HOME}/config.json -p ${new_port}
  "${xray_config_manage}" --path ${HOME}/config.json -u ${in_uuid}
  "${xray_config_manage}" --path ${HOME}/config.json -d "$(jq -r '.xray.dest' /usr/local/etc/xray-script/config.json | grep -Eoi '([a-zA-Z0-9](\-?[a-zA-Z0-9])*\.)+[a-zA-Z]{2,}')"
  "${xray_config_manage}" --path ${HOME}/config.json -sn "$(jq -c -r '.xray | .serverNames[.dest] | .[]' /usr/local/etc/xray-script/config.json | tr '\n' ',')"
  "${xray_config_manage}" --path ${HOME}/config.json -x "${xs_private_key}"
  "${xray_config_manage}" --path ${HOME}/config.json -rsid
  mv -f ${HOME}/config.json /usr/local/etc/xray/config.json
  _systemctl "restart" "xray"
}

function tcp2raw() {
  local current_xray_version=$(xray version | awk '$1=="Xray" {print $2}')
  local tcp2raw_xray_version='24.9.30'
  if _version_ge "${current_xray_version}" "${tcp2raw_xray_version}"; then
    sed -i 's/"network": "tcp"/"network": "raw"/' /usr/local/etc/xray/config.json
    _systemctl "restart" "xray"
  fi
}

function dest2target() {
  local current_xray_version=$(xray version | awk '$1=="Xray" {print $2}')
  local dest2target_xray_version='24.10.31'
  if _version_ge "${current_xray_version}" "${dest2target_xray_version}"; then
    sed -i 's/"dest"/"target"/' /usr/local/etc/xray/config.json
    _systemctl "restart" "xray"
  fi
}

function show_config() {
  local IPv4=$(wget -qO- -t1 -T2 ipv4.icanhazip.com)
  local xs_inbound=$(jq '.inbounds[] | select(.tag == "xray-script-xtls-reality")' /usr/local/etc/xray/config.json)
  local xs_port=$(echo ${xs_inbound} | jq '.port')
  local xs_protocol=$(echo ${xs_inbound} | jq '.protocol')
  local xs_ids=$(echo ${xs_inbound} | jq '.settings.clients[] | .id' | tr '\n' ',')
  local xs_public_key=$(jq '.xray.publicKey' /usr/local/etc/xray-script/config.json)
  local xs_serverNames=$(echo ${xs_inbound} | jq '.streamSettings.realitySettings.serverNames[]' | tr '\n' ',')
  local xs_shortIds=$(echo ${xs_inbound} | jq '.streamSettings.realitySettings.shortIds[]' | tr '\n' ',')
  local xs_spiderX=$(jq '.xray.dest' /usr/local/etc/xray-script/config.json)
  [[ "${xs_spiderX}" == "${xs_spiderX##*/}" ]] && xs_spiderX='"/"' || xs_spiderX="\"/${xs_spiderX#*/}"
  echo -e "-------------- Конфиг клиента --------------"
  echo -e "address     : \"${IPv4}\""
  echo -e "port        : ${xs_port}"
  echo -e "protocol    : ${xs_protocol}"
  echo -e "id          : ${xs_ids%,}"
  echo -e "flow        : \"xtls-rprx-vision\""
  echo -e "network     : \"tcp\""
  echo -e "TLS         : \"reality\""
  echo -e "SNI         : ${xs_serverNames%,}"
  echo -e "Fingerprint : \"chrome\""
  echo -e "PublicKey   : ${xs_public_key}"
  echo -e "ShortId     : ${xs_shortIds%,}"
  echo -e "SpiderX     : ${xs_spiderX}"
  echo -e "------------------------------------------"
  read -p "Сгенерировать ссылку для импорта? [y/n]: " is_show_share_link
  echo
  if [[ ${is_show_share_link} =~ ^[Yy]$ ]]; then
    show_share_link
  else
    echo -e "------------------------------------------"
    echo -e "${RED}Скрипт предназначен только для обучения.${NC}"
    echo -e "${RED}Не используйте для незаконных целей.${NC}"
    echo -e "------------------------------------------"
  fi
}

function show_share_link() {
  local sl=""
  # Параметры ссылки
  local sl_host=$(wget -qO- -t1 -T2 ipv4.icanhazip.com)
  local sl_inbound=$(jq '.inbounds[] | select(.tag == "xray-script-xtls-reality")' /usr/local/etc/xray/config.json)
  local sl_port=$(echo ${sl_inbound} | jq -r '.port')
  local sl_protocol=$(echo ${sl_inbound} | jq -r '.protocol')
  local sl_ids=$(echo ${sl_inbound} | jq -r '.settings.clients[] | .id')
  local sl_public_key=$(jq -r '.xray.publicKey' /usr/local/etc/xray-script/config.json)
  local sl_serverNames=$(echo ${sl_inbound} | jq -r '.streamSettings.realitySettings.serverNames[]')
  local sl_shortIds=$(echo ${sl_inbound} | jq '.streamSettings.realitySettings.shortIds[]')
  # Поля ссылки
  local sl_uuid=""
  local sl_security='security=reality'
  local sl_flow='flow=xtls-rprx-vision'
  local sl_fingerprint='fp=chrome'
  local sl_publicKey="pbk=${sl_public_key}"
  local sl_sni=""
  local sl_shortId=""
  local sl_spiderX='spx=%2F'
  local sl_descriptive_text='VLESS-XTLS-uTLS-REALITY'
  # Выбор параметров
  _print_list "${sl_ids[@]}"
  read -p "Выберите UUID (через запятую), по умолчанию все: " pick_num
  sl_id=($(select_data "$(awk 'BEGIN{ORS=","} {print}' <<<"${sl_ids[@]}")" "${pick_num}"))
  _print_list "${sl_serverNames[@]}"
  read -p "Выберите serverName (через запятую), по умолчанию все: " pick_num
  sl_serverNames=($(select_data "$(awk 'BEGIN{ORS=","} {print}' <<<"${sl_serverNames[@]}")" "${pick_num}"))
  _print_list "${sl_shortIds[@]}"
  read -p "Выберите shortId (через запятую), по умолчанию все: " pick_num
  sl_shortIds=($(select_data "$(awk 'BEGIN{ORS=","} {print}' <<<"${sl_shortIds[@]}")" "${pick_num}"))
  echo -e "--------------- Ссылки для импорта ---------------"
  for sl_id in "${sl_ids[@]}"; do
    sl_uuid="${sl_id}"
    for sl_serverName in "${sl_serverNames[@]}"; do
      sl_sni="sni=${sl_serverName}"
      echo -e "---------- serverName ${sl_sni} ----------"
      for sl_shortId in "${sl_shortIds[@]}"; do
        [[ "${sl_shortId//\"/}" != "" ]] && sl_shortId="sid=${sl_shortId//\"/}" || sl_shortId=""
        sl="${sl_protocol}://${sl_uuid}@${sl_host}:${sl_port}?${sl_security}&${sl_flow}&${sl_fingerprint}&${sl_publicKey}&${sl_sni}&${sl_spiderX}&${sl_shortId}"
        echo "${sl%&}#${sl_descriptive_text}"
      done
      echo -e "------------------------------------------------"
    done
  done
  echo -e "------------------------------------------"
  echo -e "${RED}Скрипт предназначен только для обучения.${NC}"
  echo -e "${RED}Не используйте для незаконных целей.${NC}"
  echo -e "------------------------------------------"
}

function menu() {
  check_os
  clear
  echo -e "--------------- Xray-script ---------------"
  echo -e " Версия      : ${GREEN}v2023-03-15${NC}(${RED}beta${NC})"
  echo -e " Описание    : Скрипт управления Xray"
  echo -e "---------------- Управление ----------------"
  echo -e "${GREEN}1.${NC} Установка"
  echo -e "${GREEN}2.${NC} Обновление"
  echo -e "${GREEN}3.${NC} Удаление"
  echo -e "---------------- Действия ------------------"
  echo -e "${GREEN}4.${NC} Запуск"
  echo -e "${GREEN}5.${NC} Остановка"
  echo -e "${GREEN}6.${NC} Перезапуск"
  echo -e "---------------- Настройки -----------------"
  echo -e "${GREEN}101.${NC} Просмотр конфига"
  echo -e "${GREEN}102.${NC} Статистика"
  echo -e "${GREEN}103.${NC} Изменить ID"
  echo -e "${GREEN}104.${NC} Изменить dest"
  echo -e "${GREEN}105.${NC} Изменить x25519 key"
  echo -e "${GREEN}106.${NC} Изменить shortIds"
  echo -e "${GREEN}107.${NC} Изменить порт"
  echo -e "${GREEN}108.${NC} Обновить shortIds"
  echo -e "${GREEN}109.${NC} Добавить shortIds"
  echo -e "${GREEN}110.${NC} WARP для OpenAI"
  echo -e "---------------- Другое --------------------"
  echo -e "${GREEN}201.${NC} Обновить ядро"
  echo -e "${GREEN}202.${NC} Удалить старые ядра"
  echo -e "${GREEN}203.${NC} Изменить SSH порт"
  echo -e "${GREEN}204.${NC} Оптимизация сети"
  echo -e "-------------------------------------------"
  echo -e "${RED}0.${NC} Выход"
  read -rp "Выберите: " idx
  ! _is_digit "${idx}" && _error "Введите число"
  if [[ ! -d /usr/local/etc/xray-script && (${idx} -ne 0 && ${idx} -ne 1 && ${idx} -lt 201) ]]; then
    _error "Сначала установите Xray-script"
  fi
  if [ -d /usr/local/etc/xray-script ] && ([ ${idx} -gt 102 ] || [ ${idx} -lt 111 ]); then
    wget -qO ${xray_config_manage} https://raw.githubusercontent.com/lyekka/Xray-script/main/tool/xray_config_manage.sh
    chmod a+x ${xray_config_manage}
  fi
  case "${idx}" in
  1)
    if [[ ! -d /usr/local/etc/xray-script ]]; then
      mkdir -p /usr/local/etc/xray-script
      wget -O /usr/local/etc/xray-script/config.json https://raw.githubusercontent.com/lyekka/Xray-script/main/config/config.json
      wget -O ${xray_config_manage} https://raw.githubusercontent.com/lyekka/Xray-script/main/tool/xray_config_manage.sh
      chmod a+x ${xray_config_manage}
      install_dependencies
      install_update_xray
      local xs_port=$(jq '.xray.port' /usr/local/etc/xray-script/config.json)
      read_port "Текущий порт: ${xs_port}" "${xs_port}"
      read_uuid
      select_dest
      config_xray
      tcp2raw
      dest2target
      show_config
    fi
    ;;
  2)
    _info "Проверка обновлений Xray"
    local current_xray_version="$(jq -r '.xray.version' /usr/local/etc/xray-script/config.json)"
    local latest_xray_version="$(wget -qO- --no-check-certificate https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[0].tag_name ' | cut -d v -f 2)"
    if _version_ge "${latest_xray_version}" "${current_xray_version}"; then
      _info "Доступно обновление"
      install_update_xray
      tcp2raw
      dest2target
    else
      _info "Установлена последняя версия: ${current_xray_version}"
    fi
    ;;
  3)
    purge_xray
    [[ -f /usr/local/etc/xray-script/sysctl.conf.bak ]] && mv -f /usr/local/etc/xray-script/sysctl.conf.bak /etc/sysctl.conf && _info "Восстановлены сетевые настройки"
    rm -rf /usr/local/etc/xray-script
    if docker ps | grep -q cloudflare-warp; then
      _info 'Остановка cloudflare-warp'
      docker container stop cloudflare-warp
      docker container rm cloudflare-warp
    fi
    if docker images | grep -q e7h4n/cloudflare-warp; then
      _info 'Удаление cloudflare-warp'
      docker image rm e7h4n/cloudflare-warp
    fi
    rm -rf ${HOME}/.warp
    _info 'Docker нужно удалить отдельно'
    _info "Удаление завершено"
    ;;
  4)
    _systemctl "start" "xray"
    ;;
  5)
    _systemctl "stop" "xray"
    ;;
  6)
    _systemctl "restart" "xray"
    ;;
  101)
    show_config
    ;;
  102)
    [[ -f /usr/local/etc/xray-script/traffic.sh ]] || wget -O /usr/local/etc/xray-script/traffic.sh https://raw.githubusercontent.com/lyekka/Xray-script/main/tool/traffic.sh
    bash /usr/local/etc/xray-script/traffic.sh
    ;;
  103)
    read_uuid
    _info "Изменение ID"
    "${xray_config_manage}" -u ${in_uuid}
    _info "ID изменен"
    _systemctl "restart" "xray"
    show_config
    ;;
  104)
    _info "Изменение dest и serverNames"
    select_dest
    local current_xray_version=$(xray version | awk '$1=="Xray" {print $2}')
    local dest2target_xray_version='24.10.31'
    if _version_ge "${current_xray_version}" "${dest2target_xray_version}"; then
      "${xray_config_manage}" -d "$(jq -r '.xray.target' /usr/local/etc/xray-script/config.json | grep -Eoi '([a-zA-Z0-9](\-?[a-zA-Z0-9])*\.)+[a-zA-Z]{2,}')"
      "${xray_config_manage}" -sn "$(jq -c -r '.xray | .serverNames[.target] | .[]' /usr/local/etc/xray-script/config.json | tr '\n' ',')"
    else
      "${xray_config_manage}" -d "$(jq -r '.xray.dest' /usr/local/etc/xray-script/config.json | grep -Eoi '([a-zA-Z0-9](\-?[a-zA-Z0-9])*\.)+[a-zA-Z]{2,}')"
      "${xray_config_manage}" -sn "$(jq -c -r '.xray | .serverNames[.dest] | .[]' /usr/local/etc/xray-script/config.json | tr '\n' ',')"
    fi
    _info "dest и serverNames изменены"
    _systemctl "restart" "xray"
    show_config
    ;;
  105)
    _info "Изменение x25519 ключей"
    local xray_x25519=$(xray x25519)
    local xs_private_key=$(echo ${xray_x25519} | awk '{print $3}')
    local xs_public_key=$(echo ${xray_x25519} | awk '{print $6}')
    # Обновляем конфиг
    jq --arg privateKey "${xs_private_key}" '.xray.privateKey = $privateKey' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
    jq --arg publicKey "${xs_public_key}" '.xray.publicKey = $publicKey' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
    "${xray_config_manage}" -x "${xs_private_key}"
    _info "Ключи изменены"
    _systemctl "restart" "xray"
    show_config
    ;;
  106)
    _info "shortId: 16-ричное число, длина кратна 2 (макс 16 символов)"
    _info "По умолчанию список shortId имеет значение [\"\"]. Если этот параметр присутствует, клиент может оставить shortId пустым"
    read -p "Введите shortIds через запятую: " sid_str
    _info "Изменение shortIds"
    "${xray_config_manage}" -sid "${sid_str}"
    _info "shortIds изменены"
    _systemctl "restart" "xray"
    show_config
    ;;
  107)
    local xs_port=$(jq '.inbounds[] | select(.tag == "xray-script-xtls-reality") | .port' /usr/local/etc/xray/config.json)
    read_port "Текущий порт: ${xs_port}" "${xs_port}"
    if [[ "${new_port}" && ${new_port} -ne ${xs_port} ]]; then
      "${xray_config_manage}" -p ${new_port}
      _info "Порт изменен на: ${new_port}"
      _systemctl "restart" "xray"
      show_config
    fi
    ;;
  108)
    _info "Обновление shortIds"
    "${xray_config_manage}" -rsid
    _info "shortIds обновлены"
    _systemctl "restart" "xray"
    show_config
    ;;
  109)
    until [ ${#sid_str} -gt 0 ] && [ ${#sid_str} -le 16 ] && [ $((${#sid_str} % 2)) -eq 0 ]; do
      _info "shortId: 16-ричное число, длина кратна 2 (макс 16 символов)"
      read -p "Введите shortIds через запятую: " sid_str
    done
    _info "Добавление shortIds"
    "${xray_config_manage}" -asid "${sid_str}"
    _info "shortIds добавлены"
    _systemctl "restart" "xray"
    show_config
    ;;
  110)
    if ! _exists "docker"; then
      read -r -p "Установить Docker? [y/n] " is_docker
      if [[ ${is_docker} =~ ^[Yy]$ ]]; then
        curl -fsSL -o /usr/local/etc/xray-script/install-docker.sh https://get.docker.com
        if [[ "$(_os)" == "centos" && "$(_os_ver)" -eq 8 ]]; then
          sed -i 's|$sh_c "$pkg_manager install -y -q $pkgs"| $sh_c "$pkg_manager install -y -q $pkgs --allowerasing"|' /usr/local/etc/xray-script/install-docker.sh
        fi
        sh /usr/local/etc/xray-script/install-docker.sh --dry-run
        sh /usr/local/etc/xray-script/install-docker.sh
      else
        _warn "Отмена"
        exit 0
      fi
    fi
    if docker ps | grep -q cloudflare-warp; then
      _info "WARP уже запущен"
    else
      _info "Запуск cloudflare-warp"
      docker run -v $HOME/.warp:/var/lib/cloudflare-warp:rw --restart=always --name=cloudflare-warp e7h4n/cloudflare-warp
      _info "Настройка routing"
      local routing='{"type":"field","domain":["domain:ipinfo.io","domain:ip.sb","geosite:openai"],"outboundTag":"warp"}'
      _info "Настройка outbounds"
      local outbound=$(echo '{"tag":"warp","protocol":"socks","settings":{"servers":[{"address":"172.17.0.2","port":40001}]}}' | jq -c --arg addr "$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cloudflare-warp)" '.settings.servers[].address = $addr')
      jq --argjson routing "${routing}" '.routing.rules += [$routing]' /usr/local/etc/xray/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray/config.json
      jq --argjson outbound "${outbound}" '.outbounds += [$outbound]' /usr/local/etc/xray/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray/config.json
      _systemctl "restart" "xray"
      show_config
    fi
    ;;
  201)
    bash <(wget -qO- https://raw.githubusercontent.com/lyekka/system-automation-scripts/main/update-kernel.sh)
    ;;
  202)
    bash <(wget -qO- https://raw.githubusercontent.com/lyekka/system-automation-scripts/main/remove-kernel.sh)
    ;;
  203)
    local ssh_port=$(sed -En "s/^[#pP].*ort\s*([0-9]*)$/\1/p" /etc/ssh/sshd_config)
    read_port "Текущий SSH порт: ${ssh_port}" "${ssh_port}"
    if [[ "${new_port}" && ${new_port} -ne ${ssh_port} ]]; then
      sed -i "s/^[#pP].*ort\s*[0-9]*$/Port ${new_port}/" /etc/ssh/sshd_config
      systemctl restart sshd
      _info "SSH порт изменен на: ${new_port}"
    fi
    ;;
  204)
    read -r -p "Оптимизировать сеть? [y/n] " is_opt
    if [[ ${is_opt} =~ ^[Yy]$ ]]; then
      [[ -f /usr/local/etc/xray-script/sysctl.conf.bak ]] || cp -af /etc/sysctl.conf /usr/local/etc/xray-script/sysctl.conf.bak
      wget -O /etc/sysctl.conf https://raw.githubusercontent.com/lyekka/Xray-script/main/config/sysctl.conf
      sysctl -p
    fi
    ;;
  0)
    exit 0
    ;;
  *)
    _error "Неверный выбор"
    ;;
  esac
}

[[ $EUID -ne 0 ]] && _error "Требуются права root"

menu