## ColdVPN 0.1.3

### Новое в 0.1.3

- **Расширение для Chrome** (Windows) — пульт ColdVPN в браузере:
  - VPN включается только внутри Chrome: другие браузеры и программы идут напрямую. Весь компьютер по-прежнему включается в самом приложении.
  - Два режима: «Все сайты» и «Избранные». Избранные сайты включаются переключателями, перетаскиваются зажатием левой кнопки мыши, правка и удаление — по правому щелчку.
  - Кнопки «Добавить текущий сайт в избранное» и «Добавить сайт в приложение» — сайт с открытой вкладки попадает в выбранный раздел ColdVPN.
  - Связь с приложением защищена кодом из настроек. Расширение лежит в папке `chrome_extension` рядом с приложением; как его поставить — в инструкции.
- **Встроенная инструкция**: «Настройки» → «О программе» → «Инструкция». Разделы по всем функциям — сервер, сервисы, режимы, диагностика, Android, расширение, настройки.
- **«Запускать в свёрнутом режиме»** (Windows) — новый пункт под «Запускать вместе с системой»: приложение стартует сразу в трей, без окна.

### Изменения

- Автозапуск больше не прячет окно сам по себе: при входе в Windows приложение уходит в трей, только если включён пункт «Запускать в свёрнутом режиме». Если вам нужно прежнее поведение, включите этот пункт.
- Убрана кнопка «Купить подписку» на вкладке «Сервер».

### Как обновиться

- **Windows:** запустите новый установщик поверх старой версии — настройки сохранятся. Windows покажет предупреждение SmartScreen: «Подробнее» → «Выполнить в любом случае».
- **Android:** установите APK поверх версии 0.1.x из раздела Releases.
- **Расширение:** если оно уже загружено в Chrome, откройте `chrome://extensions` и нажмите «Обновить» у ColdVPN.

Полный список возможностей предыдущих версий — в [заметках к 0.1.1](https://github.com/ColdVision/ColdVPN/releases/tag/v0.1.1).

---

### New in 0.1.3

- **Chrome extension** (Windows) — a ColdVPN remote in the browser:
  - The VPN is turned on inside Chrome only: other browsers and programs go directly. The whole computer is still turned on in the app itself.
  - Two modes: All sites and Favourites. Favourite sites have their own switches, are reordered by holding the left mouse button, and are edited or removed with a right click.
  - “Add current site to favourites” and “Add site to the app” buttons — the site of the open tab goes into the chosen ColdVPN section.
  - The link to the app is protected by a code from the settings. The extension is in the `chrome_extension` folder next to the app; the guide explains how to install it.
- **Built-in guide**: Settings → About → User guide. Sections on every feature — server, services, modes, diagnostics, Android, the extension, settings.
- **“Start minimized”** (Windows) — a new item under “Start with the system”: the app starts straight in the tray, without a window.

### Changes

- Autostart no longer hides the window on its own: at Windows sign-in the app goes to the tray only when “Start minimized” is on. Turn this item on if you want the old behaviour.
- The “Buy a subscription” button was removed from the Server tab.

### How to update

- **Windows:** run the new installer over the old version — your settings are kept. Windows shows a SmartScreen warning: “More info” → “Run anyway”.
- **Android:** install the APK over version 0.1.x from the Releases page.
- **Extension:** if it is already loaded in Chrome, open `chrome://extensions` and click “Reload” on ColdVPN.

See the [0.1.1 notes](https://github.com/ColdVision/ColdVPN/releases/tag/v0.1.1) for the full list of earlier features.
