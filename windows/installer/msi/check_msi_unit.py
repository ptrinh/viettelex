#!/usr/bin/env python3
"""Unit tests for check_msi.py's rules on plain data (no MSI needed). Each case is a
real VietTelex release bug."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_msi import ca_problems, first_key_order_problem  # noqa: E402

GOOD_SEQ = {'CostFinalize': 1000, 'InstallInitialize': 1500, 'RemoveFiles': 3500, 'InstallFinalize': 6600,
            'SetVtxExe': 1010, 'CleanupUser': 3400, 'SetupUser': 6610, 'LaunchApp': 6620}
GOOD_CAS = {
    'SetVtxExe': {'Type': 51, 'Source': 'VTXEXE', 'Target': '[INSTALLFOLDER]VietTelex.exe'},
    'SetupUser': {'Type': 114, 'Source': 'VTXEXE', 'Target': '--setup-user'},
    'LaunchApp': {'Type': 242, 'Source': 'VTXEXE', 'Target': '--background'},
    'CleanupUser': {'Type': 1138, 'Source': 'VTXEXE', 'Target': '--cleanup-user'},
}
FILES = {'VietTelexExe'}
DIRS = {'INSTALLFOLDER', 'TARGETDIR'}


def run(cas=None, seq=None):
    return ca_problems(cas or GOOD_CAS, {'InstallExecuteSequence': seq or GOOD_SEQ}, FILES, DIRS)


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


if __name__ == '__main__':
    unittest.main()
