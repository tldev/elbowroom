import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
import json

spec = importlib.util.spec_from_file_location('release', Path(__file__).parents[2] / 'Scripts/release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_versions_reject_ambiguous_or_unsafe_input(self):
        for value in ['v1.2.3', '1.2', '01.2.3', '1.2.3-beta', '1.2.3;rm', '../1.2.3']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.version_tuple(value)
        self.assertGreater(release.version_tuple('1.10.0'), release.version_tuple('1.9.9'))

    def test_notes_select_exact_version_and_keep_subheadings(self):
        text = '## [1.1.0] - 2026-09-16\n\n### Added\n- Installer\n\n## [1.0.0] - 2026-09-01\n- Old\n'
        self.assertEqual(release.changelog_section(text, '1.1.0'), '### Added\n- Installer')
        for bad in [text + text, '## [1.1.0] - 2026-09-16\n\n### Added\n', text.replace('2026-09-16', '2026-99-99')]:
            with self.assertRaises(ValueError):
                release.changelog_section(bad, '1.1.0')

    def test_bump_promotes_unreleased_and_increments_build(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(release, 'ROOT', Path(tmp)):
            meta = dict(version='1.1.9', build=7, repository='tldev/elbowroom', bundle_id='dev.elbowroom.app')
            (Path(tmp) / 'release.json').write_text(json.dumps(meta))
            (Path(tmp) / 'CHANGELOG.md').write_text('# Changelog\n\n## [Unreleased]\n\n### Fixed\n- Better scan\n\n## [1.1.9] - 2026-09-01\n- Old\n')
            release.bump('minor')
            updated = release.metadata()
            self.assertEqual((updated['version'], updated['build']), ('1.2.0', 8))
            self.assertEqual(release.changelog_section((Path(tmp) / 'CHANGELOG.md').read_text(), '1.2.0'), '### Fixed\n- Better scan')
            with self.assertRaises(ValueError):
                release.bump('patch')

    def test_appcast_preserves_history_and_exact_signed_archive(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(release, 'ROOT', Path(tmp)):
            (Path(tmp) / 'appcast.xml').write_text('<rss><channel><title>Elbowroom</title><item><title>Old</title></item></channel></rss>')
            meta = dict(version='1.2.0', build=4, repository='tldev/elbowroom', minimum_macos='14.0')
            output = release.appcast(meta, 'signed+archive==', 1234, datetime(2026, 9, 16, tzinfo=timezone.utc))
            items = ET.fromstring(output).findall('channel/item')
            self.assertEqual(len(items), 2)
            self.assertEqual(items[1].findtext('title'), 'Old')
            self.assertEqual(items[0].findtext(f'{{{release.NS}}}version'), '4')
            enclosure = items[0].find('enclosure')
            self.assertEqual(enclosure.attrib['length'], '1234')
            self.assertEqual(enclosure.attrib[f'{{{release.NS}}}edSignature'], 'signed+archive==')
            self.assertIn('/v1.2.0/Elbowroom-v1.2.0.zip', enclosure.attrib['url'])

    def test_publish_rejects_dirty_or_preview_artifacts_before_network_calls(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(release, 'run') as run:
            folder = Path(tmp)
            for dirty, notarized in [(True, True), (False, False)]:
                (folder / 'release-manifest.json').write_text(json.dumps(dict(dirty=dirty, notarized=notarized)))
                with self.assertRaises(ValueError):
                    release.publish({}, folder)
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
