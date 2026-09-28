/// Deskbot cloud API base URL.
/// Override at build time: `--dart-define=DESKBOT_API_BASE=https://deskbot.inmomentservices.com`
const String kDeskbotApiBase = String.fromEnvironment(
  'DESKBOT_API_BASE',
  defaultValue: 'https://deskbot.inmomentservices.com',
);
