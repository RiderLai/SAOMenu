#!/usr/bin/env python3
"""Validate a SAO Menu config. Usage: validate.py [path]  (default: ~/.config/sao-menu/config.json)

Prints errors (the app would reject or mis-run the config) and warnings
(likely mistakes), then OK or FAILED. Exits 1 on errors.
"""
import json
import os
import re
import sys

ICONS = {
    "user", "users", "message", "map", "gear", "folder", "file", "star", "home", "download",
    "desktop", "grid", "list", "code", "terminal", "globe", "image", "music", "book", "heart",
    "logout", "sword",
}
ACTION_FIELDS = {
    "open": {"path"},
    "app": {"app"},
    "url": {"url"},
    "terminal": set(),
    "settings": set(),
    "quit": set(),
}
MODIFIERS = {"cmd", "command", "alt", "option", "opt", "ctrl", "control", "shift"}
KEYS = set("abcdefghijklmnopqrstuvwxyz0123456789=-[]';\\,/.`") | {
    "return", "enter", "tab", "space", "escape", "esc", *(f"f{i}" for i in range(1, 13)),
}
APP_DIRS = [
    "/Applications", "/System/Applications", "/System/Applications/Utilities",
    "/Applications/Utilities", os.path.expanduser("~/Applications"),
    "/System/Library/CoreServices", "/System/Library/CoreServices/Applications",
]

errors, warnings = [], []


def app_exists(name):
    if "/" in name:
        return os.path.exists(os.path.expanduser(name))
    if re.fullmatch(r"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+){2,}", name):
        return True  # looks like a bundle id; can't cheaply resolve it here
    file = name if name.endswith(".app") else name + ".app"
    return any(os.path.exists(os.path.join(d, file)) for d in APP_DIRS)


def check_icon(icon, where):
    if not isinstance(icon, str) or not icon:
        errors.append(f"{where}: icon must be a non-empty string")
    elif icon not in ICONS and re.fullmatch(r"[a-z]{3,}", icon):
        warnings.append(f"{where}: icon '{icon}' is not a built-in name and will show as its first two letters")


def check_action(action, where):
    if not isinstance(action, dict):
        errors.append(f"{where}: action must be an object")
        return
    kind = action.get("type", "open")
    if kind not in ACTION_FIELDS:
        errors.append(f"{where}: unknown action type '{kind}'")
        return
    for key in ACTION_FIELDS[kind]:
        if not isinstance(action.get(key), str) or not action[key].strip():
            errors.append(f"{where}: action type '{kind}' needs a non-empty '{key}'")
    for key in ("path", "cwd"):
        value = action.get(key)
        if isinstance(value, str) and value and not os.path.exists(os.path.expanduser(value)):
            warnings.append(f"{where}: {key} does not exist: {value}")
    app = action.get("app")
    if isinstance(app, str) and app and not app_exists(app):
        warnings.append(f"{where}: app not found: {app}")
    url = action.get("url")
    if isinstance(url, str) and url and " " in url.strip():
        errors.append(f"{where}: url contains a space: {url}")
    if "confirm" in action and not isinstance(action["confirm"], (str, bool)):
        errors.append(f"{where}: confirm must be true or a string")


def check_items(items, where, top):
    if not isinstance(items, list):
        errors.append(f"{where}: must be a list")
        return
    for i, node in enumerate(items):
        if not isinstance(node, dict):
            errors.append(f"{where}[{i}]: must be an object")
            continue
        label = node.get("label")
        here = f"{where}[{i}] ({label or 'no label'})"
        if not isinstance(label, str) or not label:
            warnings.append(f"{here}: missing label")
        elif len(label) > 22 and not top:
            warnings.append(f"{here}: label is longer than 22 characters and may be cut off")
        if "icon" in node:
            check_icon(node["icon"], here)
        elif top:
            warnings.append(f"{here}: top-level entry has no icon (a star is shown)")
        has_items, has_action = "items" in node, "action" in node
        if has_items and has_action:
            errors.append(f"{here}: has both items and action; the action is ignored unless items is empty")
        elif not has_items and not has_action:
            errors.append(f"{here}: needs either items or action")
        if has_items:
            check_items(node["items"], here + ".items", False)
        if has_action:
            check_action(node["action"], here)


def check_hotkey(text):
    parts = [p.strip() for p in text.lower().split("+")]
    keys = [p for p in parts if p not in MODIFIERS]
    if len(keys) != 1 or keys[0] not in KEYS:
        errors.append(f"hotkey '{text}' is not modifiers plus one known key")
    elif len(parts) == 1 and not re.fullmatch(r"f\d+", keys[0]):
        errors.append(f"hotkey '{text}' needs at least one modifier")


def main():
    path = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/.config/sao-menu/config.json")
    try:
        with open(path, encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        print(f"error: cannot read {path}: {e}\nFAILED")
        return 1
    if not isinstance(cfg, dict):
        print("error: the top level must be a JSON object\nFAILED")
        return 1

    check_items(cfg.get("menu", []), "menu", True)
    if isinstance(cfg.get("menu"), list) and len(cfg["menu"]) > 6:
        warnings.append(f"menu has {len(cfg['menu'])} top-level icons; more than 6 may not fit on small screens")
    if "hotkey" in cfg:
        if isinstance(cfg["hotkey"], str):
            check_hotkey(cfg["hotkey"])
        else:
            errors.append("hotkey must be a string")
    for key in ("sound", "intro"):
        if key in cfg and not isinstance(cfg[key], bool):
            errors.append(f"{key} must be true or false")
    volume = cfg.get("volume", 0.7)
    if isinstance(volume, bool) or not isinstance(volume, (int, float)) or not 0 <= volume <= 1:
        errors.append("volume must be a number from 0 to 1")
    if cfg.get("mouseGesture", "off") not in ("off", "right", "both", True, False):
        errors.append("mouseGesture must be 'right', 'both' or 'off'")
    if cfg.get("trackpad", "off") not in ("off", "tap3", "tap4", "tap5"):
        errors.append("trackpad must be 'tap3', 'tap4', 'tap5' or 'off'")

    for msg in errors:
        print("error:", msg)
    for msg in warnings:
        print("warning:", msg)
    print("FAILED" if errors else "OK")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
