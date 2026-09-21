import '../settings/app_strings.dart';
import 'package:flutter/foundation.dart';

final desktopConnectionBusy = ValueNotifier<bool>(false);
final desktopConnectionOnline = ValueNotifier<bool>(false);

final desktopConnectionStatus = ValueNotifier<String>(
  tr('Nenhum dispositivo conectado'),
);
