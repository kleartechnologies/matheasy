import 'app_routes.dart';

/// Translates external deep links into in-app route locations.
///
/// Supports the custom `matheasy://` scheme (e.g. `matheasy://scan`) and, in
/// the future, universal/app links on `https://www.getmatheasy.com/…`. For
/// custom schemes the *host* carries the destination (`matheasy://scan` → host
/// `scan`); for https links the *path* does.
class DeepLinkParser {
  const DeepLinkParser._();

  static const String scheme = 'matheasy';

  /// The registered web hosts. Both are listed because the apex and `www` are
  /// distinct hosts to iOS/Android — each needs its own
  /// `apple-app-site-association` / `assetlinks.json`, and a link shared as the
  /// apex must still open the app even though the browser would 308 to `www`.
  ///
  /// NOTE: nothing routes here yet — there is no Associated Domains entitlement
  /// on the iOS target, so the OS never hands us an https link. Registering
  /// these hosts with Apple/Google is what turns this on.
  static const List<String> webHosts = ['getmatheasy.com', 'www.getmatheasy.com'];

  /// The canonical host to *build* links with (the apex redirects to it).
  static const String webHost = 'www.getmatheasy.com';

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

    // Universal link: https://www.getmatheasy.com/<destination>/<rest>
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        webHosts.contains(uri.host.toLowerCase()) &&
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
        // The AI Tutor is contextual now — a deep link opens the chat directly.
        return AppRoutes.tutorChat;
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
