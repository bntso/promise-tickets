import 'package:hive/hive.dart';

const String kNameKey = 'name';
const String kWalletViewKey = 'walletView';

String profileName(Box settings) {
  final name = settings.get(kNameKey);
  if (name is String && name.trim().isNotEmpty) return name.trim();
  return 'Me';
}
