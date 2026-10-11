import 'package:flutter/material.dart';

/// Раздел из начального набора и сервисы каталога, которые в него попадают.
class ServiceGroup {
  const ServiceGroup(this.id, this.label, this.icon, this.serviceIds);

  final String id;
  final String label;

  /// Ключ значка из [sectionIcons].
  final String icon;
  final List<String> serviceIds;
}

const otherGroupId = 'other';

/// Раздел, куда при переходе с прежних сборок попадают «Мои маршруты».
const customGroupId = 'custom';

/// Значки, из которых выбирается значок раздела.
const sectionIcons = <String, IconData>{
  'spark': Icons.auto_awesome,
  'chat': Icons.chat_bubble_outline,
  'people': Icons.people_outline,
  'play': Icons.play_circle_outline,
  'cloud': Icons.cloud_outlined,
  'globe': Icons.public,
  'route': Icons.alt_route,
  'game': Icons.sports_esports_outlined,
  'work': Icons.work_outline,
  'cart': Icons.shopping_cart_outlined,
  'music': Icons.music_note_outlined,
  'star': Icons.star_outline,
};

IconData sectionIcon(String key) => sectionIcons[key] ?? Icons.star_outline;

/// Начальный набор разделов. Дальше пользователь меняет его как хочет;
/// сервис каталога, не попавший ни в один раздел, идёт в «Прочее».
const serviceGroups = <ServiceGroup>[
  ServiceGroup('ai', 'ИИ', 'spark',
      ['chatgpt-openai', 'claude', 'gemini', 'grok', 'copilot']),
  ServiceGroup('chat', 'Общение', 'chat', ['discord', 'telegram', 'whatsapp']),
  ServiceGroup('social', 'Соцсети', 'people',
      ['facebook', 'instagram', 'meta', 'twitter-x', 'tiktok', 'snapchat']),
  ServiceGroup('fun', 'Развлечения', 'play', [
    'youtube', 'spotify', 'soundcloud', 'anilibria-animego', 'netflix', //
    'twitch',
  ]),
  ServiceGroup('games', 'Игры', 'game',
      ['blizzard', 'epic-games', 'steam', 'bethesda']),
  ServiceGroup('system', 'Системные', 'cloud',
      ['aws-amazon', 'cloudflare', 'google', 'nvidia']),
  ServiceGroup(otherGroupId, 'Прочее', 'globe',
      ['2ip-ru', 'figma', 'miro']),
];

/// Сервисы, убранные из каталога: у тех, кто ими уже пользовался, они
/// исчезают из разделов.
const retiredServices = {'rutracker', 'nnm-club', 'rutor'};

/// Сайт, по которому диагностика проверяет, отвечает ли сервис через VPN.
const serviceProbeHosts = <String, String>{
  'aws-amazon': 'aws.amazon.com',
  'chatgpt-openai': 'chatgpt.com',
  'claude': 'claude.ai',
  'gemini': 'gemini.google.com',
  'grok': 'grok.com',
  'google': 'www.google.com',
  'youtube': 'www.youtube.com',
  'cloudflare': 'www.cloudflare.com',
  'discord': 'discord.com',
  'telegram': 'telegram.org',
  'whatsapp': 'www.whatsapp.com',
  'facebook': 'www.facebook.com',
  'instagram': 'www.instagram.com',
  'meta': 'about.meta.com',
  'twitter-x': 'x.com',
  'tiktok': 'www.tiktok.com',
  'spotify': 'open.spotify.com',
  'soundcloud': 'soundcloud.com',
  'nvidia': 'www.nvidia.com',
  'anilibria-animego': 'anilibria.top',
  '2ip-ru': '2ip.ru',
  'copilot': 'copilot.microsoft.com',
  'snapchat': 'www.snapchat.com',
  'netflix': 'www.netflix.com',
  'twitch': 'www.twitch.tv',
  'blizzard': 'www.blizzard.com',
  'epic-games': 'store.epicgames.com',
  'steam': 'store.steampowered.com',
  'bethesda': 'bethesda.net',
  'figma': 'www.figma.com',
  'miro': 'miro.com',
};

/// Флаги стран лежат одной картинкой-сеткой `assets/flags.png`:
/// 16 флагов в ряд, по порядку кодов в этой строке (по две буквы).
const flagColumns = 16;
const flagRows = 16;
const flagCodes =
    'adaeafagaialamaoaqarasatauawaxazbabbbdbebfbgbhbibjblbmbnbobq'
    'brbsbtbvbwbybzcacccdcfcgchcickclcmcncocrcucvcwcxcyczdedjdkdm'
    'dodzeceeegehereseteufifjfkfmfofrgagbgdgegfggghgiglgmgngpgqgr'
    'gsgtgugwgyhkhmhnhrhthuidieiliminioiqirisitjejmjojpkekgkhkikm'
    'knkpkrkwkykzlalblclilklrlsltlulvlymamcmdmemfmgmhmkmlmmmnmomp'
    'mqmrmsmtmumvmwmxmymznancnenfngninlnonpnrnunzompapepfpgphpkpl'
    'pmpnprpsptpwpyqarerorsrurwsasbscsdsesgshsisjskslsmsnsosrssst'
    'svsxsysztctdtftgthtjtktltmtntotrtttvtwtzuaugumusuyuzvavcvevg'
    'vivnvuwfwsxkyeytzazmzw';

/// Номер флага в сетке или -1, если такой страны в наборе нет.
int flagIndex(String countryCode) {
  final code = countryCode.toLowerCase();
  if (code.length != 2) return -1;
  for (var i = 0; i + 1 < flagCodes.length; i += 2) {
    if (flagCodes[i] == code[0] && flagCodes[i + 1] == code[1]) return i ~/ 2;
  }
  return -1;
}
