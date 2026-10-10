#!/usr/bin/env bash
# Диагностика сервера AmneziaWG. Ничего не меняет.
export LC_ALL=C
NAME="splitvpn-awg"
section() { echo; echo "##### $*"; }

section "Сервер"
date -u '+время UTC: %Y-%m-%d %H:%M:%S'
echo "нагрузка: $(cut -d' ' -f1-3 /proc/loadavg), процессоров: $(nproc 2>/dev/null)"
free -m 2>/dev/null | awk 'NR==2 {print "память, МБ: всего " $2 ", доступно " $7}'

section "Контейнер"
docker ps -a --filter "name=$NAME" --format 'состояние: {{.Status}}; порты: {{.Ports}}' 2>&1

section "AmneziaWG (ключи скрыты)"
docker exec "$NAME" awg show awg0 2>&1 | grep -v -i 'private key\|preshared key'

section "Исходящие соединения с сервера"
for URL in https://www.google.com/generate_204 https://2ip.ru http://cp.cloudflare.com/generate_204; do
  R="$(curl -4 -s -o /dev/null -m 8 -w '%{http_code} за %{time_total} с' "$URL" 2>/dev/null)"
  echo "$URL: ${R:-нет ответа}"
done

section "Интернет из контейнера"
if docker exec "$NAME" sh -c 'wget -q -T 6 -O /dev/null http://cp.cloudflare.com/generate_204 || curl -s -m 6 -o /dev/null http://cp.cloudflare.com/generate_204' >/dev/null 2>&1; then
  echo "работает"
else
  echo "НЕ работает"
fi
docker exec "$NAME" iptables -t nat -S POSTROUTING 2>&1 | tail -n 3

section "Файрвол сервера"
if command -v ufw >/dev/null 2>&1; then ufw status 2>/dev/null | head -n 12; else echo "ufw не установлен"; fi

section "Журнал контейнера: последние 30 строк"
docker logs --tail 30 "$NAME" 2>&1 | cut -c1-240
echo
echo "SVPN_DONE"
