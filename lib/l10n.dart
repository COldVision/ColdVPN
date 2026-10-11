import 'dart:io';

/// Язык интерфейса: `ru` или `en`. До чтения настроек — язык системы.
String appLang = systemLang();

String systemLang() =>
    Platform.localeName.toLowerCase().startsWith('ru') ? 'ru' : 'en';

/// Перевод строки интерфейса. Строки в коде написаны по-русски и служат
/// ключами; `{0}`, `{1}`… заменяются на [args]. Строка без перевода
/// остаётся русской.
String tr(String ru, [List<Object?> args = const []]) {
  var text = appLang == 'ru' ? ru : (_en[ru] ?? ru);
  for (var i = 0; i < args.length; i++) {
    text = text.replaceAll('{$i}', '${args[i]}');
  }
  return text;
}

/// Перевод сообщения, пришедшего извне: целиком или только части до
/// двоеточия («ошибка туннеля: …»).
String trLoose(String text) {
  if (appLang == 'ru' || _en.containsKey(text)) return tr(text);
  final colon = text.indexOf(': ');
  if (colon < 0) return text;
  return tr(text.substring(0, colon)) + text.substring(colon);
}

/// Десятичная дробь в привычном для языка виде: запятая или точка.
String decimal(double value, [int digits = 1]) {
  final text = value.toStringAsFixed(digits);
  return appLang == 'ru' ? text.replaceAll('.', ',') : text;
}

/// Скрипт для сервера с сообщениями на выбранном языке.
String localizeScript(String script) {
  if (appLang == 'ru') return script;
  // Длинные фрагменты заменяются первыми: короткие входят в них.
  final keys = _scriptEn.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    script = script.replaceAll(key, _scriptEn[key]!);
  }
  return script;
}

const _scriptEn = <String, String>{
  'нужны права root (войдите под root или пользователем с sudo без пароля)':
      'root rights are needed (sign in as root or as a user with passwordless sudo)',
  'некорректный порт':
      'invalid port',
  'некорректное имя устройства':
      'invalid device name',
  'не удалось установить Docker — проверьте, что с сервера открывается get.docker.com':
      'could not install Docker — check that get.docker.com opens from the server',
  'не удалось установить':
      'could not install',
  'неизвестный менеджер пакетов':
      'unknown package manager',
  'Устанавливаю curl':
      'Installing curl',
  'Останавливаю прежний Xray':
      'Stopping the previous Xray',
  'Устанавливаю Docker (официальный установщик get.docker.com)':
      'Installing Docker (the official get.docker.com installer)',
  'установлен, но не запускается':
      'is installed but does not start',
  'Готовлю образ AmneziaWG':
      'Preparing the AmneziaWG image',
  'не удалось собрать образ — проверьте, что с сервера открывается hub.docker.com':
      'could not build the image — check that hub.docker.com opens from the server',
  'не смог запустить контейнер — перезапускаю systemd и Docker':
      'could not start the container — restarting systemd and Docker',
  'не запускает контейнеры даже после перезапуска. Перезагрузите сервер (в панели хостинга или командой reboot) и повторите установку':
      'does not start containers even after a restart. Reboot the server (in the hosting panel or with the reboot command) and repeat the installation',
  'помогло, продолжаю':
      'that helped, continuing',
  'Генерирую ключи и параметры маскировки сервера':
      'Generating the server keys and obfuscation parameters',
  'не удалось сгенерировать ключи сервера':
      'could not generate the server keys',
  'Использую уже выпущенные ключи сервера':
      'Using the server keys issued earlier',
  'Выпускаю ключи для устройства «':
      'Issuing keys for device «',
  'не удалось сгенерировать ключи устройства':
      'could not generate the device keys',
  'закончились адреса для устройств':
      'no addresses left for devices',
  'Использую уже выпущенные ключи устройства «':
      'Using the keys issued earlier for device «',
  'Записываю конфигурацию':
      'Writing the configuration',
  'Запускаю контейнер (UDP-порт':
      'Starting the container (UDP port',
  'контейнер не запустился':
      'the container did not start',
  'Открываю порт':
      'Opening port',
  'в файрволе сервера':
      'in the server firewall',
  ': открыт':
      ': opened',
  'системный файрвол не активен':
      'the system firewall is not active',
  'Проверяю, что AmneziaWG поднялся':
      'Checking that AmneziaWG came up',
  'слушает UDP-порт':
      'listens on UDP port',
  'AmneziaWG не поднялся':
      'AmneziaWG did not come up',
  'из контейнера не открывается интернет — VPN подключится, но сайты работать не будут':
      'the internet does not open from the container — the VPN will connect, but websites will not work',
  'section "Сервер"':
      'section "Server"',
  'время UTC':
      'UTC time',
  'нагрузка':
      'load',
  'процессоров':
      'CPUs',
  'память, МБ: всего':
      'memory, MB: total',
  'доступно':
      'available',
  'section "Контейнер"':
      'section "Container"',
  'состояние':
      'state',
  'порты':
      'ports',
  'ключи скрыты':
      'keys hidden',
  'Исходящие соединения с сервера':
      'Outgoing connections from the server',
  ' за %{time_total} с':
      ' in %{time_total} s',
  'нет ответа':
      'no reply',
  'Интернет из контейнера':
      'Internet from the container',
  'НЕ работает':
      'does NOT work',
  'echo "работает"':
      'echo "works"',
  'Файрвол сервера':
      'Server firewall',
  'ufw не установлен':
      'ufw is not installed',
  'Журнал контейнера: последние 30 строк':
      'Container log: last 30 lines',
};

const _en = <String, String>{
  'Не удалось сохранить пароль сервера: {0}':
      'Could not save the server password: {0}',
  'Не удалось получить список приложений: {0}':
      'Could not get the list of apps: {0}',
  'Прочее':
      'Other',
  'Не удалось прочитать сохранённые настройки: {0}':
      'Could not read the saved settings: {0}',
  'Мои маршруты':
      'My routes',
  'Основной':
      'Main',
  'Не удалось сохранить настройки: {0}':
      'Could not save the settings: {0}',
  'Это не файл настроек ColdVPN.':
      'This is not a ColdVPN settings file.',
  'Файл настроек повреждён: {0}':
      'The settings file is damaged: {0}',
  'Настройки загружены из файла: серверов {0}, разделов {1}, ресурсов {2}.':
      'Settings loaded from the file: servers {0}, sections {1}, resources {2}.',
  'Настройки сброшены.':
      'Settings were reset.',
  'Обновление уже идёт':
      'An update is already running',
  'Списки: {0}':
      'Lists: {0}',
  'из репозиториев не удалось собрать ни одного сервиса':
      'no service could be built from the repositories',
  'Списки актуальны, изменений нет':
      'The lists are up to date, no changes',
  'Списки обновлены, изменилось сервисов: {0}':
      'Lists updated, services changed: {0}',
  'Не удалось обновить списки сервисов: {0}':
      'Could not update the service lists: {0}',
  'Не удалось обновить списки. Подробности в журнале':
      'Could not update the lists. Details are in the log',
  '--- конец: {0} ---':
      '--- end: {0} ---',
  'Сервер {0}':
      'Server {0}',
  'Нет данных для входа на сервер.':
      'No sign-in data for the server.',
  'На сервере {0} выпущен отдельный ключ «{1}» для другого устройства.':
      'A separate key “{1}” for another device was issued on server {0}.',
  'Новый раздел':
      'New section',
  'Не удалось изменить автозапуск: {0}':
      'Could not change autostart: {0}',
  'Сначала добавьте сервер на вкладке «Сервер».':
      'Add a server on the Server tab first.',
  'Включите хотя бы одно приложение.':
      'Turn on at least one app.',
  'Включите хотя бы один сервис.':
      'Turn on at least one service.',
  'Подключение на этой платформе пока не реализовано.':
      'Connecting is not implemented on this platform yet.',
  'Запустите приложение от имени администратора.':
      'Run the app as administrator.',
  'Маршрутизация по доменам включена, обычный DNS: {0}.':
      'Domain routing is on, regular DNS: {0}.',
  'Маршрутизация по доменам недоступна (не удалось занять {0}:53): {1}. Работают только списки IP.':
      'Domain routing is unavailable (could not bind {0}:53): {1}. Only the IP lists work.',
  'Поднимаю туннель AmneziaWG к {0}:{1} (весь трафик)…':
      'Bringing up the AmneziaWG tunnel to {0}:{1} (all traffic)…',
  'Поднимаю туннель AmneziaWG к {0}:{1} (диапазонов: {2}, адресов по доменам: {3})…':
      'Bringing up the AmneziaWG tunnel to {0}:{1} (ranges: {2}, addresses by domain: {3})…',
  'журнал клиента AmneziaWG':
      'AmneziaWG client log',
  'Сервер не ответил на рукопожатие. Проверьте, что UDP-порт {0} открыт в файрволе хостинга. Подробности в журнале.':
      'The server did not respond to the handshake. Check that UDP port {0} is open in the hosting firewall. Details are in the log.',
  'Рукопожатие с сервером выполнено.':
      'Handshake with the server completed.',
  'DNS-посредник не смог занять {0}:53, остаётся прежний адрес.':
      'The DNS proxy could not bind {0}:53, the previous address stays.',
  'Туннель поднят, но проверочный запрос через него не прошёл. Сайты могут не открываться — запустите диагностику в журнале.':
      'The tunnel is up, but the probe request through it failed. Websites may not open — run diagnostics on the Log tab.',
  'Подключено. Сайты видят вас под адресом {0}.':
      'Connected. Websites see you at {0}.',
  'Разрешите приложению создавать VPN-подключение и попробуйте снова.':
      'Allow the app to create a VPN connection and try again.',
  'Поднимаю туннель AmneziaWG к {0}:{1} (приложений: {2})…':
      'Bringing up the AmneziaWG tunnel to {0}:{1} (apps: {2})…',
  'Поднимаю туннель AmneziaWG к {0}:{1} (диапазонов: {2})…':
      'Bringing up the AmneziaWG tunnel to {0}:{1} (ranges: {2})…',
  'Выбранные приложения не установлены на этом телефоне.':
      'The selected apps are not installed on this phone.',
  'Сервер не ответил на рукопожатие. Проверьте, что сервер включён и UDP-порт {0} открыт в файрволе хостинга.':
      'The server did not respond to the handshake. Check that the server is on and UDP port {0} is open in the hosting firewall.',
  'Подключено. Через VPN идут выбранные приложения.':
      'Connected. The selected apps go through the VPN.',
  'Не удалось поднять туннель: {0}':
      'Could not bring up the tunnel: {0}',
  'По домену {0} в туннель добавлено: {1}':
      'By domain {0} added to the tunnel: {1}',
  'Дальше добавления по доменам в журнал не пишутся.':
      'Further additions by domain are not written to the log.',
  'Не удалось добавить маршруты: {0}':
      'Could not add routes: {0}',
  'DNS-посредник остановлен: запросов {0}, по спискам сервисов {1}, без ответа {2}, с опозданием через туннель {3}; адресов добавлено по доменам: {4}.':
      'DNS proxy stopped: requests {0}, by service lists {1}, unanswered {2}, late through the tunnel {3}; addresses added by domain: {4}.',
  'неожиданный ответ {0}':
      'unexpected reply {0}',
  'Проверка туннеля не прошла за {0} попыток: {1}':
      'The tunnel check failed after {0} attempts: {1}',
  'VPN отключён системой.':
      'The VPN was turned off by the system.',
  'Найденные по доменам адреса забыты.':
      'Addresses found by domain were forgotten.',
  'На Android отдельного журнала туннеля нет.':
      'There is no separate tunnel log on Android.',
  'Туннель сейчас не поднят.':
      'The tunnel is not up right now.',
  'Туннель: последнее рукопожатие {0}, получено {1} байт, отправлено {2} байт.':
      'Tunnel: last handshake {0}, received {1} bytes, sent {2} bytes.',
  '{0} Мбит/с':
      '{0} Mbit/s',
  'нет сервера':
      'no server',
  'узел измерения ответил кодом {0}':
      'the measurement host replied with code {0}',
  'слишком мало данных':
      'too little data',
  'Клиент AmneziaWG':
      'AmneziaWG client',
  'Связь с сервером':
      'Connection to the server',
  'Трафик через туннель':
      'Traffic through the tunnel',
  'Маршруты':
      'Routes',
  'Включённые сервисы':
      'Services turned on',
  'Скорость':
      'Speed',
  'Сервер изнутри':
      'Server from the inside',
  'проверяю…':
      'checking…',
  'VPN выключен — включите его и повторите':
      'The VPN is off — turn it on and run again',
  'встроен в приложение':
      'built into the app',
  'ещё не установлен — поставится при первом включении VPN':
      'not installed yet — it is installed when the VPN is first turned on',
  'установлен, но служба туннеля не запущена':
      'installed, but the tunnel service is not running',
  'Выключите и снова включите VPN.':
      'Turn the VPN off and on again.',
  'установлен, служба туннеля запущена':
      'installed, the tunnel service is running',
  'установлен':
      'installed',
  'рукопожатия с сервером не было':
      'there was no handshake with the server',
  'Проверьте, что сервер включён и его UDP-порт открыт в файрволе хостинга.':
      'Check that the server is on and its UDP port is open in the hosting firewall.',
  'последнее рукопожатие {0} с назад — связь могла пропасть':
      'last handshake {0} s ago — the connection may be lost',
  'Сервер давно не отвечал. Проверьте, что он работает.':
      'The server has not responded for a long time. Check that it is running.',
  'рукопожатие {0} с назад':
      'handshake {0} s ago',
  'в режиме «Приложения» само ColdVPN идёт мимо VPN':
      'in Apps mode ColdVPN itself goes outside the VPN',
  'сайты видят адрес {0} (у сервера другой исходящий адрес)':
      'websites see the address {0} (the server has a different outgoing address)',
  'сайты видят адрес сервера {0}':
      'websites see the server address {0}',
  'запрос через туннель не прошёл':
      'the request through the tunnel failed',
  'Туннель поднят, но трафик не проходит. Запустите проверку «Сервер изнутри» — для неё нужен пароль от сервера.':
      'The tunnel is up, but traffic does not pass. Run the “Server from the inside” check — it needs the server password.',
  'на Android маршрутов по доменам нет — работают списки IP':
      'there are no routes by domain on Android — the IP lists work',
  'маршруты по доменам выключены — работают только списки IP':
      'routes by domain are off — only the IP lists work',
  'у включённых сервисов нет доменов':
      'the services turned on have no domains',
  'имя {0} найдено за {1} мс':
      'name {0} found in {1} ms',
  'DNS отвечает медленно — сайты могут открываться с задержкой. Попробуйте другой DNS в настройках.':
      'DNS responds slowly — websites may open with a delay. Try another DNS in Settings.',
  'имя {0} не найдено':
      'name {0} not found',
  'DNS не отвечает. Попробуйте другой DNS в настройках.':
      'DNS does not respond. Try another DNS in Settings.',
  'не удалось прочитать маршруты туннеля':
      'could not read the tunnel routes',
  'в туннеле {0} из {1} адресов и диапазонов':
      '{0} of {1} addresses and ranges are in the tunnel',
  'Часть маршрутов потерялась. Выключите и включите VPN.':
      'Some routes were lost. Turn the VPN off and on.',
  'весь трафик направлен в туннель':
      'all traffic is sent into the tunnel',
  '{0} диапазонов и {1} адресов по доменам — все на месте':
      '{0} ranges and {1} addresses by domain — all in place',
  'в режиме «Приложения» проверьте нужное приложение сами':
      'in Apps mode check the app you need yourself',
  'нет сервисов с доменами для проверки':
      'no services with domains to check',
  'отвечают все: {0}':
      'all respond: {0}',
  '{0} из {1} отвечают · не ответили: {2}':
      '{0} of {1} respond · no reply from: {2}',
  '{0}: нет ответа через туннель. Чаще всего сервис блокирует адрес сервера — попробуйте другой сервер.':
      '{0}: no reply through the tunnel. Most often the service blocks the server address — try another server.',
  'на Android замер работает только в режиме «Весь трафик»':
      'on Android the measurement works only in All traffic mode',
  '↓ {0} · ↑ {1} через туннель':
      '↓ {0} · ↑ {1} through the tunnel',
  '↓ {0} · ↑ {1}, но замер, похоже, прошёл мимо туннеля':
      '↓ {0} · ↑ {1}, but the measurement seems to have bypassed the tunnel',
  'замерить не удалось: {0}':
      'could not measure: {0}',
  'нужен пароль от сервера — введите его в «Поделиться» у этого сервера':
      'the server password is needed — enter it under Share for this server',
  'диагностика сервера':
      'server diagnostics',
  'отчёт получен и записан во вкладку «Подробно»':
      'the report was received and written to the Details tab',
  'не удалось подключиться: {0}':
      'could not connect: {0}',
  'Диагностика прервалась: {0}':
      'Diagnostics were interrupted: {0}',
  'VPN выключен':
      'VPN is off',
  'Включите VPN на вкладке «Сервисы» и повторите проверку — тогда проверятся связь, DNS, маршруты и сервисы.':
      'Turn on the VPN on the Services tab and run the check again — then the connection, DNS, routes and services are checked.',
  'Есть проблемы: {0}':
      'There are problems: {0}',
  'VPN работает, замечаний: {0}':
      'The VPN works, warnings: {0}',
  'Всё в порядке':
      'All good',
  'VPN работает, включённые сервисы отвечают.':
      'The VPN works, the services turned on respond.',
  'Диагностика завершена: в порядке {0}, замечаний {1}, ошибок {2}, пропущено {3}.':
      'Diagnostics finished: OK {0}, warnings {1}, errors {2}, skipped {3}.',
  'Диагностика ColdVPN: {0}':
      'ColdVPN diagnostics: {0}',
  'В порядке':
      'OK',
  'Замечание':
      'Warning',
  'Ошибка':
      'Error',
  'Пропущено':
      'Skipped',
  'Идёт':
      'Running',
  'В очереди':
      'Queued',
  'Скачиваю клиент AmneziaWG {0} (около 3,5 МБ)…':
      'Downloading the AmneziaWG client {0} (about 3.5 MB)…',
  'GitHub ответил кодом {0}':
      'GitHub replied with code {0}',
  'Не удалось скачать клиент AmneziaWG: {0}\nЕго можно установить вручную: {1}':
      'Could not download the AmneziaWG client: {0}\nYou can install it by hand: {1}',
  'Устанавливаю клиент AmneziaWG…':
      'Installing the AmneziaWG client…',
  'Установка клиента AmneziaWG не удалась (код {0}). Установите его вручную: {1}':
      'Installing the AmneziaWG client failed (code {0}). Install it by hand: {1}',
  'Клиент AmneziaWG установлен.':
      'The AmneziaWG client is installed.',
  'Служба туннеля не запустилась (код {0}): {1}':
      'The tunnel service did not start (code {0}): {1}',
  'Клиент AmneziaWG ещё не установлен: он ставится при первом нажатии «Подключить».':
      'The AmneziaWG client is not installed yet: it is installed on the first tap of Connect.',
  'Не удалось прочитать журнал клиента: {0}':
      'Could not read the client log: {0}',
  'ИИ':
      'AI',
  'Общение':
      'Messaging',
  'Соцсети':
      'Social',
  'Развлечения':
      'Entertainment',
  'Игры':
      'Games',
  'Системные':
      'System',
  'Значок в трее недоступен: {0}':
      'The tray icon is unavailable: {0}',
  'Открыть ColdVPN':
      'Open ColdVPN',
  'Включить VPN':
      'Turn VPN on',
  'Выключить VPN':
      'Turn VPN off',
  'Выход':
      'Quit',
  'ColdVPN — включён':
      'ColdVPN — on',
  'DNS по TCP недоступен: {0}':
      'DNS over TCP is unavailable: {0}',
  'DNS: {0} — адресов {1}, через туннель {2}, напрямую {3}, {4} мс, запрос {5}':
      'DNS: {0} — addresses {1}, through the tunnel {2}, direct {3}, {4} ms, request {5}',
  'нет списка доменов «{0}»':
      'there is no domain list “{0}”',
  '{0}: в репозитории больше нет «{1}»':
      '{0}: “{1}” is no longer in the repository',
  '{0}: не найдено ни адресов, ни доменов':
      '{0}: neither addresses nor domains were found',
  'GitHub ответил кодом {0} для {1}':
      'GitHub replied with code {0} for {1}',
  'архив {0} неожиданно большой':
      'the archive {0} is unexpectedly large',
  'Не удалось настроить окно и трей: {0}':
      'Could not set up the window and tray: {0}',
  'Сервер':
      'Server',
  'Раздел':
      'Section',
  'Ресурс':
      'Resource',
  'в очереди':
      'queued',
  'пропущено: число в адресе больше 255':
      'skipped: a number in the address is above 255',
  'один адрес':
      'single address',
  'пропущено: маска должна быть от 0 до 32':
      'skipped: the mask must be between 0 and 32',
  'пропущено: слишком широкий диапазон, минимум /5':
      'skipped: the range is too wide, /5 at most',
  '{0} адресов':
      '{0} addresses',
  'пропущено: IPv6 пока не поддерживается':
      'skipped: IPv6 is not supported yet',
  'пропущено: не похоже на домен или IP':
      'skipped: not a domain or an IP',
  'домен из ссылки, с поддоменами':
      'domain from a link, with subdomains',
  'с поддоменами':
      'with subdomains',
  'повтор — будет пропущен':
      'duplicate — will be skipped',
  'защита данных Windows вернула ошибку: {0}':
      'Windows data protection returned an error: {0}',
  'Подключаюсь к {0}:{1}…':
      'Connecting to {0}:{1}…',
  'Сервер не отвечает по SSH ({0}:{1}): {2}':
      'The server does not respond over SSH ({0}:{1}): {2}',
  'Не удалось прочитать SSH-ключ: {0}':
      'Could not read the SSH key: {0}',
  'Сервер не принял логин или пароль: {0}':
      'The server did not accept the login or password: {0}',
  'Вход выполнен.':
      'Signed in.',
  'Ошибка: {0}':
      'Error: {0}',
  'Внимание: {0}':
      'Warning: {0}',
  'Самопроверка на сервере пройдена {0}.':
      'The self-test on the server passed {0}.',
  'Самопроверка на сервере НЕ пройдена {0}.':
      'The self-test on the server NOT passed {0}.',
  'Установка прервалась, подробности в журнале выше.':
      'The installation was interrupted, details are in the log above.',
  'Установка прервалась. Пользователю {0} нужен sudo без пароля — проще всего войти под root.':
      'The installation was interrupted. User {0} needs passwordless sudo — the easiest way is to sign in as root.',
  'Сервер не вернул данные подключения.':
      'The server did not return the connection data.',
  'Готово: AmneziaWG установлен и запущен.':
      'Done: AmneziaWG is installed and running.',
  'Укажите адрес сервера.':
      'Enter the server address.',
  'Порт SSH — число от 1 до 65535.':
      'The SSH port is a number from 1 to 65535.',
  'Укажите логин.':
      'Enter the login.',
  'Укажите пароль или SSH-ключ.':
      'Enter the password or an SSH key.',
  'UDP-порт VPN — число от 1 до 65535 или пусто.':
      'The VPN UDP port is a number from 1 to 65535, or empty.',
  'Сервер {0} настроен, UDP-порт {1}.':
      'Server {0} is configured, UDP port {1}.',
  'Сервер сохранён, но при установке были предупреждения — они в журнале ниже.':
      'The server was saved, but there were warnings during installation — they are in the log below.',
  'Сервер настроен и добавлен':
      'The server is configured and added',
  'Установка на VPS':
      'Install on a VPS',
  'Приложение само поставит AmneziaWG':
      'The app installs AmneziaWG by itself',
  'IP-адрес сервера':
      'Server IP address',
  'Порт SSH':
      'SSH port',
  'Логин':
      'Login',
  'Пароль':
      'Password',
  'Запомнить пароль':
      'Remember the password',
  'Чтобы потом выпускать ключи для других устройств. Хранится на этом компьютере в зашифрованном виде':
      'To issue keys for other devices later. Stored on this computer in encrypted form',
  'Скрыть дополнительное':
      'Hide advanced',
  'Дополнительно':
      'Advanced',
  'Приватный SSH-ключ вместо пароля':
      'Private SSH key instead of a password',
  'UDP-порт VPN':
      'VPN UDP port',
  'Пусто — сервер выберет случайный и запомнит':
      'Empty — the server picks a random one and remembers it',
  'Выпустить новые ключи':
      'Issue new keys',
  'Уже подключённые устройства перестанут работать':
      'Devices already connected will stop working',
  'Готово':
      'Done',
  'Устанавливаю…':
      'Installing…',
  'Установить AmneziaWG':
      'Install AmneziaWG',
  'Журнал сохранён':
      'Log saved',
  'Текст':
      'Text',
  'Не удалось сохранить журнал: {0}':
      'Could not save the log: {0}',
  'Журнал':
      'Log',
  'События':
      'Events',
  'Подробно':
      'Details',
  'Запустить диагностику':
      'Run diagnostics',
  'Проверит клиент, связь, DNS, маршруты, сервисы и сервер.':
      'Checks the client, connection, DNS, routes, services and server.',
  'Событий пока нет. Они появятся, когда вы включите VPN.':
      'No events yet. They appear when you turn on the VPN.',
  'Включён режим «Весь трафик»: через VPN идёт всё, списки ниже сейчас не используются.':
      'All traffic mode is on: everything goes through the VPN, the lists below are not used right now.',
  'сервисов':
      'services',
  'диапазонов':
      'ranges',
  'по доменам':
      'by domain',
  'По сервисам':
      'By service',
  'Ни один сервис не включён.':
      'No service is turned on.',
  'Первое число — диапазоны из списка, второе — адреса, найденные по доменам.':
      'The first number is ranges from the list, the second is addresses found by domain.',
  'Найдено по доменам':
      'Found by domain',
  'Пока ничего: адреса появляются, когда программы обращаются к сервисам при включённом VPN.':
      'Nothing yet: addresses appear when programs contact the services while the VPN is on.',
  'Забыть найденные адреса':
      'Forget found addresses',
  'Найденные адреса забыты':
      'Found addresses forgotten',
  'Сохранено адресов: {0}. Приложение найдёт их заново, когда сервисы к ним обратятся.':
      'Addresses saved: {0}. The app will find them again when the services request them.',
  'Журнал пуст.':
      'The log is empty.',
  'Журнал туннеля':
      'Tunnel log',
  'Поделиться журналом':
      'Share the log',
  'Сохранить в файл':
      'Save to a file',
  'Пароли в журнал не попадают.':
      'Passwords never get into the log.',
  'Диагностика':
      'Diagnostics',
  'Готово: {0}':
      'Done: {0}',
  'Шаг {0} из {1}':
      'Step {0} of {1}',
  'Ход проверки':
      'Progress',
  '{0} из {1}':
      '{0} of {1}',
  'Повторить':
      'Run again',
  'Скопировать отчёт':
      'Copy report',
  'Отчёт скопирован':
      'Report copied',
  'Наведите камеру на QR-код':
      'Point the camera at the QR code',
  'Закрыть':
      'Close',
  'Код можно показать на экране компьютера: «Сервер» → три точки → «Поделиться».':
      'The code can be shown on the computer screen: Server → three dots → Share.',
  'домен':
      'domain',
  'домена':
      'domains',
  'доменов':
      'domains',
  'диапазон':
      'range',
  'диапазона':
      'ranges',
  'адрес':
      'address',
  'адреса':
      'addresses',
  'адресов':
      'addresses',
  'ошибок: {0}':
      'errors: {0}',
  'Укажите название ресурса':
      'Enter a name for the resource',
  'Выберите раздел':
      'Choose a section',
  'Нужен хотя бы один правильный домен или адрес':
      'At least one valid domain or address is needed',
  'Строки с ошибкой будут пропущены: {0}':
      'Lines with errors will be skipped: {0}',
  'Изменить ресурс':
      'Edit resource',
  'Новый ресурс':
      'New resource',
  'Домены и адреса, которые пойдут через VPN':
      'Domains and addresses that go through the VPN',
  'Название':
      'Name',
  'Например, Рабочий портал':
      'For example, Work portal',
  'Домены и IP-адреса, по одному в строке':
      'Domains and IP addresses, one per line',
  'Вставить':
      'Paste',
  'Домен добавляется вместе с поддоменами. Можно вставить ссылку целиком — из неё возьмётся домен.':
      'A domain is added together with its subdomains. You can paste a whole link — the domain is taken from it.',
  'Проверка':
      'Check',
  'Найти в списке':
      'Find in the list',
  'Часть домена или адреса':
      'Part of a domain or address',
  'Список длинный: ниже показаны только строки с ошибками. Найденную строку можно убрать крестиком.':
      'The list is long: only lines with errors are shown below. A found line can be removed with the cross.',
  'Ничего не найдено':
      'Nothing found',
  'Найдено {0}, показаны первые {1}':
      'Found {0}, the first {1} are shown',
  'Введите хотя бы один домен или адрес':
      'Enter at least one domain or address',
  'Включить сразу':
      'Turn on right away',
  'Ресурс пойдёт через VPN после добавления':
      'The resource goes through the VPN once added',
  'Отмена':
      'Cancel',
  'Сохранить':
      'Save',
  'Добавить':
      'Add',
  'Домен':
      'Domain',
  'Диапазон':
      'Range',
  'Адрес':
      'Address',
  'Повтор':
      'Duplicate',
  'Убрать «{0}» из списка':
      'Remove “{0}” from the list',
  'Раздел «{0}»':
      'Section “{0}”',
  'Изменить':
      'Edit',
  'Название, раздел, домены и адреса':
      'Name, section, domains and addresses',
  'Переместить в другой раздел':
      'Move to another section',
  'Сейчас: {0}':
      'Now in: {0}',
  'Удалить ресурс':
      'Delete resource',
  'Удалить ресурс «{0}»?':
      'Delete the resource “{0}”?',
  'Его домены и адреса перестанут идти через VPN.':
      'Its domains and addresses will stop going through the VPN.',
  'Переместить':
      'Move',
  'Раздел · ресурсов: {0}':
      'Section · resources: {0}',
  'Изменить название и значок':
      'Change the name and icon',
  'Удалить раздел, ресурсы перенести':
      'Delete section, move its resources',
  'Выберите, куда переедут ресурсы':
      'Choose where the resources go',
  'Удалить раздел вместе с ресурсами':
      'Delete section with its resources',
  'Удалить раздел':
      'Delete section',
  'Удалить раздел «{0}»?':
      'Delete the section “{0}”?',
  'Вместе с ним удалятся {0}. Вернуть начальный набор можно в настройках.':
      '{0} will be deleted with it. The default set can be restored in Settings.',
  'Раздел пуст, больше ничего не удалится.':
      'The section is empty, nothing else will be deleted.',
  'Куда перенести ресурсы?':
      'Where should the resources go?',
  'Раздел «{0}» будет удалён':
      'Section “{0}” will be deleted',
  'Новый раздел…':
      'New section…',
  'Не удалять':
      'Keep',
  'Удалить':
      'Delete',
  'Изменить раздел':
      'Edit section',
  'Появится в конце списка, его можно перетащить':
      'It appears at the end of the list and can be dragged',
  'Название раздела':
      'Section name',
  'Например, Игры':
      'For example, Games',
  'Значок':
      'Icon',
  'Создать':
      'Create',
  'Конфиг AmneziaWG':
      'AmneziaWG config',
  'Картинка с QR-кодом':
      'Picture with a QR code',
  'Картинка PNG':
      'PNG picture',
  'Не похоже на конфиг AmneziaWG: нужны секции [Interface] (PrivateKey, Address) и [Peer] (PublicKey, Endpoint).':
      'This does not look like an AmneziaWG config: the sections [Interface] (PrivateKey, Address) and [Peer] (PublicKey, Endpoint) are needed.',
  'Импортирован конфиг сервера {0}:{1} из файла.':
      'Imported the config of server {0}:{1} from a file.',
  'Сервер «{0}» добавлен':
      'Server “{0}” added',
  'Не удалось прочитать файл: {0}':
      'Could not read the file: {0}',
  'Импорт из QR-кода':
      'Import from a QR code',
  'Сканировать камерой':
      'Scan with the camera',
  'Наведите телефон на код':
      'Point the phone at the code',
  'Выбрать картинку':
      'Choose a picture',
  'Снимок экрана или фото с кодом':
      'A screenshot or photo with the code',
  'На картинке не удалось найти QR-код.':
      'Could not find a QR code in the picture.',
  'Не удалось прочитать картинку: {0}':
      'Could not read the picture: {0}',
  'В QR-коде не конфиг AmneziaWG.':
      'The QR code is not an AmneziaWG config.',
  'Импортирован конфиг сервера {0}:{1} из QR-кода.':
      'Imported the config of server {0}:{1} from a QR code.',
  'Не удалось добавить сервер: {0}':
      'Could not add the server: {0}',
  'Сервера пока нет':
      'No server yet',
  'Арендуйте VPS и установите на него VPN прямо отсюда или добавьте готовый конфиг AmneziaWG.':
      'Rent a VPS and install the VPN on it right from here, or add a ready AmneziaWG config.',
  'Мои серверы':
      'My servers',
  'Добавить сервер':
      'Add a server',
  'Установить на свой VPS':
      'Install on your own VPS',
  'Нужны адрес сервера, логин и пароль':
      'The server address, login and password are needed',
  'Импорт из файла .conf':
      'Import a .conf file',
  'Готовый конфиг AmneziaWG':
      'A ready AmneziaWG config',
  'Камерой или с картинки':
      'With the camera or from a picture',
  'Картинка или снимок экрана с кодом':
      'A picture or screenshot with the code',
  'Вставить конфиг текстом':
      'Paste a config as text',
  'Например, из сообщения':
      'For example, from a message',
  'Подключён':
      'Connected',
  'Не подключён':
      'Not connected',
  'Место не определено':
      'Location unknown',
  'Порт':
      'Port',
  'Связь':
      'Link',
  'нет':
      'none',
  '{0} с назад':
      '{0} s ago',
  'Трафик':
      'Traffic',
  'Действия с сервером «{0}»':
      'Actions for server “{0}”',
  'Добавлен сервер {0}:{1} из вставленного текста.':
      'Added server {0}:{1} from pasted text.',
  'Вставить конфиг':
      'Paste a config',
  'Текст конфига AmneziaWG':
      'AmneziaWG config text',
  'Текст конфига':
      'Config text',
  'Вставить из буфера':
      'Paste from clipboard',
  'Маршруты из конфига не используются: через VPN пойдёт то, что выбрано на вкладке «Сервисы».':
      'Routes from the config are not used: what goes through the VPN is chosen on the Services tab.',
  'Файл сохранён':
      'File saved',
  'Не удалось сохранить файл: {0}':
      'Could not save the file: {0}',
  'не удалось получить картинку':
      'could not get the picture',
  'QR-код сохранён':
      'QR code saved',
  'Не удалось сохранить QR-код: {0}':
      'Could not save the QR code: {0}',
  'Укажите логин, пароль и порт SSH.':
      'Enter the login, password and SSH port.',
  'Не удалось выпустить ключ: {0}':
      'Could not issue the key: {0}',
  'Назад':
      'Back',
  'Изменить название и место':
      'Change the name and location',
  'Поделиться':
      'Share',
  'QR-кодом, файлом .conf или текстом':
      'As a QR code, a .conf file or text',
  'Забыть пароль сервера':
      'Forget the server password',
  'Сейчас он сохранён на этом компьютере':
      'It is saved on this computer now',
  'Сейчас приложение его помнит':
      'The app remembers it now',
  'Пароль сервера забыт':
      'Server password forgotten',
  'Удалить сервер':
      'Delete server',
  'Изменить сервер':
      'Edit server',
  'Страна':
      'Country',
  'Город':
      'City',
  'Место определяется по адресу сервера автоматически. Если оно определилось неверно, поправьте его здесь.':
      'The location is detected from the server address automatically. If it is wrong, correct it here.',
  'Это конфиг вашего устройства. Два устройства не могут пользоваться им одновременно: связь будет рваться у обоих. В конфиге есть ключ доступа — передавайте его только тем, кому доверяете.':
      'This is the config of your device. Two devices cannot use it at the same time: the connection will break on both. The config contains an access key — share it only with people you trust.',
  'Это отдельный ключ: им можно пользоваться одновременно с этим устройством. Передавайте его только тем, кому доверяете.':
      'This is a separate key: it can be used at the same time as this device. Share it only with people you trust.',
  'Пароль от сервера {0}':
      'Password for server {0}',
  'Приложение запомнит его и сохранит на этом компьютере в зашифрованном виде':
      'The app will remember it and store it on this computer in encrypted form',
  'Приложение запомнит его до закрытия':
      'The app will remember it until it is closed',
  'Выпускаю ключ…':
      'Issuing the key…',
  'Сохранить и выпустить ключ':
      'Save and issue the key',
  'Выпустить отдельный ключ':
      'Issue a separate key',
  'Для другого устройства или друга. Связь с сервером прервётся на несколько секунд.':
      'For another device or a friend. The connection to the server will drop for a few seconds.',
  'QR-код с конфигом сервера':
      'QR code with the server config',
  'Не удалось построить QR-код':
      'Could not build the QR code',
  'Конфиг слишком длинный для QR-кода — передайте его файлом или текстом.':
      'The config is too long for a QR code — share it as a file or text.',
  'Сохранить QR-код':
      'Save QR code',
  'Сохранить .conf':
      'Save .conf',
  'Скопировать текстом':
      'Copy as text',
  'Конфиг скопирован':
      'Config copied',
  'Удалить сервер «{0}» из приложения?':
      'Remove server “{0}” from the app?',
  'Сам сервер останется настроенным. Чтобы вернуть его в приложение, понадобится конфиг или повторная установка.':
      'The server itself stays configured. To bring it back into the app you will need a config or a new installation.',
  'Приложение запущено без прав администратора — подключение не сработает. Закройте его и запустите от имени администратора.':
      'The app is running without administrator rights — connecting will not work. Close it and run it as administrator.',
  'Сервисы':
      'Services',
  'Приложения':
      'Apps',
  'Весь трафик':
      'All traffic',
  'Весь трафик через VPN':
      'All traffic through VPN',
  'Переключатели сервисов заблокированы':
      'Service switches are locked',
  'Сейчас — только включённые сервисы':
      'Now: only the services turned on',
  'Приложения, которые идут через VPN целиком':
      'Apps that go through the VPN entirely',
  'Поиск по названию':
      'Search by name',
  'Не удалось получить список приложений.':
      'Could not get the list of apps.',
  'Ничего не найдено.':
      'Nothing found.',
  'Подключаюсь…':
      'Connecting…',
  'Нажмите для отмены':
      'Tap to cancel',
  'VPN включён':
      'VPN is on',
  'Приложений: {0}':
      'Apps: {0}',
  'В туннеле: {0}':
      'In tunnel: {0}',
  'Добавьте сервер':
      'Add a server',
  'Включите приложения ниже':
      'Turn on apps below',
  'Включите сервисы ниже':
      'Turn on services below',
  'Нажмите для включения':
      'Tap to connect',
  'Пока пусто':
      'Empty for now',
  'Включено {0} из {1}':
      'On: {0} of {1}',
  'Перетащите, чтобы изменить порядок':
      'Drag to reorder',
  'Переместить раздел «{0}»':
      'Move section “{0}”',
  'Действия с разделом «{0}»':
      'Actions for section “{0}”',
  'В разделе пока ничего нет.':
      'Nothing in this section yet.',
  'Добавить ресурс':
      'Add a resource',
  'Выключить все':
      'Turn all off',
  'Включить все':
      'Turn all on',
  '{0} IP · {1} доменов':
      '{0} IP · {1} domains',
  'Действия с ресурсом «{0}»':
      'Actions for resource “{0}”',
  'Настройки ColdVPN':
      'ColdVPN settings',
  'Настройки сохранены':
      'Settings saved',
  'Настройки загружены':
      'Settings loaded',
  'Настройки сброшены':
      'Settings reset',
  'Загружаю списки с GitHub…':
      'Loading the lists from GitHub…',
  'Встроены в эту версию приложения':
      'Built into this version of the app',
  'Обновлены {0}.{1}.{2} в {3}:{4}':
      'Updated {0}.{1}.{2} at {3}:{4}',
  'Ссылка скопирована':
      'Link copied',
  'Настройки':
      'Settings',
  'Запуск':
      'Startup',
  'Запускать вместе с системой':
      'Start with the system',
  'При входе в Windows, сразу в трей':
      'At Windows sign-in, straight to the tray',
  'Подключаться при запуске':
      'Connect on startup',
  'При открытии приложения, если VPN был включён':
      'When the app opens, if the VPN was on',
  'Если в прошлый раз VPN был включён':
      'If the VPN was on last time',
  'Сворачивать в трей при закрытии':
      'Minimize to tray on close',
  'VPN продолжит работать в фоне. Выход — через значок в трее':
      'The VPN keeps working in the background. Quit through the tray icon',
  'Маршрутизация':
      'Routing',
  'Маршруты по доменам':
      'Routes by domain',
  'Добавлять адреса сервисов на лету через DNS':
      'Add service addresses on the fly through DNS',
  'Только IPv4 для сервисов из списка':
      'IPv4 only for listed services',
  'Чтобы трафик не ушёл по IPv6 мимо VPN':
      'So that traffic does not bypass the VPN over IPv6',
  'DNS для сервисов в туннеле':
      'DNS for services in the tunnel',
  'Свой':
      'Custom',
  'Адрес своего DNS-сервера':
      'Address of your DNS server',
  'Нужен адрес IPv4, например 9.9.9.9. Пока используется {0}.':
      'An IPv4 address is needed, for example 9.9.9.9. For now {0} is used.',
  'Через него узнаются адреса только включённых сервисов. Остальные сайты используют обычный DNS вашей сети.':
      'Only the addresses of services turned on are looked up through it. Other websites use the regular DNS of your network.',
  'Списки сервисов':
      'Service lists',
  'Сервисов: {0} · доменов: {1}':
      'Services: {0} · domains: {1}',
  'Идёт…':
      'Running…',
  'Обновить':
      'Update',
  'Обновлять автоматически':
      'Update automatically',
  'Раз в неделю, при запуске приложения':
      'Once a week, when the app starts',
  'Перенос и сброс':
      'Transfer and reset',
  'Сохранить настройки в файл':
      'Save settings to a file',
  'Серверы, разделы и ресурсы со всеми правками. В файле есть ключи серверов — храните его как пароль':
      'Servers, sections and resources with all edits. The file contains server keys — keep it like a password',
  'Загрузить настройки из файла':
      'Load settings from a file',
  'Текущие настройки будут заменены':
      'Current settings will be replaced',
  'Восстановить стандартные разделы':
      'Restore default sections',
  'Вернуть удалённые разделы и ресурсы. Ваши правки и свои ресурсы останутся':
      'Bring back deleted sections and resources. Your edits and your own resources stay',
  'Стандартные разделы возвращены':
      'Default sections restored',
  'Сбросить все настройки':
      'Reset all settings',
  'Вернуть приложение к начальному состоянию':
      'Return the app to its initial state',
  'Сбросить все настройки?':
      'Reset all settings?',
  'Удалятся серверы, свои разделы и ресурсы, правки в списках. Сами серверы останутся настроенными — их можно будет добавить снова.':
      'Servers, your sections and resources, and list edits will be removed. The servers themselves stay configured — you can add them again.',
  'Не сбрасывать':
      'Keep',
  'Сбросить':
      'Reset',
  'О программе':
      'About',
  'Исходный код':
      'Source code',
  'Выбрать сервер':
      'Choose a server',
  'Добавить или изменить серверы':
      'Add or edit servers',
  'Нет сервера':
      'No server',
  '{0} Кбит/с':
      '{0} Kbit/s',
  '{0} ГБ':
      '{0} GB',
  '{0} МБ':
      '{0} MB',
  '{0} КБ':
      '{0} KB',
  '{0}, заблокировано':
      '{0}, locked',
  'Страна неизвестна':
      'Country unknown',
  'не было':
      'none',
  'нет ответа':
      'no reply',
  'ответ':
      'reply',
  'шаг':
      'step',
  'шага':
      'steps',
  'шагов':
      'steps',
  'ресурс':
      'resource',
  'ресурса':
      'resources',
  'ресурсов':
      'resources',
  'нет разрешения на VPN-подключение':
      'no permission for a VPN connection',
  'не удалось запустить службу VPN':
      'could not start the VPN service',
  'Android не дал создать туннель (возможно, включён другой VPN с «Постоянной VPN»)':
      'Android did not allow creating the tunnel (another VPN with Always-on VPN may be enabled)',
  'не удалось узнать адрес сервера':
      'could not resolve the server address',
  'ошибка туннеля':
      'tunnel error',
  'конфиг не принят':
      'the config was rejected',
  'Язык':
      'Language',
  'Перетащите на нужное место или на другой раздел':
      'Drag to a new place or onto another section',
};
