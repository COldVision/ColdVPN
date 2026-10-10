#!/usr/bin/env bash
# Установка AmneziaWG на VPS. Запускается приложением по SSH.
# Разворачивает тот же контейнер, что и официальное приложение Amnezia
# (образ amneziavpn/amneziawg-go), и выдаёт конфигурацию для устройства.
#
# Параметры: SVPN_PORT   — UDP-порт (0 = выбрать случайный при первой установке)
#            SVPN_DEVICE — имя устройства; у каждого устройства свой ключ и адрес
#            SVPN_RESET=1 — выпустить все ключи заново
# Повторный запуск ничего не ломает: ключи и параметры сохраняются.
set -euo pipefail

PORT="${SVPN_PORT:-0}"
DEVICE="${SVPN_DEVICE:-windows}"
RESET="${SVPN_RESET:-0}"
DIR="${SVPN_DIR:-/opt/splitvpn/awg}"
NAME="splitvpn-awg"
IMAGE="splitvpn-awg"
BASE_IMAGE="amneziavpn/amneziawg-go:latest"
NET="10.66.77"

step() { echo "==> $*"; }
fail() { echo "SVPN_ERROR: $*"; exit 1; }

[ "$(id -u)" = "0" ] || fail "нужны права root (войдите под root или пользователем с sudo без пароля)"
case "$PORT" in ''|*[!0-9]*) fail "некорректный порт: $PORT";; esac
case "$DEVICE" in ''|*[!a-zA-Z0-9_-]*) fail "некорректное имя устройства: $DEVICE";; esac

install_pkg() {
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -y -q >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$@" >/dev/null
  elif command -v dnf >/dev/null 2>&1; then dnf install -y -q "$@" >/dev/null
  elif command -v yum >/dev/null 2>&1; then yum install -y -q "$@" >/dev/null
  else fail "не удалось установить $*: неизвестный менеджер пакетов"; fi
}
command -v curl >/dev/null 2>&1 || { step "Устанавливаю curl"; install_pkg curl; }

# Прежняя установка Xray от этого приложения больше не нужна.
if grep -qs '"splitvpn-in"' /usr/local/etc/xray/config.json; then
  step "Останавливаю прежний Xray"
  systemctl disable --now xray >/dev/null 2>&1 || true
fi

if ! command -v docker >/dev/null 2>&1; then
  step "Устанавливаю Docker (официальный установщик get.docker.com)"
  curl -fsSL https://get.docker.com | sh </dev/null >/dev/null 2>&1 \
    || fail "не удалось установить Docker — проверьте, что с сервера открывается get.docker.com"
fi
systemctl enable --now docker >/dev/null 2>&1 || true
docker info >/dev/null 2>&1 || fail "Docker установлен, но не запускается"

step "Готовлю образ AmneziaWG"
BUILD="$(mktemp -d)"
cat > "$BUILD/Dockerfile" <<DOCKER_EOF
FROM $BASE_IMAGE
RUN apk add --no-cache bash dumb-init iptables
ENTRYPOINT [ "dumb-init", "/opt/amnezia/awg/start.sh" ]
DOCKER_EOF
docker build -q -t "$IMAGE" "$BUILD" </dev/null >/dev/null 2>&1 \
  || docker build -t "$IMAGE" "$BUILD" </dev/null \
  || fail "не удалось собрать образ — проверьте, что с сервера открывается hub.docker.com"
rm -rf "$BUILD"
# Скрипт может выполняться из stdin, а `docker run -i` читает stdin до конца.
# Поэтому stdin передаётся контейнеру только там, где он действительно нужен
# (pubkey), а в остальных вызовах закрыт — иначе контейнер «съест» остаток
# скрипта, и установка молча оборвётся.
awg() { docker run --rm --entrypoint awg "$IMAGE" "$@" </dev/null; }
awg_stdin() { docker run --rm -i --entrypoint awg "$IMAGE" "$@"; }

# Docker должен уметь запускать контейнеры. После обновления системных
# пакетов systemd иногда теряет связь с D-Bus, и запуск падает с ошибкой
# «Message recipient disconnected from message bus»; лечится перезапуском
# systemd и Docker, в крайнем случае — перезагрузкой сервера.
docker_ok() { docker run --rm --entrypoint /bin/true "$IMAGE" </dev/null >/dev/null 2>&1; }
if ! docker_ok; then
  step "Docker не смог запустить контейнер — перезапускаю systemd и Docker"
  systemctl daemon-reexec >/dev/null 2>&1 || true
  sleep 2
  systemctl restart docker >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do docker info >/dev/null 2>&1 && break; sleep 1; done
  if ! docker_ok; then
    docker run --rm --entrypoint /bin/true "$IMAGE" </dev/null 2>&1 | tail -n 2 | cut -c1-300 | sed 's/^/    /' || true
    fail "Docker не запускает контейнеры даже после перезапуска. Перезагрузите сервер (в панели хостинга или командой reboot) и повторите установку"
  fi
  echo "    помогло, продолжаю"
fi

mkdir -p "$DIR/clients"
chmod 700 "$DIR"
STATE="$DIR/server.env"
[ "$RESET" = "1" ] && rm -f "$STATE" "$DIR"/clients/*.env

rand() { echo $(( $1 + ( ($(od -An -N4 -tu4 /dev/urandom) ) % ($2 - $1 + 1) ) )); }

SPRIV=""; SPUB=""; SPORT=""; JC=""; JMIN=""; JMAX=""; S1=""; S2=""; H1=""; H2=""; H3=""; H4=""
# shellcheck disable=SC1090
[ -f "$STATE" ] && . "$STATE"
if [ -z "$SPRIV" ] || [ -z "$H4" ]; then
  step "Генерирую ключи и параметры маскировки сервера"
  SPRIV="$(awg genkey)"
  SPUB="$(echo "$SPRIV" | awg_stdin pubkey)"
  [ ${#SPRIV} -eq 44 ] && [ ${#SPUB} -eq 44 ] || fail "не удалось сгенерировать ключи сервера"
  JC="$(rand 4 8)"; JMIN="$(rand 8 20)"; JMAX="$(rand 50 90)"
  S1="$(rand 15 150)"; S2="$(rand 15 150)"
  while [ $((S1 + 56)) -eq "$S2" ] || [ "$S1" -eq "$S2" ]; do S2="$(rand 15 150)"; done
  H1="$(rand 5 2147483647)"; H2="$(rand 5 2147483647)"; H3="$(rand 5 2147483647)"; H4="$(rand 5 2147483647)"
  while [ "$H2" = "$H1" ]; do H2="$(rand 5 2147483647)"; done
  while [ "$H3" = "$H1" ] || [ "$H3" = "$H2" ]; do H3="$(rand 5 2147483647)"; done
  while [ "$H4" = "$H1" ] || [ "$H4" = "$H2" ] || [ "$H4" = "$H3" ]; do H4="$(rand 5 2147483647)"; done
  SPORT=""
else
  step "Использую уже выпущенные ключи сервера"
fi
# Порт: заданный явно важнее сохранённого; иначе сохранённый; иначе случайный.
if [ "$PORT" != "0" ]; then SPORT="$PORT"; fi
[ -n "$SPORT" ] || SPORT="$(rand 20000 60000)"
umask 077
cat > "$STATE" <<STATE_EOF
SPRIV="$SPRIV"
SPUB="$SPUB"
SPORT="$SPORT"
JC="$JC"
JMIN="$JMIN"
JMAX="$JMAX"
S1="$S1"
S2="$S2"
H1="$H1"
H2="$H2"
H3="$H3"
H4="$H4"
STATE_EOF

CFILE="$DIR/clients/$DEVICE.env"
CPRIV=""; CPUB=""; CPSK=""; CIP=""
# shellcheck disable=SC1090
[ -f "$CFILE" ] && . "$CFILE"
if [ -z "$CPRIV" ] || [ -z "$CIP" ]; then
  step "Выпускаю ключи для устройства «$DEVICE»"
  CPRIV="$(awg genkey)"
  CPUB="$(echo "$CPRIV" | awg_stdin pubkey)"
  CPSK="$(awg genpsk)"
  [ ${#CPRIV} -eq 44 ] && [ ${#CPUB} -eq 44 ] && [ ${#CPSK} -eq 44 ] || fail "не удалось сгенерировать ключи устройства"
  N=2
  while grep -qs "CIP=\"$NET.$N\"" "$DIR"/clients/*.env 2>/dev/null; do N=$((N + 1)); done
  [ "$N" -le 250 ] || fail "закончились адреса для устройств"
  CIP="$NET.$N"
  cat > "$CFILE" <<CLIENT_EOF
CPRIV="$CPRIV"
CPUB="$CPUB"
CPSK="$CPSK"
CIP="$CIP"
CLIENT_EOF
else
  step "Использую уже выпущенные ключи устройства «$DEVICE»"
fi

step "Записываю конфигурацию"
{
  cat <<CONF_EOF
[Interface]
PrivateKey = $SPRIV
Address = $NET.1/24
ListenPort = $SPORT
MTU = 1280
Jc = $JC
Jmin = $JMIN
Jmax = $JMAX
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4
CONF_EOF
  for F in "$DIR"/clients/*.env; do
    ( . "$F"
      echo
      echo "# $(basename "$F" .env)"
      echo "[Peer]"
      echo "PublicKey = $CPUB"
      echo "PresharedKey = $CPSK"
      echo "AllowedIPs = $CIP/32" )
  done
} > "$DIR/awg0.conf"

cat > "$DIR/start.sh" <<START_EOF
#!/bin/bash
# Запускается при каждом старте контейнера.
awg-quick down /opt/amnezia/awg/awg0.conf 2>/dev/null
awg-quick up /opt/amnezia/awg/awg0.conf
iptables -A INPUT -i awg0 -j ACCEPT
iptables -A FORWARD -i awg0 -j ACCEPT
iptables -A OUTPUT -o awg0 -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -A POSTROUTING -s $NET.0/24 -o eth0 -j MASQUERADE
tail -f /dev/null
START_EOF
chmod 700 "$DIR/start.sh"
umask 022

step "Запускаю контейнер (UDP-порт $SPORT)"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d \
  --name "$NAME" \
  --restart always \
  --privileged \
  --cap-add=NET_ADMIN \
  --log-driver json-file --log-opt max-size=1m \
  -p "$SPORT:$SPORT/udp" \
  -v "$DIR:/opt/amnezia/awg" \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  "$IMAGE" </dev/null >/dev/null || fail "контейнер не запустился"

step "Открываю порт $SPORT/udp в файрволе сервера"
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "$SPORT/udp" >/dev/null && echo "    ufw: открыт"
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="$SPORT/udp" >/dev/null && firewall-cmd --reload >/dev/null && echo "    firewalld: открыт"
else
  echo "    системный файрвол не активен"
fi

step "Проверяю, что AmneziaWG поднялся"
UP=""
for _ in 1 2 3 4 5 6 7 8; do
  sleep 1
  if docker exec "$NAME" awg show awg0 </dev/null 2>/dev/null | grep -q "listening port: $SPORT"; then UP=1; break; fi
done
if [ -n "$UP" ]; then
  echo "SVPN_SELFTEST ok AmneziaWG слушает UDP-порт $SPORT"
else
  echo "SVPN_SELFTEST fail AmneziaWG не поднялся"
  docker logs --tail 25 "$NAME" </dev/null 2>&1 | sed 's/^/    container: /' || true
fi
if ! docker exec "$NAME" sh -c 'wget -q -T 6 -O /dev/null http://cp.cloudflare.com/generate_204 || curl -s -m 6 -o /dev/null http://cp.cloudflare.com/generate_204' </dev/null >/dev/null 2>&1; then
  echo "SVPN_WARN: из контейнера не открывается интернет — VPN подключится, но сайты работать не будут"
fi

echo "SVPN_RESULT port=$SPORT"
echo "SVPN_RESULT server_public_key=$SPUB"
echo "SVPN_RESULT client_private_key=$CPRIV"
echo "SVPN_RESULT preshared_key=$CPSK"
echo "SVPN_RESULT client_address=$CIP"
echo "SVPN_RESULT server_address=$NET.1"
for P in JC JMIN JMAX S1 S2 H1 H2 H3 H4; do
  echo "SVPN_RESULT $(echo "$P" | tr 'A-Z' 'a-z')=${!P}"
done
echo "SVPN_DONE"
