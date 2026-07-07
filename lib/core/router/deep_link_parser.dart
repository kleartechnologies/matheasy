import 'app_routes.dart';

/// Translates external deep links into in-app route locations.
///
/// Supports the custom `matheasy://` scheme (e.g. `matheasy://scan`) and, in
/// the future, universal/app links on `https://matheasy.app/…`. For custom
/// schemes the *host* carries the destination (`matheasy://scan` → host
/// `scan`); for https links the *path* does.
class DeepLinkParser {
  const DeepLinkParser._();

  static const String scheme = 'matheasy';
  static const String webHost = 'matheasy.app';

  /// Maps a deep-link [uri] to an in-app location, or `null` if it isn't a
  /// recognized external link (in which case normal route matching applies).
  static String? resolve(Uri uri) {
    // Custom scheme: matheasy://<destination>/<rest>
    if (uri.scheme == scheme) {
      final destination = uri.host.isNotEmpty
          ? uri.host
          : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
      return _locationFor(destination);
    }

    // Universal link: https://matheasy.app/<destination>/<rest>
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == webHost &&
        uri.pathSegments.isNotEmpty) {
      return _locationFor(uri.pathSegments.first);
    }

    return null;
  }

  static String? _locationFor(String destination) {
    switch (destination) {
      case 'scan':
        return AppRoutes.scan;
      case 'practice':
        return AppRoutes.practice;
      case 'tutor':
        return AppRoutes.tutor;
      case 'paywall':
        return AppRoutes.paywall;
      case 'home':
        return AppRoutes.home;
      case 'profile':
        return AppRoutes.profile;
      default:
        return null;
    }
  }
}
