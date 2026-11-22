import copy
import io
import unittest
from contextlib import redirect_stdout
from unittest.mock import call, patch

import nextdns_sync


class SecuritySyncTests(unittest.TestCase):
    def test_sync_preserves_each_targets_nrd_without_changing_source(self):
        source = {"nrd": False, "dnsRebinding": False, "typosquatting": True}
        original = copy.deepcopy(source)
        profiles = {
            "main": {"security": source},
            "first": {"security": {"nrd": True}},
            "second": {"security": {"nrd": False}},
            "third": {"security": {}},
        }
        with (
            patch.object(nextdns_sync, "PROFILE_MAIN", "main"),
            patch.object(nextdns_sync, "PROFILE_SYNC_LIST", ["first", "second", "third"]),
            patch.object(
                nextdns_sync,
                "fetch_profile_settings",
                side_effect=lambda profile: {"data": profiles[profile]},
            ),
            patch.object(nextdns_sync, "update_profile_settings") as update,
        ):
            nextdns_sync.sync_profiles(["security"])

        self.assertEqual(
            update.call_args_list,
            [
                call("first", {**source, "nrd": True}, "security", timeout=10),
                call("second", source, "security", timeout=10),
                call(
                    "third",
                    {"dnsRebinding": False, "typosquatting": True},
                    "security",
                    timeout=10,
                ),
            ],
        )
        self.assertEqual(source, original)


class PrivacySyncTests(unittest.TestCase):
    def setUp(self):
        self.source = {
            "blocklists": [{"id": "hagezi-multi-normal", "name": "Normal"}, {"id": "oisd"}],
            "allowAffiliate": True,
        }
        self.profiles = {
            "main": {"name": "Main", "privacy": self.source},
            "tailnet": {
                "name": "Tailnet",
                "privacy": {
                    **self.source,
                    "blocklists": [{"id": "hagezi-multi-pro", "name": "Pro"}, {"id": "oisd"}],
                },
            },
            "other": {"name": "Other", "privacy": copy.deepcopy(self.source)},
        }
        for name, value in (
            ("PROFILE_MAIN", "main"),
            ("PROFILE_TAILNET", "tailnet"),
            ("PROFILE_SYNC_LIST", ["tailnet", "other"]),
        ):
            self.enterContext(patch.object(nextdns_sync, name, value))
        self.enterContext(patch.object(
            nextdns_sync, "fetch_profile_settings",
            side_effect=lambda profile: {"data": self.profiles[profile]},
        ))

    def test_tailnet_override_does_not_change_main_or_other_profiles(self):
        original = copy.deepcopy(self.source)
        with patch.object(nextdns_sync, "update_profile_settings") as update:
            nextdns_sync.sync_profiles(["privacy"])
        self.assertEqual(update.call_args_list, [
            call("tailnet", {"allowAffiliate": True, "blocklists": [
                {"id": "hagezi-multi-pro"}, {"id": "oisd"},
            ]}, "privacy", timeout=10),
            call("other", {"allowAffiliate": True, "blocklists": [
                {"id": "hagezi-multi-normal"}, {"id": "oisd"},
            ]}, "privacy", timeout=10),
        ])
        self.assertEqual(self.source, original)

    def test_diff_accepts_expected_tailnet_tier(self):
        with redirect_stdout(io.StringIO()) as output:
            nextdns_sync.diff_profiles()
        self.assertIn("privacy: IN SYNC", output.getvalue())

    def test_diff_reports_wrong_tailnet_tier(self):
        self.profiles["tailnet"]["privacy"] = copy.deepcopy(self.source)
        with redirect_stdout(io.StringIO()) as output:
            nextdns_sync.diff_profiles()
        self.assertIn("privacy: DIFFERS on Tailnet", output.getvalue())


class ProfileDiscoveryTests(unittest.TestCase):
    def test_targets_exclude_main_skip_empty_and_sort_by_name(self):
        environ = {
            "NEXTDNS_PROFILE_MAIN": "m",
            "NEXTDNS_PROFILE_SITE_B": "b2",
            "NEXTDNS_PROFILE_SITE_A": " a1 ",
            "NEXTDNS_PROFILE_TAILNET": "t3",
            "NEXTDNS_PROFILE_EMPTY": "  ",
            "NEXTDNS_API_KEY": "k",
        }
        self.assertEqual(nextdns_sync.profile_sync_ids(environ), ["a1", "b2", "t3"])

    def test_unset_check_name_logs_one_warning_and_skips(self):
        with (
            patch.object(nextdns_sync, "TAILNET_CHECK_NAME", None),
            patch.object(nextdns_sync.requests, "get") as get,
            self.assertLogs(nextdns_sync.logger, level="WARNING") as logs,
        ):
            nextdns_sync.verify_tailnet_resolution(["a1"])
        get.assert_not_called()
        self.assertEqual(len(logs.output), 1)


if __name__ == "__main__":
    unittest.main()
