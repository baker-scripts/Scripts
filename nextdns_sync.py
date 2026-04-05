import argparse
import json
import logging
import os
import requests
from typing import Optional, Dict, List, Union

# Configuration
TIMEOUT = 10
NEXT_DNS_API = "https://api.nextdns.io"
API_PROFILE_ROUTE = "profiles"

API_KEY = os.getenv("NEXTDNS_API_KEY")

PROFILE_MAIN = os.getenv("NEXTDNS_PROFILE_MAIN")
PROFILE_RPM = os.getenv("NEXTDNS_PROFILE_RPM")
PROFILE_BETSY = os.getenv("NEXTDNS_PROFILE_BETSY")
PROFILE_LEONA = os.getenv("NEXTDNS_PROFILE_LEONA")
PROFILE_HURLEY = os.getenv("NEXTDNS_PROFILE_HURLEY")
PROFILE_TAILNET = os.getenv("NEXTDNS_PROFILE_TAILNET")
PROFILE_SYNC_LIST = [
    PROFILE_RPM,
    PROFILE_BETSY,
    PROFILE_LEONA,
    PROFILE_HURLEY,
    PROFILE_TAILNET,
]

# Rewrites that are site-specific (Main only), not synced to other profiles
SITE_SPECIFIC_REWRITES = os.getenv("NEXTDNS_SITE_SPECIFIC_REWRITES", "").split(",")

# Settings to enforce across all synced profiles
SETTINGS_SYNC = {
    "bav": True,
}
SETTINGS_PERFORMANCE_SYNC = {
    "cnameFlattening": False,
    "ecs": True,
    "cacheBoost": True,
}
SETTINGS_LOGS_SYNC = {
    "retention": 604800,  # 7 days
}

# Keys that should NOT be synced for security (preserved per-profile)
SECURITY_PRESERVE_KEYS = ["nrd"]

TLD_BAN_LIST = sorted(
    set(
        [
            "autos",
            "best",
            "bid",
            "bio",
            "boats",
            "boston",
            "boutique",
            "charity",
            "christmas",
            "dance",
            "fishing",
            "hair",
            "haus",
            "loan",
            "loans",
            "men",
            "mom",
            "name",
            "review",
            "rip",
            "skin",
            "support",
            "tattoo",
            "tokyo",
            "voto",
            "sbs",
            "ooo",
            "gdn",
            "zip",
        ]
    )
)
TLD_BAN_LIST_DICT = [{"id": tld} for tld in TLD_BAN_LIST]
TLD_BAN_PAYLOAD = {"tlds": TLD_BAN_LIST_DICT}

HEADERS = {"X-Api-Key": API_KEY, "Content-Type": "application/json"}


def setup_logger(name: str) -> logging.Logger:
    """Sets up a logger with a given name."""
    logger = logging.getLogger(name)
    logger.setLevel(logging.DEBUG)  # Set to DEBUG to capture all messages

    # Create a stream handler and set its format
    handler = logging.StreamHandler()
    formatter = logging.Formatter("%(asctime)s|%(levelname)s|%(message)s")
    handler.setFormatter(formatter)

    # Add the handler if it doesn't already exist
    if not logger.hasHandlers():
        logger.addHandler(handler)

    return logger


logger = setup_logger(__name__)


def api_request(
    method: str,
    url: str,
    headers: Optional[Dict[str, str]] = None,
    data: Optional[Union[Dict, str]] = None,
    json: Optional[Dict] = None,
    timeout: int = TIMEOUT,
) -> requests.Response:
    """
    Makes an HTTP request and handles errors.

    Args:
        method (str): HTTP method (GET, POST, PATCH, etc.).
        url (str): The endpoint URL.
        headers (dict, optional): Headers to include in the request.
        data (dict, optional): Data to send in the body of the request (for POST, PATCH).
        json (dict, optional): JSON data to send in the body of the request (for POST, PATCH).
        timeout (int): Timeout for the request.

    Returns:
        Response: The HTTP response object.

    Raises:
        Exception: If the request returns a 400 Bad Request, or any other HTTP error.
    """
    logger.info("[API CALL] USING %s", method)
    if data is not None:
        logger.info(
            "[API CALL] Using payload %s", json.dumps(data, separators=(",", ":"))
        )

    try:
        response = requests.request(
            method, url, headers=headers, data=data, json=json, timeout=timeout
        )
        response.raise_for_status()
        if response.status_code not in (200, 204):
            logger.info("[API CALL] Response: %s", response.text)
        else:
            logger.info("[API CALL] Request succeeded")
        return response
    except requests.exceptions.RequestException as e:
        logger.error("[API CALL] Request failed: %s", e)
        raise


def fetch_profile_settings(profile_id: str) -> Dict:
    """Fetches the settings for a given profile ID."""
    url = f"{NEXT_DNS_API}/{API_PROFILE_ROUTE}/{profile_id}/"
    response = api_request("GET", url, headers=HEADERS)
    return response.json()


def filter_blocklists(blocklists: List[Dict[str, str]]) -> List[Dict[str, str]]:
    """Filter blocklists to only include the 'id' field."""
    return [
        {"id": blocklist.get("id")} for blocklist in blocklists if blocklist.get("id")
    ]


def build_payload(data: Dict, keys_to_sync: List[str]) -> Dict:
    """Build payload for syncing settings."""
    return {key: data.get(key, []) for key in keys_to_sync if data.get(key) is not None}


def alpha_sort_lists(data: Dict) -> Dict:
    """Sorts the allowlist and denylist alphabetically by 'id'."""
    if "allowlist" in data:
        data["allowlist"] = sorted(data["allowlist"], key=lambda x: x["id"])
    if "denylist" in data:
        data["denylist"] = sorted(data["denylist"], key=lambda x: x["id"])
    return data


def update_profile_settings(
    profile_id: str, payload: Dict, route: Optional[str] = None, method: str = "PATCH"
) -> requests.Response:
    """Updates the settings for a given profile ID."""
    logger.info(
        "[UPDATE-PROFILE] Updating profile settings for profile %s...", profile_id
    )
    url = f"{NEXT_DNS_API}/{API_PROFILE_ROUTE}/{profile_id}/{route if route else 'settings'}"
    if payload is None:
        raise ValueError(
            "[UPDATE-PROFILE] Payload cannot be None. Please provide a valid payload."
        )
    return api_request(method, url, headers=HEADERS, json=payload)


def update_array_settings(
    profile_id: str,
    key: str,
    payload: List[Dict],
    route: Optional[str] = None,
    method: str = "PUT",
) -> requests.Response:
    """Updates array settings like denylist or blocklists."""
    logger.info("[UPDATE-ARRAY] Updating array settings for profile %s...", profile_id)
    url = f"{NEXT_DNS_API}/{API_PROFILE_ROUTE}/{profile_id}/{route if route else key}"
    if not isinstance(payload, list):
        raise ValueError("[UPDATE-ARRAY] Payload must be a list for array updates.")
    logger.info("[UPDATE-ARRAY] Url for [%s] is %s", profile_id, url)
    return api_request(method, url, headers=HEADERS, json=payload)


def update_security_settings(
    profile_id: str, tlds_payload: Dict, method: str = "PATCH"
) -> requests.Response:
    """Updates security settings for the profile."""
    url = f"{NEXT_DNS_API}/{API_PROFILE_ROUTE}/{profile_id}/security"
    logger.info(
        "[UPDATE-SECURITY] Updating security settings for profile %s...", profile_id
    )
    try:
        response = api_request(method, url, headers=HEADERS, json=tlds_payload)
        logger.info("[UPDATE-SECURITY] Request succeeded")
        return response
    except Exception as e:
        logger.error("[UPDATE-SECURITY] Failed to update security settings: %s", e)
        raise


def sync_rewrites(source_id: str, target_ids: List[str]) -> None:
    """Syncs rewrites from source profile to target profiles, skipping site-specific ones."""
    source = fetch_profile_settings(source_id)["data"]
    source_rewrites = source.get("rewrites", [])
    global_rewrites = [
        r for r in source_rewrites if r.get("name", "") not in SITE_SPECIFIC_REWRITES
    ]
    logger.info("[REWRITE-SYNC] %d global rewrites from source", len(global_rewrites))

    for target_id in target_ids:
        if target_id is None:
            continue
        target = fetch_profile_settings(target_id)["data"]
        existing = {r.get("name") for r in target.get("rewrites", [])}
        existing_by_name = {r.get("name"): r for r in target.get("rewrites", [])}

        for rw in global_rewrites:
            name = rw.get("name", "")
            content = rw.get("content", "")
            if name not in existing:
                url = f"{NEXT_DNS_API}/{API_PROFILE_ROUTE}/{target_id}/rewrites"
                try:
                    api_request(
                        "POST",
                        url,
                        headers=HEADERS,
                        json={"name": name, "content": content},
                    )
                    logger.info("[REWRITE-SYNC] Added %s to %s", name, target_id)
                except Exception as e:
                    logger.error(
                        "[REWRITE-SYNC] Failed to add %s to %s: %s", name, target_id, e
                    )
            elif existing_by_name.get(name, {}).get("content") != content:
                rid = existing_by_name[name].get("id")
                if rid:
                    url = (
                        f"{NEXT_DNS_API}/{API_PROFILE_ROUTE}/{target_id}/rewrites/{rid}"
                    )
                    try:
                        api_request(
                            "PATCH", url, headers=HEADERS, json={"content": content}
                        )
                        logger.info("[REWRITE-SYNC] Updated %s on %s", name, target_id)
                    except Exception as e:
                        logger.error(
                            "[REWRITE-SYNC] Failed to update %s on %s: %s",
                            name,
                            target_id,
                            e,
                        )

        # Remove rewrites on target that don't exist on source (except site-specific)
        source_names = {r.get("name") for r in global_rewrites}
        for rw in target.get("rewrites", []):
            name = rw.get("name", "")
            if name not in source_names and name not in SITE_SPECIFIC_REWRITES:
                rid = rw.get("id")
                if rid:
                    url = (
                        f"{NEXT_DNS_API}/{API_PROFILE_ROUTE}/{target_id}/rewrites/{rid}"
                    )
                    try:
                        api_request("DELETE", url, headers=HEADERS)
                        logger.info(
                            "[REWRITE-SYNC] Removed stale %s from %s", name, target_id
                        )
                    except Exception as e:
                        logger.error(
                            "[REWRITE-SYNC] Failed to remove %s from %s: %s",
                            name,
                            target_id,
                            e,
                        )


def sync_settings(target_ids: List[str]) -> None:
    """Syncs settings (bav, performance, logs) to target profiles."""
    for target_id in target_ids:
        if target_id is None:
            continue
        try:
            if SETTINGS_SYNC:
                update_profile_settings(target_id, SETTINGS_SYNC, "settings")
            if SETTINGS_PERFORMANCE_SYNC:
                update_profile_settings(
                    target_id, SETTINGS_PERFORMANCE_SYNC, "settings/performance"
                )
            if SETTINGS_LOGS_SYNC:
                update_profile_settings(target_id, SETTINGS_LOGS_SYNC, "settings/logs")
            logger.info("[SETTINGS-SYNC] Updated settings for %s", target_id)
        except Exception as e:
            logger.error("[SETTINGS-SYNC] Failed for %s: %s", target_id, e)


def build_security_payload(source_security: Dict, target_security: Dict) -> Dict:
    """Build security payload preserving per-profile keys like NRD."""
    payload = {
        k: v for k, v in source_security.items() if k not in SECURITY_PRESERVE_KEYS
    }
    for key in SECURITY_PRESERVE_KEYS:
        if key in target_security:
            payload[key] = target_security[key]
    return payload


def diff_profiles() -> None:
    """Shows differences between Main and all synced profiles."""
    source = fetch_profile_settings(PROFILE_MAIN)["data"]
    source_name = source.get("name", PROFILE_MAIN)

    all_profiles = {PROFILE_MAIN: source}
    profile_names = {PROFILE_MAIN: source_name}

    for pid in PROFILE_SYNC_LIST:
        if pid is None:
            continue
        data = fetch_profile_settings(pid)["data"]
        all_profiles[pid] = data
        profile_names[pid] = data.get("name", pid)

    sections = [
        "security",
        "privacy",
        "parentalControl",
        "denylist",
        "allowlist",
        "settings",
    ]

    print(f"\n{'=' * 60}")
    print(f"  NextDNS Profile Diff — Source: {source_name} ({PROFILE_MAIN})")
    print(f"{'=' * 60}")

    for section in sections:
        source_val = json.dumps(source.get(section, {}), sort_keys=True)
        diffs = []
        for pid in PROFILE_SYNC_LIST:
            if pid is None or pid not in all_profiles:
                continue
            target_val = json.dumps(all_profiles[pid].get(section, {}), sort_keys=True)
            if source_val != target_val:
                diffs.append(profile_names[pid])
        if diffs:
            print(f"\n  {section}: DIFFERS on {', '.join(diffs)}")
            for pid in PROFILE_SYNC_LIST:
                if pid is None or pid not in all_profiles:
                    continue
                name = profile_names[pid]
                if name not in diffs:
                    continue
                src = source.get(section, {})
                tgt = all_profiles[pid].get(section, {})
                if isinstance(src, dict):
                    for key in sorted(set(list(src.keys()) + list(tgt.keys()))):
                        sv = json.dumps(src.get(key), sort_keys=True)
                        tv = json.dumps(tgt.get(key), sort_keys=True)
                        if sv != tv:
                            print(
                                f"    {name}.{key}: {source_name}={sv[:60]}  {name}={tv[:60]}"
                            )
                elif isinstance(src, list):
                    src_ids = {i.get("id", "") for i in src if isinstance(i, dict)}
                    tgt_ids = {i.get("id", "") for i in tgt if isinstance(i, dict)}
                    only_src = src_ids - tgt_ids
                    only_tgt = tgt_ids - src_ids
                    if only_src:
                        print(f"    Only in {source_name}: {sorted(only_src)}")
                    if only_tgt:
                        print(f"    Only in {name}: {sorted(only_tgt)}")
        else:
            print(f"\n  {section}: IN SYNC")

    # Rewrites diff
    source_rw = {r["name"]: r["content"] for r in source.get("rewrites", [])}
    global_rw = {k: v for k, v in source_rw.items() if k not in SITE_SPECIFIC_REWRITES}
    rw_diffs = []
    for pid in PROFILE_SYNC_LIST:
        if pid is None or pid not in all_profiles:
            continue
        name = profile_names[pid]
        target_rw = {
            r["name"]: r["content"] for r in all_profiles[pid].get("rewrites", [])
        }
        missing = set(global_rw.keys()) - set(target_rw.keys())
        extra = (
            set(target_rw.keys()) - set(global_rw.keys()) - set(SITE_SPECIFIC_REWRITES)
        )
        wrong = {
            k for k in global_rw if k in target_rw and global_rw[k] != target_rw[k]
        }
        if missing or extra or wrong:
            rw_diffs.append(name)
            if missing:
                print(f"    {name} missing: {sorted(missing)}")
            if extra:
                print(f"    {name} extra: {sorted(extra)}")
            if wrong:
                print(f"    {name} wrong target: {sorted(wrong)}")
    if not rw_diffs:
        print("\n  rewrites: IN SYNC")
    else:
        print(f"\n  rewrites: DIFFERS on {', '.join(rw_diffs)}")

    # Summary table
    print(f"\n{'=' * 60}")
    print(
        f"  {'Profile':10s} {'Rewrites':>9s} {'Allow':>6s} {'Deny':>5s} {'BLists':>7s}"
    )
    print(f"  {'-' * 40}")
    for pid in [PROFILE_MAIN] + PROFILE_SYNC_LIST:
        if pid is None or pid not in all_profiles:
            continue
        d = all_profiles[pid]
        name = profile_names[pid]
        rw = len(d.get("rewrites", []))
        al = len(d.get("allowlist", []))
        dn = len(d.get("denylist", []))
        bl = len(d.get("privacy", {}).get("blocklists", []))
        print(f"  {name:10s} {rw:>9d} {al:>6d} {dn:>5d} {bl:>7d}")
    print()


def sync_profiles(keys_to_sync: List[str], payload: Optional[Dict] = None) -> None:
    """Syncs settings from the main profile to the target profiles."""
    try:
        settings = fetch_profile_settings(PROFILE_MAIN)
        data = settings["data"]
        logger.info("[SYNC] Settings from Profile %s", PROFILE_MAIN)

        if payload is None:
            payload = build_payload(data, keys_to_sync)

        payload = alpha_sort_lists(payload)
        logger.debug(
            "[SYNC] Generated Payload: %s", json.dumps(payload, separators=(",", ":"))
        )

        for profile_id in PROFILE_SYNC_LIST:
            if profile_id is not None:
                for key in keys_to_sync:
                    if key in payload:
                        key_payload = payload[key]
                        logger.info("[SYNC] Using Key [%s]", key)
                        if "blocklists" in key_payload:
                            logger.debug("[SYNC] [blocklists] to be filtered")
                            key_payload["blocklists"] = filter_blocklists(
                                key_payload["blocklists"]
                            )
                        try:
                            if isinstance(key_payload, list):
                                update_array_settings(profile_id, key, key_payload)
                            else:
                                update_profile_settings(profile_id, key_payload, key)
                            logger.info(
                                "[SYNC] Successfully updated %s for profile %s.",
                                key,
                                profile_id,
                            )
                        except Exception as e:
                            logger.error(
                                "[SYNC] Failed to update %s for profile %s: %s",
                                key,
                                profile_id,
                                e,
                            )

    except Exception as e:
        logger.error("[SYNC] Failed to sync profiles: %s", e)
        raise


def output_profile_settings(profile_id: str = PROFILE_MAIN) -> None:
    """Fetches and prints the settings of a profile."""
    try:
        settings = fetch_profile_settings(profile_id)
        print(json.dumps(settings, indent=2))
    except Exception as e:
        logger.error("[GET] Failed to fetch profile settings: %s", e)


def main():
    parser = argparse.ArgumentParser(description="NextDNS profile sync and update tool")
    parser.add_argument(
        "action",
        choices=["sync", "update", "get", "diff"],
        help="Action to perform: 'sync' to sync profiles, 'update' to update security, 'get' to print profile settings, 'diff' to show differences",
    )
    parser.add_argument(
        "--profile",
        default=PROFILE_MAIN,
        help="Profile ID to get settings for (default: MAIN)",
    )
    args = parser.parse_args()

    if args.action == "sync":
        keys_to_sync = [
            "allowlist",
            "denylist",
            "parentalControl",
            "security",
            "privacy",
        ]
        logging.info("Starting profile sync (lists + security + privacy)...")
        sync_profiles(keys_to_sync)
        logging.info("Syncing rewrites...")
        sync_rewrites(PROFILE_MAIN, [p for p in PROFILE_SYNC_LIST if p])
        logging.info("Syncing settings...")
        sync_settings([p for p in PROFILE_SYNC_LIST if p])

    elif args.action == "update":
        logging.info("Updating main profile security settings (TLD ban list)...")
        update_security_settings(PROFILE_MAIN, TLD_BAN_PAYLOAD)

    elif args.action == "get":
        output_profile_settings(args.profile)

    elif args.action == "diff":
        diff_profiles()

    logging.info("Done.")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
    main()
