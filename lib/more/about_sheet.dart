import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/suchi_widgets.dart';

final _sourceUri = Uri.parse('https://github.com/johnnybravo-xyz/suchi-mobile');
final _privacyUri = Uri.parse('https://suchi.page/privacy/');
final _supportUri = Uri.parse('https://suchi.page/support/');
final _securityUri = Uri.parse('https://suchi.page/security/');

class AboutSuchiSheet extends StatefulWidget {
  const AboutSuchiSheet({super.key});

  @override
  State<AboutSuchiSheet> createState() => _AboutSuchiSheetState();
}

class _AboutSuchiSheetState extends State<AboutSuchiSheet> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  Future<void> _open(Uri uri, String label) async {
    bool opened;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$label could not be opened.')));
    }
  }

  void _showLicenses(PackageInfo? info) {
    showLicensePage(
      context: context,
      applicationName: 'Suchi Companion',
      applicationVersion: info == null
          ? null
          : '${info.version} (${info.buildNumber})',
      applicationIcon: const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: BrandMark(size: 48),
      ),
      applicationLegalese:
          'GNU Affero General Public License v3.0 or a commercial license.',
    );
  }

  Widget _externalLink({
    required Key key,
    required IconData icon,
    required String title,
    required Uri uri,
  }) => ListTile(
    key: key,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(uri.toString()),
    trailing: const Icon(Icons.open_in_new),
    onTap: () => _open(uri, title),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: _packageInfo,
    builder: (context, snapshot) {
      final info = snapshot.data;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(child: BrandMark(size: 56)),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Suchi Companion',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              info == null
                  ? snapshot.hasError
                        ? 'Version unavailable'
                        : 'Loading version…'
                  : 'Version ${info.version} · Build ${info.buildNumber}',
              key: const ValueKey('about-version'),
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Source and licenses'),
          const SizedBox(height: 8),
          const Text(
            'Suchi Companion is available under the GNU Affero General Public '
            'License v3.0. Commercial licensing is available for users who '
            'cannot accept it.',
          ),
          const SizedBox(height: 8),
          _externalLink(
            key: const ValueKey('about-source'),
            icon: Icons.code,
            title: 'Source code',
            uri: _sourceUri,
          ),
          ListTile(
            key: const ValueKey('about-licenses'),
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open-source licenses'),
            subtitle: const Text('Dependencies and bundled fonts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLicenses(info),
          ),
          const SizedBox(height: 16),
          const SectionLabel('Help and policies'),
          const SizedBox(height: 8),
          _externalLink(
            key: const ValueKey('about-privacy'),
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy policy',
            uri: _privacyUri,
          ),
          _externalLink(
            key: const ValueKey('about-support'),
            icon: Icons.help_outline,
            title: 'Support',
            uri: _supportUri,
          ),
          _externalLink(
            key: const ValueKey('about-security'),
            icon: Icons.security_outlined,
            title: 'Security',
            uri: _securityUri,
          ),
        ],
      );
    },
  );
}
