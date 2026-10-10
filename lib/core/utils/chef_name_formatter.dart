import '../../models/user_model.dart';

class ChefNameFormatter {
  ChefNameFormatter._();

  static const _commonFamilyNameSuffixes = <String>[
    'saad',
    'khan',
    'malik',
    'sheikh',
    'ahmed',
    'ali',
  ];

  static String fromUser(UserModel? user) {
    if (user == null) return 'Chef';

    final profileName = user.name.trim();
    final emailLocalPart = user.email.split('@').first.trim();
    final profileIsUseful =
        profileName.isNotEmpty &&
        profileName.toLowerCase() != 'chef' &&
        profileName.toLowerCase() != emailLocalPart.toLowerCase();

    final source = profileIsUseful ? profileName : emailLocalPart;
    if (source.isEmpty) return 'Chef';

    var firstPart = source.split(RegExp(r'[\s._-]+')).first;
    firstPart = firstPart.replaceAll(RegExp(r'[^a-zA-Z]'), '');

    if (!profileIsUseful) {
      final lower = firstPart.toLowerCase();
      for (final suffix in _commonFamilyNameSuffixes) {
        if (lower.endsWith(suffix) && lower.length >= suffix.length + 3) {
          firstPart = firstPart.substring(0, firstPart.length - suffix.length);
          break;
        }
      }
    }

    if (firstPart.isEmpty) return 'Chef';
    return '${firstPart[0].toUpperCase()}${firstPart.substring(1).toLowerCase()}';
  }
}
