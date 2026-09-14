import 'package:flutter/foundation.dart';

final desktopConnectionBusy = ValueNotifier<bool>(false);
final desktopConnectionOnline = ValueNotifier<bool>(false);

final desktopConnectionStatus = ValueNotifier<String>(
  'Nenhum dispositivo conectado',
);
