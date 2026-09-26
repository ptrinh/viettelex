#!/usr/bin/env python3
"""Unit tests for check_msi.py's rules on plain data (no MSI needed). Each case is a
real VietTelex release bug."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_msi import ca_problems, file_version_problems, first_key_order_problem, ice63_problems  # noqa: E402

GOOD_SEQ = {'CostFinalize': 1000, 'InstallValidate': 1400, 'InstallInitialize': 1500, 'RemoveFiles': 3500,
            'InstallFiles': 4000, 'InstallExecute': 6590, 'RemoveExistingProducts': 6595, 'InstallFinalize': 6600,
            'SetVtxExe': 1010, 'QuitApp': 1020, 'ReleaseTip': 3450, 'CleanupUser': 3400, 'SetupUser': 6610,
            'LaunchApp': 6620}
GOOD_CAS = {
    'SetVtxExe': {'Type': 51, 'Source': 'VTXEXE', 'Target': '[INSTALLFOLDER]VietTelex.exe'},
    'SetupUser': {'Type': 114, 'Source': 'VTXEXE', 'Target': '--setup-user'},
    'LaunchApp': {'Type': 242, 'Source': 'VTXEXE', 'Target': '--background'},
    'CleanupUser': {'Type': 1138, 'Source': 'VTXEXE', 'Target': '--cleanup-user'},
    'QuitApp': {'Type': 66, 'Source': 'SetupHelper', 'Target': '--quit-app'},
    'ReleaseTip': {'Type': 3138, 'Source': 'SetupHelper',
                   'Target': '--max-version 1.0.7 --release-tip "[INSTALLFOLDER]." "[INSTALLFOLDER86]."'},
}
BINARIES = {'SetupHelper'}
FILES = {'VietTelexExe'}
DIRS = {'INSTALLFOLDER', 'TARGETDIR'}


GOOD_COND = {'ReleaseTip': 'NOT UPGRADINGPRODUCTCODE'}


def run(cas=None, seq=None, binaries=None, cond=None):
    return ca_problems(cas or GOOD_CAS, {'InstallExecuteSequence': seq or GOOD_SEQ}, FILES, DIRS,
                       BINARIES if binaries is None else binaries,
                       {'InstallExecuteSequence': GOOD_COND if cond is None else cond})


class KeyOrder(unittest.TestCase):
    def test_sorted_ok(self):
        self.assertIsNone(first_key_order_problem([(1,), (5,), (9,)]))

    def test_v100_reused_low_id(self):  # 1.0.0: ids [98, 102, 207, 115, ...] -> error 2211
        self.assertEqual(first_key_order_problem([(98,), (102,), (207,), (115,)]), (3, 'out of order'))

    def test_duplicate(self):
        self.assertEqual(first_key_order_problem([(1, 2), (1, 2)]), (1, 'duplicate'))


class CustomActions(unittest.TestCase):
    def test_current_template_ok(self):
        self.assertEqual(run(), [])

    def test_v103_cleanup_before_costing(self):  # 1.0.3: error 2731 on uninstall
        cas = dict(GOOD_CAS, CleanupUser={'Type': 1106, 'Source': 'VietTelexExe', 'Target': '--cleanup-user'})
        p = run(cas, dict(GOOD_SEQ, CleanupUser=1))
        self.assertTrue(any('before CostFinalize' in x for x in p))
        self.assertTrue(any('after InstallInitialize' in x for x in p))

    def test_v104_filekey_forbidden(self):  # 1.0.4: error 2753 on repair
        cas = dict(GOOD_CAS, SetupUser={'Type': 82, 'Source': 'VietTelexExe', 'Target': '--setup-user'})
        self.assertTrue(any('FileKey' in x for x in run(cas)))

    def test_property_set_too_early(self):
        self.assertTrue(any('formats a directory' in x for x in run(seq=dict(GOOD_SEQ, SetVtxExe=900))))

    def test_property_never_set(self):
        seq = dict(GOOD_SEQ)
        del seq['SetVtxExe']
        self.assertTrue(any('nothing sets it' in x for x in run(seq=seq)))


class UpgradeInPlace(unittest.TestCase):  # 1.0.6: upgrade must not leave the old app running
    def test_quit_after_validate_rejected(self):
        self.assertTrue(any('QuitApp' in x for x in run(seq=dict(GOOD_SEQ, QuitApp=1450))))

    def test_quit_deferred_rejected(self):
        cas = dict(GOOD_CAS, QuitApp={'Type': 66 + 1024, 'Source': 'SetupHelper', 'Target': '--quit-app'})
        self.assertTrue(any('immediate' in x for x in run(cas)))

    def test_release_after_file_actions_rejected(self):
        self.assertTrue(any('before RemoveFiles' in x for x in run(seq=dict(GOOD_SEQ, ReleaseTip=3900))))

    def test_release_impersonated_rejected(self):
        cas = dict(GOOD_CAS, ReleaseTip={'Type': 66 + 1024, 'Source': 'SetupHelper',
                                         'Target': '--release-tip "[INSTALLFOLDER]."'})
        self.assertTrue(any('not impersonated' in x for x in run(cas)))

    def test_release_dir_trailing_backslash_rejected(self):  # "C:\dir\" escapes the quote
        cas = dict(GOOD_CAS, ReleaseTip={'Type': 3138, 'Source': 'SetupHelper',
                                         'Target': '--release-tip "[INSTALLFOLDER]" "[INSTALLFOLDER86]"'})
        self.assertTrue(any('escapes' in x for x in run(cas)))

    def test_release_runs_in_old_package_during_upgrade_rejected(self):  # found in the 1.0.6->1.0.7 run
        self.assertTrue(any('NOT UPGRADINGPRODUCTCODE' in x for x in run(cond={})))

    def test_release_without_max_version_rejected(self):
        cas = dict(GOOD_CAS, ReleaseTip={'Type': 3138, 'Source': 'SetupHelper',
                                         'Target': '--release-tip "[INSTALLFOLDER]."'})
        self.assertTrue(any('--max-version' in x for x in run(cas)))

    def test_missing_binary_rejected(self):
        self.assertTrue(any('Binary source' in x for x in run(binaries=set())))


class Ice63(unittest.TestCase):  # RemoveExistingProducts positions (error 2613 in 1.0.6)
    def seq(self, **kw):
        return dict({'InstallValidate': 1400, 'InstallInitialize': 1500, 'InstallExecute': 6590,
                     'InstallFinalize': 6600, 'ProcessComponents': 1600}, **kw)

    def test_v106_rejected(self):  # REP 1510 with ReleaseTip 1505 in between
        self.assertTrue(ice63_problems(self.seq(RemoveExistingProducts=1510, ReleaseTip=1505)))

    def test_legal_positions(self):
        for rep in (1401, 1501, 6595, 6700):
            self.assertEqual(ice63_problems(self.seq(RemoveExistingProducts=rep)), [], rep)

    def test_between_initialize_and_execute_rejected(self):
        self.assertTrue(ice63_problems(self.seq(RemoveExistingProducts=3000)))

    def test_execute_window_needs_install_execute(self):
        s = self.seq(RemoveExistingProducts=6595)
        del s['InstallExecute']
        self.assertTrue(ice63_problems(s))


class Ice77Ice12(unittest.TestCase):
    def test_deferred_outside_script_rejected(self):
        self.assertTrue(any('ICE77' in x for x in run(seq=dict(GOOD_SEQ, CleanupUser=6700))))

    def test_type51_directory_after_costfinalize_rejected(self):
        cas = dict(GOOD_CAS, SetDir={'Type': 51, 'Source': 'INSTALLFOLDER', 'Target': 'C:\\x'})
        self.assertTrue(any('ICE12' in x for x in run(cas, dict(GOOD_SEQ, SetDir=1100))))

    def test_type35_before_costfinalize_rejected(self):
        cas = dict(GOOD_CAS, SetDir={'Type': 35, 'Source': 'INSTALLFOLDER', 'Target': 'C:\\x'})
        self.assertTrue(any('ICE12' in x for x in run(cas, dict(GOOD_SEQ, SetDir=900))))


class FileVersions(unittest.TestCase):  # 1.0.8/1.0.9 kept the 1.0.7 exe (empty File.Version)
    def row(self, name, v='1.1.0.0', lang='1033'):
        return {'FileName': name, 'Version': v, 'Language': lang}

    def test_ok(self):
        self.assertEqual(file_version_problems([self.row('VIETTE~1.EXE|VietTelex.exe'),
                                                self.row('VietTelexTIP_1_1_0.dll')], '1.1.0.0'), [])

    def test_v109_empty_version_rejected(self):
        p = file_version_problems([self.row('VietTelex.exe', v=None, lang=None)], '1.1.0.0')
        self.assertTrue(any('Version is empty' in x for x in p))
        self.assertTrue(any('Language' in x for x in p))

    def test_wrong_version_rejected(self):
        self.assertTrue(file_version_problems([self.row('VietTelexTIP_1_1_0.dll', v='1.0.9.0')], '1.1.0.0'))

    def test_non_pe_files_ignored(self):
        self.assertEqual(file_version_problems([self.row('readme.txt', v=None, lang=None)], '1.1.0.0'), [])


if __name__ == '__main__':
    unittest.main()
