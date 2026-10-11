## ColdVPN 0.1.1

### Новое в 0.1.1

- **Кнопка «Купить подписку»** на вкладке «Сервер»: открывает страницу подписки в браузере.
- **Новый порядок способов добавить сервер:** подписка, установка на свой VPS, вставка конфига текстом, QR-код, файл `.conf`.
- **Android:** ресурсы и разделы перетаскиваются долгим нажатием; ссылки из приложения открываются в браузере, а не копируются.

### Что появилось в 0.1.0

- **Версия для Android** (8.0 и новее). Три режима: «Сервисы» — через VPN идут выбранные ресурсы, «Приложения» — выбранные приложения целиком, «Весь трафик».
- **Редактируемые разделы и ресурсы.** Любой раздел и ресурс можно переименовать, изменить или удалить; можно создавать свои разделы и добавлять ресурсы с собственными доменами и адресами. Правки в готовых списках сохраняются при обновлении списков.
- **Перетаскивание ресурсов** внутри раздела и между разделами.
- **Новые ресурсы:** раздел «Игры» (Blizzard, Epic Games, Steam, Bethesda), а также Copilot, Snapchat, Netflix, Twitch, Figma и Miro.
- **Английский язык интерфейса.** Язык переключается в настройках; по умолчанию берётся язык системы.
- **Перенос настроек** теперь включает разделы, ресурсы со всеми правками и выбранный язык.
- **Установщик Windows** получил значок и название приложения в мастере установки и в свойствах файла.
- **APK подписывается постоянным ключом**, поэтому следующие версии будут устанавливаться поверх этой.

### Исправления

- Подключение больше не считается неудачным, когда проверочный запрос упирается в ошибку сертификата, хотя туннель работает.

### Удалено

- RuTracker убран из готовых ресурсов.

### Как обновиться

- **Windows:** запустите новый установщик поверх старой версии — настройки сохранятся. Windows покажет предупреждение SmartScreen: «Подробнее» → «Выполнить в любом случае».
- **Android:** установите APK. Если на телефоне стоит сборка, полученная раньше не из раздела Releases, её нужно сначала удалить — у неё другая подпись. Перед этим сохраните настройки в файл.

---

### New in 0.1.1

- **A “Buy a subscription” button** on the Server tab: it opens the subscription page in the browser.
- **A new order of the ways to add a server:** subscription, installation on your own VPS, pasting a config as text, QR code, `.conf` file.
- **Android:** resources and sections are dragged with a long press; links from the app open in the browser instead of being copied.

### Introduced in 0.1.0

- **Android version** (8.0 and later). Three modes: Services — the chosen resources go through the VPN, Apps — the chosen apps go through it entirely, and All traffic.
- **Editable sections and resources.** Any section or resource can be renamed, edited or deleted; you can create your own sections and add resources with your own domains and addresses. Edits to the built-in lists survive list updates.
- **Drag and drop for resources** within a section and between sections.
- **New resources:** a Games section (Blizzard, Epic Games, Steam, Bethesda), plus Copilot, Snapchat, Netflix, Twitch, Figma and Miro.
- **English interface.** The language is switched in Settings; the system language is used by default.
- **Settings transfer** now includes sections, resources with all edits, and the chosen language.
- **The Windows installer** shows the app icon and name in the setup wizard and in the file properties.
- **The APK is signed with a permanent key**, so later versions install over this one.

### Fixes

- A connection is no longer treated as failed when the probe request hits a certificate error while the tunnel works.

### Removed

- RuTracker was removed from the built-in resources.

### How to update

- **Windows:** run the new installer over the old version — your settings are kept. Windows shows a SmartScreen warning: “More info” → “Run anyway”.
- **Android:** install the APK. If the phone has a build obtained earlier from somewhere other than the Releases page, remove it first — it has a different signature. Save your settings to a file before that.
