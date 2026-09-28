import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/suchi_widgets.dart';

final _websiteUri = Uri.parse('https://suchi.page/');

class AboutSuchiSheet extends StatefulWidget {
  const AboutSuchiSheet({super.key});

  @override
  State<AboutSuchiSheet> createState() => _AboutSuchiSheetState();
}

class _AboutSuchiSheetState extends State<AboutSuchiSheet> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  Future<void> _openWebsite() async {
    bool opened;
    try {
      opened = await launchUrl(
        _websiteUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suchi website could not be opened.')),
      );
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
          const SectionLabel('Licenses'),
          const SizedBox(height: 8),
          const Text(
            'Suchi Companion is available under the GNU Affero General Public '
            'License v3.0. Commercial licensing is available for users who '
            'cannot accept it.',
          ),
          const SizedBox(height: 8),
          ListTile(
            key: const ValueKey('about-licenses'),
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open-source licenses'),
            subtitle: const Text('Dependencies and bundled fonts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLicenses(info),
          ),
          const SizedBox(height: 16),
          const SectionLabel('Website'),
          const SizedBox(height: 8),
          ListTile(
            key: const ValueKey('about-website'),
            leading: const Icon(Icons.language_outlined),
            title: const Text('suchi.page'),
            subtitle: const Text('Privacy, support, security, and source'),
            trailing: const Icon(Icons.open_in_new),
            onTap: _openWebsite,
          ),
        ],
      );
    },
  );
}
