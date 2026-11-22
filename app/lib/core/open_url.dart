import 'package:url_launcher/url_launcher.dart';

/// Opens a link in another app: Google Maps for the directions, the browser for a search
Future<bool> openUrl(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
