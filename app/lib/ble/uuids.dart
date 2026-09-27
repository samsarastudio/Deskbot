/// Protocol constants matching docs/protocol_v1.md
class DeskbotBle {
  static const serviceUuid = '6e6f7661-0001-4000-8000-6465736b626f';
  static const cmdRxUuid = '6e6f7661-0002-4000-8000-6465736b626f';
  static const evtTxUuid = '6e6f7661-0003-4000-8000-6465736b626f';
  static const infoUuid = '6e6f7661-0004-4000-8000-6465736b626f';
  static const sessionUuid = '6e6f7661-0005-4000-8000-6465736b626f';

  static const fragMagic = 0xA5;
  static const fragMore = 0x01;
  static const fragFinal = 0x02;
  static const fragPayload = 160;
  static const protocolVersion = 1;
  static const appVersion = '1.0.0';
}
