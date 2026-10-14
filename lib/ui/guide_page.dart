import 'package:flutter/material.dart';

import '../l10n.dart';
import 'theme.dart';

/// Инструкция ко всем функциям приложения: разделы раскрываются по нажатию.
/// Текст хранится здесь же на обоих языках — это не строки интерфейса, а
/// длинный документ, поэтому он не идёт через `tr`.
class GuidePage extends StatefulWidget {
  const GuidePage({super.key});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  int? _open = 0;

  @override
  Widget build(BuildContext context) {
    final sections = appLang == 'ru' ? _ru : _en;
    return Scaffold(
      backgroundColor: C.bg,
      body: CvBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 14, 18, 4),
                      child: Row(
                        children: [
                          CvIconButton(
                            icon: Icons.arrow_back,
                            tooltip: tr('Назад'),
                            framed: false,
                            onTap: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                appLang == 'ru' ? 'Инструкция' : 'User guide',
                                style: tx(22, w: w700, c: C.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
                            child: Text(
                              appLang == 'ru'
                                  ? 'Нажмите на раздел, чтобы его раскрыть.'
                                  : 'Tap a section to open it.',
                              style: tx(13, c: C.muted),
                            ),
                          ),
                          for (var i = 0; i < sections.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _SectionCard(
                                section: sections[i],
                                open: _open == i,
                                onTap: () => setState(
                                  () => _open = _open == i ? null : i,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.open,
    required this.onTap,
  });

  final _Section section;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CvCard(
      padding: EdgeInsets.zero,
      color: open ? C.cardOpen : C.card,
      line: open ? C.cardLineLit : C.cardLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: open
                            ? C.accent
                            : const Color.fromRGBO(90, 100, 160, 0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(section.icon, size: 22, color: C.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(section.title,
                              style: tx(16, w: w600, c: C.white)),
                          const SizedBox(height: 2),
                          Text(section.summary,
                              style: tx(12, c: C.muted, h: 1.35)),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      child: const Icon(Icons.expand_more,
                          size: 22, color: C.soft),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final block in section.blocks) block.build(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- содержимое

class _Section {
  const _Section(this.icon, this.title, this.summary, this.blocks);

  final IconData icon;
  final String title;
  final String summary;
  final List<_Block> blocks;
}

abstract class _Block {
  const _Block();
  Widget build();
}

/// Подзаголовок внутри раздела.
class _H extends _Block {
  const _H(this.text);
  final String text;

  @override
  Widget build() => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(text, style: tx(14, w: w700, c: C.white)),
      );
}

/// Обычный абзац.
class _P extends _Block {
  const _P(this.text);
  final String text;

  @override
  Widget build() => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: tx(13.5, c: C.text, h: 1.5)),
      );
}

/// Список с точками.
class _L extends _Block {
  const _L(this.items);
  final List<String> items;

  @override
  Widget build() => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 8, right: 10, left: 2),
                      decoration: const BoxDecoration(
                        color: C.teal,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(item, style: tx(13.5, c: C.text, h: 1.5)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

/// Пошаговая инструкция с номерами.
class _S extends _Block {
  const _S(this.steps);
  final List<String> steps;

  @override
  Widget build() => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(right: 10, top: 1),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: C.accent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text('${i + 1}',
                          style: tx(12, w: w700, c: C.white)),
                    ),
                    Expanded(
                      child:
                          Text(steps[i], style: tx(13.5, c: C.text, h: 1.5)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

/// Совет в рамке.
class _Tip extends _Block {
  const _Tip(this.text);
  final String text;

  @override
  Widget build() => Container(
        margin: const EdgeInsets.only(top: 4, bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(31, 159, 144, 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color.fromRGBO(88, 224, 200, 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_outline, size: 18, color: C.teal),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: tx(13, c: C.white, h: 1.45)),
            ),
          ],
        ),
      );
}

const _ru = <_Section>[
  _Section(Icons.info_outline, 'Как работает ColdVPN',
      'Свой сервер и VPN только для нужных сайтов', [
    _P('ColdVPN — это VPN, который работает через ваш собственный сервер. '
        'Вы арендуете недорогой сервер (VPS) у любого хостинга, а приложение '
        'само устанавливает на него всё необходимое и подключается к нему.'),
    _P('Главная особенность — выборочная маршрутизация. Через VPN идут только '
        'те сайты и сервисы, которые вы включили, например YouTube или '
        'ChatGPT. Всё остальное — банки, госуслуги, местные сайты, игры — '
        'работает напрямую через вашего провайдера, быстро и без '
        'ограничений.'),
    _H('Что используется'),
    _L([
      'AmneziaWG — быстрый протокол на основе WireGuard, который умеет '
          'маскировать трафик, чтобы его было сложнее заблокировать.',
      'Списки адресов сервисов берутся из двух открытых репозиториев и '
          'обновляются автоматически.',
      'Никаких посредников: трафик идёт только между вашим устройством и '
          'вашим сервером.',
    ]),
    _H('С чего начать'),
    _S([
      'Добавьте сервер на вкладке «Сервер» — установите VPN на свой VPS или '
          'вставьте готовый конфиг.',
      'На вкладке «Сервисы» включите нужные сервисы.',
      'Нажмите большую круглую кнопку — VPN включится.',
    ]),
  ]),
  _Section(Icons.dns_outlined, 'Сервер', 'Установка, импорт и общий доступ', [
    _P('Вкладка «Сервер» показывает выбранный сервер: адрес, страну, порт, '
        'задержку и объём трафика. Ниже — список всех ваших серверов и '
        'способы добавить новый.'),
    _H('Способы добавить сервер'),
    _L([
      'Установить на свой VPS — приложение само зайдёт на сервер и '
          'настроит его. Нужны IP-адрес, логин и пароль.',
      'Вставить конфиг текстом — если конфиг прислали сообщением.',
      'Импорт из QR-кода — с камеры телефона или с картинки.',
      'Импорт из файла .conf — готовый конфиг AmneziaWG.',
    ]),
    _H('Как установить VPN на свой VPS'),
    _S([
      'Арендуйте VPS с Ubuntu или Debian у любого хостинга. Подойдёт самый '
          'дешёвый тариф.',
      'Нажмите «Установить на свой VPS».',
      'Введите IP-адрес сервера, логин (обычно root) и пароль из письма '
          'хостинга.',
      'Нажмите «Установить AmneziaWG» и подождите 1–3 минуты. Ход установки '
          'виден прямо в окне.',
      'Готово — сервер появится в списке и станет выбранным.',
    ]),
    _Tip('Отметьте «Запомнить пароль», если хотите потом выпускать ключи для '
        'других устройств без повторного ввода пароля. На Windows пароль '
        'хранится в зашифрованном виде.'),
    _H('Несколько серверов'),
    _P('Серверов может быть сколько угодно. Переключаться между ними можно в '
        'списке на этой вкладке или кнопкой с названием сервера в правом '
        'верхнем углу вкладки «Сервисы». Флаг и город определяются '
        'автоматически, их можно поправить вручную.'),
    _H('Поделиться сервером'),
    _P('Нажмите три точки у сервера → «Поделиться». Конфиг можно отдать '
        'QR-кодом, файлом или текстом.'),
    _L([
      'Конфиг этого устройства нельзя использовать на двух устройствах '
          'одновременно — связь будет рваться у обоих.',
      'Для второго устройства или друга нажмите «Выпустить отдельный ключ» — '
          'у него будет свой независимый доступ. Нужен пароль от сервера.',
      'В конфиге есть ключ доступа: передавайте его только тем, кому '
          'доверяете.',
    ]),
  ]),
  _Section(Icons.tune, 'Сервисы и подключение',
      'Кнопка включения, разделы и режимы', [
    _P('Главная вкладка. Сверху — кнопка включения: она показывает, включён '
        'ли VPN, сколько ресурсов в туннеле и текущую скорость. Нажмите её, '
        'чтобы включить или выключить VPN.'),
    _H('Разделы и ресурсы'),
    _P('Сервисы разложены по разделам: ИИ, Общение, Соцсети, Развлечения, '
        'Игры, Системные и Прочее. Каждый сервис в разделе называется '
        'ресурсом и имеет свой переключатель.'),
    _L([
      'Нажмите на раздел, чтобы раскрыть его.',
      'Переключатель у ресурса отправляет его через VPN.',
      '«Включить все» и «Выключить все» внизу раздела переключают сразу всё.',
      'Изменения применяются на лету, если VPN уже включён.',
    ]),
    _H('Весь трафик через VPN'),
    _P('Переключатель над разделами отправляет через VPN вообще всё. '
        'Переключатели ресурсов при этом закрываются замками — они не нужны, '
        'пока работает этот режим. Выключите его, чтобы вернуться к выбору '
        'сервисов.'),
    _Tip('Если не знаете, через какой ресурс работает нужный сайт, добавьте '
        'его сами — см. раздел «Свои разделы и ресурсы».'),
  ]),
  _Section(Icons.edit_note, 'Свои разделы и ресурсы',
      'Добавление, правка, перетаскивание', [
    _P('Любой раздел и ресурс можно изменить, переместить или удалить, а '
        'также добавить свои.'),
    _H('Добавить сайт'),
    _S([
      'Раскройте подходящий раздел и нажмите «Добавить ресурс».',
      'Введите название, например «Рабочий портал».',
      'Впишите домены или IP-адреса, по одному в строке. Можно вставить '
          'ссылку целиком — приложение само возьмёт из неё домен.',
      'Нажмите «Добавить». Строки с ошибками подсвечиваются красным и '
          'пропускаются.',
    ]),
    _P('Домен добавляется вместе со всеми поддоменами: «example.com» '
        'включает и «www.example.com», и «video.example.com».'),
    _H('Изменить или удалить'),
    _L([
      'Три точки у ресурса → «Изменить»: название, раздел, домены и адреса.',
      'Три точки у раздела → «Изменить название и значок» или удаление. '
          'При удалении раздела ресурсы можно перенести в другой раздел.',
      'Новый раздел — кнопка «Новый раздел» в конце списка.',
    ]),
    _H('Перетаскивание'),
    _L([
      'Разделы и ресурсы перетаскиваются за ручку слева (шесть точек).',
      'На телефоне — долгим нажатием на строку.',
      'Ресурс можно бросить на другой раздел, чтобы перенести его туда. '
          'У края экрана список прокручивается сам.',
    ]),
    _Tip('Правки в готовых списках сохраняются при их обновлении. Удалённые '
        'стандартные разделы и ресурсы можно вернуть в настройках: '
        '«Восстановить стандартные разделы».'),
  ]),
  _Section(Icons.phone_android, 'Android', 'Три режима работы на телефоне', [
    _P('На телефоне над разделами есть переключатель из трёх режимов:'),
    _L([
      'Сервисы — через VPN идут включённые ресурсы, как на компьютере.',
      'Приложения — через VPN идут выбранные приложения телефона целиком, '
          'например браузер или YouTube. Список приложений появится вместо '
          'разделов.',
      'Весь трафик — через VPN идёт всё.',
    ]),
    _P('При первом включении Android спросит разрешение на VPN-подключение — '
        'его нужно подтвердить.'),
    _Tip('На Android в режиме «Сервисы» работают только списки IP-адресов: '
        'маршрутов по доменам там нет. Если сайт не открывается, '
        'используйте режим «Приложения» для браузера.'),
    _P('На телефоне одновременно может работать только один VPN. Если '
        'включить другой VPN, Android выключит ColdVPN.'),
  ]),
  _Section(Icons.public, 'Расширение для браузера',
      'VPN только в Chrome и список избранных сайтов', [
    _P('Расширение для Chrome, Edge, Яндекс.Браузера и Opera включает VPN '
        'только внутри браузера. Другие браузеры и программы при этом ходят '
        'напрямую. Работает на Windows вместе с запущенным приложением.'),
    _H('Установка'),
    _S([
      'В приложении: «Настройки» → «Расширение для браузера» → «Открыть '
          'папку расширения».',
      'В браузере откройте страницу расширений (chrome://extensions), '
          'включите «Режим разработчика» и нажмите «Загрузить распакованное».',
      'Выберите открытую папку.',
      'Нажмите значок ColdVPN в браузере и введите код из того же раздела '
          'настроек. Это нужно один раз.',
    ]),
    _H('Как пользоваться'),
    _L([
      'Кнопка включения включает VPN в браузере.',
      '«Все сайты» — через VPN идёт весь браузер. «Избранные» — только '
          'включённые сайты из списка.',
      '«Добавить текущий сайт в избранное» — открытый сайт попадает в '
          'список.',
      'Правая кнопка мыши на сайте — меню: изменить, выключить, открыть, '
          'удалить. Зажмите строку левой кнопкой, чтобы перетащить её.',
      '«Добавить сайт в приложение» — сайт станет ресурсом ColdVPN, и его '
          'можно будет включить для всей системы.',
    ]),
  ]),
  _Section(Icons.description_outlined, 'Журнал и диагностика',
      'Что происходит и что делать, если не работает', [
    _P('Вкладка «Журнал» показывает, что делает приложение.'),
    _L([
      'События — главное: подключение, ошибки, изменения.',
      'Маршруты — какие сервисы сейчас в туннеле и какие адреса найдены по '
          'доменам.',
      'Подробно — полный технический журнал. Его можно сохранить в файл и '
          'отправить, если нужна помощь. Пароли в журнал не попадают.',
    ]),
    _H('Диагностика'),
    _P('Кнопка «Запустить диагностику» внизу проверяет всё по шагам: клиент, '
        'связь с сервером, трафик через туннель, DNS, маршруты, доступность '
        'включённых сервисов, скорость и состояние самого сервера. У каждого '
        'шага — итог и совет, что делать, если что-то не так.'),
    _Tip('Для полной проверки VPN должен быть включён. Шаг «Сервер изнутри» '
        'просит пароль от сервера.'),
  ]),
  _Section(Icons.settings_outlined, 'Настройки', 'Что означает каждый пункт', [
    _L([
      'Язык — русский или английский.',
      'Запускать вместе с системой — приложение стартует при входе в '
          'Windows.',
      'Запускать в свёрнутом режиме — окно не открывается, приложение сразу '
          'уходит в трей. Открыть его можно щелчком по значку.',
      'Подключаться при запуске — VPN включится сам, если в прошлый раз был '
          'включён.',
      'Сворачивать в трей при закрытии — VPN продолжит работать в фоне. '
          'Выйти можно через значок в трее.',
      'Маршруты по доменам (Windows) — приложение следит за обращениями к '
          'доменам включённых сервисов и сразу отправляет их адреса в '
          'туннель. Это делает работу сервисов надёжнее.',
      'Только IPv4 — чтобы трафик не ушёл мимо VPN по IPv6.',
      'DNS для сервисов в туннеле — через какой DNS узнаются адреса '
          'включённых сервисов. Остальные сайты используют обычный DNS.',
      'Списки сервисов — обновление адресов из репозиториев, вручную или раз '
          'в неделю автоматически.',
      'Перенос и сброс — сохранить все настройки в файл и загрузить на '
          'другом устройстве, вернуть стандартные разделы или сбросить всё.',
    ]),
    _Tip('Файл настроек содержит ключи ваших серверов — храните его как '
        'пароль.'),
    _H('Запуск в свёрнутом режиме (Windows)'),
    _P('Пункт «Запускать в свёрнутом режиме» находится сразу под «Запускать '
        'вместе с системой». Когда он включён, окно приложения при запуске не '
        'появляется: ColdVPN работает в фоне, а в области уведомлений рядом с '
        'часами виден его значок.'),
    _L([
      'Щелчок по значку — открыть окно.',
      'Правый щелчок — меню: открыть ColdVPN, включить или выключить VPN, '
          'выйти.',
      'Действует при любом запуске — и при входе в Windows, и когда вы '
          'открываете приложение сами.',
    ]),
    _S([
      'Включите «Запускать вместе с системой».',
      'Включите «Запускать в свёрнутом режиме».',
      'При желании включите «Подключаться при запуске» — тогда после входа '
          'в Windows VPN поднимется сам, без единого окна.',
    ]),
    _Tip('Если значок не виден, нажмите стрелку «^» у часов — Windows прячет '
        'туда редко используемые значки. Его можно перетащить на панель, '
        'чтобы он был всегда на виду.'),
  ]),
  _Section(Icons.help_outline, 'Если что-то не работает',
      'Частые вопросы и решения', [
    _H('Windows показывает «Система Windows защитила ваш компьютер»'),
    _P('Установщик не подписан платной цифровой подписью. Нажмите '
        '«Подробнее» → «Выполнить в любом случае».'),
    _H('Приложение просит права администратора'),
    _P('Без них нельзя создать туннель и менять маршруты. Запускайте '
        'ColdVPN от имени администратора — установщик настраивает это сам.'),
    _H('«Сервер не ответил на рукопожатие»'),
    _P('Сервер выключен или его UDP-порт закрыт файрволом хостинга. '
        'Проверьте сервер в панели хостинга и откройте порт, указанный на '
        'вкладке «Сервер».'),
    _H('VPN включён, но сайт не открывается'),
    _S([
      'Проверьте, что ресурс этого сайта включён.',
      'Если сайта нет в списках — добавьте его домен как свой ресурс.',
      'Запустите диагностику в журнале и посмотрите на шаги с ошибками.',
      'Попробуйте другой сервер: некоторые сервисы блокируют адреса '
          'отдельных хостингов.',
    ]),
    _H('Конфликт с другими VPN и ускорителями'),
    _P('Программы вроде других VPN или игровых ускорителей тоже меняют '
        'маршруты и DNS. Если ColdVPN перестал работать вместе с ними, '
        'выключите ресурсы той игры или сервиса, которые ускоряет другая '
        'программа, или используйте их по очереди.'),
  ]),
];

const _en = <_Section>[
  _Section(Icons.info_outline, 'How ColdVPN works',
      'Your own server and a VPN only for the sites you need', [
    _P('ColdVPN is a VPN that runs through your own server. You rent an '
        'inexpensive server (VPS) from any hosting company, and the app '
        'installs everything on it by itself and connects to it.'),
    _P('Its main feature is split tunnelling. Only the sites and services you '
        'turn on, such as YouTube or ChatGPT, go through the VPN. Everything '
        'else — banks, government services, local sites, games — goes '
        'directly through your provider, fast and without limits.'),
    _H('What it uses'),
    _L([
      'AmneziaWG — a fast protocol based on WireGuard that can disguise '
          'traffic so that it is harder to block.',
      'Service address lists come from two open repositories and are updated '
          'automatically.',
      'No middlemen: traffic goes only between your device and your server.',
    ]),
    _H('Getting started'),
    _S([
      'Add a server on the Server tab — install the VPN on your VPS or paste '
          'a ready config.',
      'Turn on the services you need on the Services tab.',
      'Press the big round button — the VPN turns on.',
    ]),
  ]),
  _Section(Icons.dns_outlined, 'Server', 'Installation, import and sharing', [
    _P('The Server tab shows the selected server: address, country, port, '
        'latency and traffic. Below are all your servers and the ways to add '
        'a new one.'),
    _H('Ways to add a server'),
    _L([
      'Install on your own VPS — the app signs in to the server and sets it '
          'up. You need the IP address, login and password.',
      'Paste a config as text — if the config was sent in a message.',
      'Import from a QR code — with the phone camera or from a picture.',
      'Import a .conf file — a ready AmneziaWG config.',
    ]),
    _H('How to install the VPN on your VPS'),
    _S([
      'Rent a VPS with Ubuntu or Debian from any hosting company. The '
          'cheapest plan is enough.',
      'Press “Install on your own VPS”.',
      'Enter the server IP address, the login (usually root) and the '
          'password from the hosting e-mail.',
      'Press “Install AmneziaWG” and wait 1–3 minutes. The progress is shown '
          'right in the window.',
      'Done — the server appears in the list and becomes selected.',
    ]),
    _Tip('Tick “Remember the password” to issue keys for other devices later '
        'without entering the password again. On Windows the password is '
        'stored encrypted.'),
    _H('Several servers'),
    _P('You can have as many servers as you like. Switch between them in the '
        'list on this tab or with the server name button in the top right of '
        'the Services tab. The flag and city are detected automatically and '
        'can be corrected by hand.'),
    _H('Sharing a server'),
    _P('Press the three dots next to a server → Share. The config can be '
        'given as a QR code, a file or text.'),
    _L([
      'The config of this device cannot be used on two devices at the same '
          'time — the connection breaks on both.',
      'For a second device or a friend press “Issue a separate key” — it '
          'gets its own independent access. The server password is needed.',
      'The config contains an access key: share it only with people you '
          'trust.',
    ]),
  ]),
  _Section(Icons.tune, 'Services and connection',
      'The power button, sections and modes', [
    _P('The main tab. At the top is the power button: it shows whether the '
        'VPN is on, how many resources are in the tunnel and the current '
        'speed. Press it to turn the VPN on or off.'),
    _H('Sections and resources'),
    _P('Services are grouped into sections: AI, Messaging, Social, '
        'Entertainment, Games, System and Other. Each service in a section is '
        'called a resource and has its own switch.'),
    _L([
      'Tap a section to open it.',
      'The switch next to a resource sends it through the VPN.',
      '“Turn all on” and “Turn all off” at the bottom of a section switch '
          'everything at once.',
      'Changes apply on the fly if the VPN is already on.',
    ]),
    _H('All traffic through VPN'),
    _P('The switch above the sections sends absolutely everything through '
        'the VPN. The resource switches get locks — they are not needed while '
        'this mode is on. Turn it off to go back to choosing services.'),
    _Tip('If you do not know which resource a site belongs to, add it '
        'yourself — see “Your own sections and resources”.'),
  ]),
  _Section(Icons.edit_note, 'Your own sections and resources',
      'Adding, editing, dragging', [
    _P('Any section and resource can be edited, moved or deleted, and you '
        'can add your own.'),
    _H('Adding a site'),
    _S([
      'Open a suitable section and press “Add a resource”.',
      'Enter a name, for example “Work portal”.',
      'Type domains or IP addresses, one per line. You can paste a whole '
          'link — the app takes the domain from it.',
      'Press Add. Lines with errors are highlighted in red and skipped.',
    ]),
    _P('A domain is added with all its subdomains: “example.com” also covers '
        '“www.example.com” and “video.example.com”.'),
    _H('Editing or deleting'),
    _L([
      'Three dots on a resource → Edit: name, section, domains and addresses.',
      'Three dots on a section → change the name and icon, or delete it. '
          'When deleting a section, its resources can be moved to another one.',
      'A new section — the “New section” button at the end of the list.',
    ]),
    _H('Dragging'),
    _L([
      'Sections and resources are dragged by the handle on the left (six '
          'dots).',
      'On a phone — with a long press on the row.',
      'Drop a resource on another section to move it there. Near the edge '
          'of the screen the list scrolls by itself.',
    ]),
    _Tip('Edits to the built-in lists survive list updates. Deleted default '
        'sections and resources can be brought back in Settings: “Restore '
        'default sections”.'),
  ]),
  _Section(Icons.phone_android, 'Android', 'Three modes on a phone', [
    _P('On a phone there is a three-way switch above the sections:'),
    _L([
      'Services — the resources turned on go through the VPN, as on a '
          'computer.',
      'Apps — the selected phone apps go through the VPN entirely, for '
          'example the browser or YouTube. The app list replaces the sections.',
      'All traffic — everything goes through the VPN.',
    ]),
    _P('The first time, Android asks for permission to create a VPN '
        'connection — confirm it.'),
    _Tip('On Android in Services mode only IP lists work: there are no routes '
        'by domain. If a site does not open, use Apps mode for the browser.'),
    _P('Only one VPN can run on a phone at a time. If you turn on another VPN, '
        'Android turns ColdVPN off.'),
  ]),
  _Section(Icons.public, 'Browser extension',
      'VPN only in Chrome and a list of favourite sites', [
    _P('The extension for Chrome, Edge, Yandex Browser and Opera turns the '
        'VPN on only inside the browser. Other browsers and programs go '
        'directly. It works on Windows together with the running app.'),
    _H('Installation'),
    _S([
      'In the app: Settings → Browser extension → Open the extension folder.',
      'In the browser open the extensions page (chrome://extensions), turn on '
          'Developer mode and press “Load unpacked”.',
      'Choose the opened folder.',
      'Press the ColdVPN icon in the browser and enter the code from the same '
          'settings block. This is needed once.',
    ]),
    _H('How to use it'),
    _L([
      'The power button turns the VPN on in the browser.',
      '“All sites” — the whole browser goes through the VPN. “Favourites” — '
          'only the sites turned on in the list.',
      '“Add the current site to favourites” — the open site goes into the '
          'list.',
      'Right-click a site for the menu: edit, turn off, open, remove. Hold a '
          'row with the left button to drag it.',
      '“Add the site to the app” — the site becomes a ColdVPN resource that '
          'can be turned on for the whole system.',
    ]),
  ]),
  _Section(Icons.description_outlined, 'Log and diagnostics',
      'What is happening and what to do if it does not work', [
    _P('The Log tab shows what the app is doing.'),
    _L([
      'Events — the essentials: connecting, errors, changes.',
      'Routes — which services are in the tunnel now and which addresses '
          'were found by domain.',
      'Details — the full technical log. Save it to a file and send it if '
          'you need help. Passwords never get into the log.',
    ]),
    _H('Diagnostics'),
    _P('The “Run diagnostics” button at the bottom checks everything step by '
        'step: the client, the connection to the server, traffic through the '
        'tunnel, DNS, routes, availability of the services turned on, speed '
        'and the state of the server itself. Each step has a verdict and '
        'advice on what to do if something is wrong.'),
    _Tip('For a full check the VPN must be on. The “Server from the inside” '
        'step asks for the server password.'),
  ]),
  _Section(Icons.settings_outlined, 'Settings', 'What each item means', [
    _L([
      'Language — English or Russian.',
      'Start with the system — the app starts with Windows.',
      'Start minimized — no window opens, the app goes straight to the tray. '
          'Click the icon to open it.',
      'Connect on startup — the VPN turns on by itself if it was on last '
          'time.',
      'Minimize to tray on close — the VPN keeps working in the background. '
          'Quit through the tray icon.',
      'Routes by domain (Windows) — the app watches requests to the domains '
          'of the services turned on and sends their addresses into the '
          'tunnel right away. This makes services more reliable.',
      'IPv4 only — so that traffic does not bypass the VPN over IPv6.',
      'DNS for services in the tunnel — which DNS resolves the addresses of '
          'the services turned on. Other sites use the regular DNS.',
      'Service lists — updating the addresses from the repositories, by hand '
          'or automatically once a week.',
      'Transfer and reset — save all settings to a file and load them on '
          'another device, restore the default sections or reset everything.',
    ]),
    _Tip('The settings file contains your server keys — keep it like a '
        'password.'),
    _H('Start minimized (Windows)'),
    _P('The “Start minimized” item sits right under “Start with the system”. '
        'When it is on, no window appears at startup: ColdVPN runs in the '
        'background and its icon shows in the notification area next to the '
        'clock.'),
    _L([
      'Click the icon — open the window.',
      'Right-click — menu: open ColdVPN, turn the VPN on or off, quit.',
      'It applies to every start — both at Windows sign-in and when you open '
          'the app yourself.',
    ]),
    _S([
      'Turn on “Start with the system”.',
      'Turn on “Start minimized”.',
      'Optionally turn on “Connect on startup” — then the VPN comes up by '
          'itself after you sign in to Windows, without a single window.',
    ]),
    _Tip('If you cannot see the icon, click the “^” arrow next to the clock — '
        'Windows hides rarely used icons there. You can drag it onto the '
        'taskbar to keep it always visible.'),
  ]),
  _Section(Icons.help_outline, 'If something does not work',
      'Common questions and solutions', [
    _H('Windows says “Windows protected your PC”'),
    _P('The installer is not signed with a paid digital signature. Press '
        '“More info” → “Run anyway”.'),
    _H('The app asks for administrator rights'),
    _P('Without them it cannot create the tunnel or change routes. Run '
        'ColdVPN as administrator — the installer sets this up by itself.'),
    _H('“The server did not respond to the handshake”'),
    _P('The server is off or its UDP port is closed by the hosting firewall. '
        'Check the server in the hosting panel and open the port shown on the '
        'Server tab.'),
    _H('The VPN is on, but a site does not open'),
    _S([
      'Check that the resource for this site is turned on.',
      'If the site is not in the lists, add its domain as your own resource.',
      'Run diagnostics on the Log tab and look at the steps with errors.',
      'Try another server: some services block the addresses of certain '
          'hosting companies.',
    ]),
    _H('Conflicts with other VPNs and accelerators'),
    _P('Other VPNs and game accelerators also change routes and DNS. If '
        'ColdVPN stops working alongside them, turn off the resources of the '
        'game or service the other program accelerates, or use them one at a '
        'time.'),
  ]),
];
