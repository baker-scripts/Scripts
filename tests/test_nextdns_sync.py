import copy
import unittest
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


if __name__ == "__main__":
    unittest.main()
