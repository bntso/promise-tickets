import 'package:hive/hive.dart';

const String kNameKey = 'name';

String profileName(Box settings) {
  final name = settings.get(kNameKey);
  if (name is String && name.trim().isNotEmpty) return name.trim();
  return 'Me';
}
