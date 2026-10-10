import 'package:flutter/material.dart';

/// Группа сервисов на вкладке «Сервисы».
class ServiceGroup {
  const ServiceGroup(this.id, this.label, this.icon, this.serviceIds);

  final String id;
  final String label;
  final IconData icon;
  final List<String> serviceIds;
}

const otherGroupId = 'other';
const customGroupId = 'custom';

/// Группы в порядке по умолчанию. Сервис, не попавший ни в одну группу,
/// показывается в «Прочем»; «Мои маршруты» заполняет пользователь.
const serviceGroups = <ServiceGroup>[
  ServiceGroup('ai', 'ИИ', Icons.auto_awesome,
      ['chatgpt-openai', 'claude', 'gemini', 'grok']),
  ServiceGroup('chat', 'Общение', Icons.chat_bubble_outline,
      ['discord', 'telegram', 'whatsapp']),
  ServiceGroup('social', 'Соцсети', Icons.people_outline,
      ['facebook', 'instagram', 'meta', 'twitter-x', 'tiktok']),
  ServiceGroup('fun', 'Развлечения', Icons.play_circle_outline,
      ['youtube', 'spotify', 'soundcloud', 'anilibria-animego', 'rutracker']),
  ServiceGroup('system', 'Системные', Icons.cloud_outlined,
      ['aws-amazon', 'cloudflare', 'google', 'nvidia']),
  ServiceGroup(otherGroupId, 'Прочее', Icons.public, ['2ip-ru']),
  ServiceGroup(customGroupId, 'Мои маршруты', Icons.alt_route, []),
];

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
  'rutracker': 'rutracker.org',
  'anilibria-animego': 'anilibria.top',
  '2ip-ru': '2ip.ru',
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
