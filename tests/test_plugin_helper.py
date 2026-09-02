import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
HELPER = REPOSITORY / "bin" / "plugin-helper"
PYTHON = "/usr/bin/python3"

DEFAULT_CONFIG = {
    "disableOnUsbMouse": True,
    "disableOnBluetoothMouse": True,
    "disableOnOtherMouse": False,
    "restoreOnDisconnect": True,
    "notify": False,
    "ignoreNamePatterns": [],
}


def load_helper_module():
    loader = importlib.machinery.SourceFileLoader("mouse_touchpad_plugin_helper", str(HELPER))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class PluginHelperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir="/tmp")
        self.home = Path(self.temp.name)
        self.plugin = self.home / "plugin"
        self.plugin.mkdir(mode=0o700)
        self.fake_bin = self.home / "bin"
        self.fake_bin.mkdir(mode=0o700)
        self.env = os.environ.copy()
        self.env["HOME"] = str(self.home)
        self.env["PATH"] = f"{self.fake_bin}:{self.env.get('PATH', '')}"

    def tearDown(self):
        self.temp.cleanup()

    def run_helper(self, *arguments, timeout=3, check=True):
        return subprocess.run(
            [PYTHON, str(HELPER), *map(str, arguments)],
            env=self.env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            check=check,
            timeout=timeout,
        )

    def write_config(self, value):
        path = self.plugin / "config.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        path.chmod(0o600)
        return path

    def write_fake_command(self, name, source):
        path = self.fake_bin / name
        path.write_text(source, encoding="utf-8")
        path.chmod(0o700)
        return path

    def read_config(self):
        result = self.run_helper("config", self.plugin)
        self.assertLessEqual(len(result.stdout), 64 * 1024)
        data = json.loads(result.stdout)
        self.assertEqual(data.pop("schemaVersion"), 1)
        self.assertEqual(data.pop("type"), "config")
        return data

    def test_valid_config_is_normalized_and_bounded(self):
        expected = dict(DEFAULT_CONFIG)
        expected["notify"] = True
        expected["ignoreNamePatterns"] = ["virtual mouse", "receiver"]
        self.write_config(expected)
        self.assertEqual(self.read_config(), expected)

    def test_invalid_pattern_schema_falls_back_to_defaults(self):
        invalid = dict(DEFAULT_CONFIG)
        invalid["ignoreNamePatterns"] = [f"pattern-{index}" for index in range(33)]
        self.write_config(invalid)
        self.assertEqual(self.read_config(), DEFAULT_CONFIG)

        invalid["ignoreNamePatterns"] = ["control\u0001character"]
        self.write_config(invalid)
        self.assertEqual(self.read_config(), DEFAULT_CONFIG)

        invalid = dict(DEFAULT_CONFIG)
        invalid["unknownOption"] = True
        self.write_config(invalid)
        self.assertEqual(self.read_config(), DEFAULT_CONFIG)

    def test_oversized_symlink_and_fifo_config_are_refused_without_blocking(self):
        config = self.plugin / "config.json"
        config.write_bytes(b" " * (16 * 1024 + 1))
        config.chmod(0o600)
        self.assertEqual(self.read_config(), DEFAULT_CONFIG)

        config.unlink()
        target = self.home / "target.json"
        target.write_text('{"notify":true}', encoding="utf-8")
        config.symlink_to(target)
        self.assertEqual(self.read_config(), DEFAULT_CONFIG)
        self.assertEqual(target.read_text(encoding="utf-8"), '{"notify":true}')

        config.unlink()
        os.mkfifo(config, 0o600)
        started = time.monotonic()
        self.assertEqual(self.read_config(), DEFAULT_CONFIG)
        self.assertLess(time.monotonic() - started, 1.0)

    def test_managed_marker_is_private_atomic_and_does_not_follow_symlinks(self):
        self.run_helper("managed")
        marker = (
            self.home
            / ".local/state/omarchy/plugins/dev.ywenhao.mouse-touchpad-toggle/managed"
        )
        info = marker.stat()
        self.assertTrue(stat.S_ISREG(info.st_mode))
        self.assertEqual(stat.S_IMODE(info.st_mode), 0o600)
        state = json.loads(self.run_helper("state").stdout)
        self.assertEqual(state, {
            "schemaVersion": 1,
            "type": "state",
            "managed": True,
            "disabled": False,
        })

        target = self.home / "unrelated"
        target.write_text("do not modify", encoding="utf-8")
        marker.unlink()
        marker.symlink_to(target)
        self.run_helper("managed")
        self.assertEqual(target.read_text(encoding="utf-8"), "do not modify")
        self.assertTrue(stat.S_ISREG(marker.stat().st_mode))

        lock = marker.parent / ".lock"
        lock.unlink()
        lock.symlink_to(target)
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_helper("managed")
        self.assertEqual(target.read_text(encoding="utf-8"), "do not modify")

    def test_touchpad_state_cleanup_unlinks_only_the_named_entry(self):
        toggle_dir = self.home / ".local/state/omarchy/toggles/hypr"
        toggle_dir.mkdir(mode=0o700, parents=True)
        target = self.home / "unrelated-touchpad-state"
        target.write_text("keep", encoding="utf-8")
        state = toggle_dir / "touchpad-disabled-name"
        state.symlink_to(target)

        self.run_helper("clear-touchpad-state")
        self.assertFalse(state.exists())
        self.assertEqual(target.read_text(encoding="utf-8"), "keep")

    def test_touchpad_state_write_replaces_a_symlink_not_its_target(self):
        helper = load_helper_module()
        helper.HOME = self.home
        helper.STATE_PARENT = self.home / ".local/state/omarchy/plugins"
        helper.TOGGLE_PARENT = self.home / ".local/state/omarchy/toggles/hypr"
        helper.TOGGLE_PARENT.mkdir(mode=0o700, parents=True)

        target = self.home / "unrelated-touchpad-target"
        target.write_text("keep", encoding="utf-8")
        state = helper.TOGGLE_PARENT / helper.TOGGLE_NAME
        state.symlink_to(target)
        helper.write_touchpad_state("test-touchpad")

        self.assertEqual(target.read_text(encoding="utf-8"), "keep")
        self.assertTrue(stat.S_ISREG(state.stat().st_mode))
        self.assertEqual(stat.S_IMODE(state.stat().st_mode), 0o600)
        self.assertEqual(state.read_text(encoding="utf-8"), "test-touchpad\n")

    def test_touchpad_off_on_and_restore_round_trip(self):
        self.write_fake_command("omarchy-hw-touchpad", "#!/bin/sh\nprintf 'Test Touchpad\\n'\n")
        log = self.home / "hyprctl.log"
        self.write_fake_command(
            "hyprctl",
            f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{log}'\n",
        )

        self.run_helper("touchpad", "off")
        state = json.loads(self.run_helper("state").stdout)
        self.assertTrue(state["managed"])
        self.assertTrue(state["disabled"])
        self.assertIn("enabled = false", log.read_text(encoding="utf-8"))

        self.run_helper("touchpad", "on")
        state = json.loads(self.run_helper("state").stdout)
        self.assertFalse(state["managed"])
        self.assertFalse(state["disabled"])
        self.assertIn("enabled = true", log.read_text(encoding="utf-8"))

        self.run_helper("touchpad", "off")
        self.run_helper("restore")
        state = json.loads(self.run_helper("state").stdout)
        self.assertFalse(state["managed"])
        self.assertFalse(state["disabled"])
        self.assertGreaterEqual(log.read_text(encoding="utf-8").count("enabled = true"), 2)

    def test_failed_live_disable_does_not_leave_owned_state(self):
        self.write_fake_command("omarchy-hw-touchpad", "#!/bin/sh\nprintf 'Test Touchpad\\n'\n")
        self.write_fake_command("hyprctl", "#!/bin/sh\nexit 1\n")
        result = self.run_helper("touchpad", "off", check=False)
        self.assertNotEqual(result.returncode, 0)
        state = json.loads(self.run_helper("state").stdout)
        self.assertFalse(state["managed"])
        self.assertFalse(state["disabled"])

    def test_json_encoding_and_process_deadline_are_enforced(self):
        helper = load_helper_module()
        payload = helper.bounded_json({"name": 'mouse\u0001"\\'})
        self.assertEqual(json.loads(payload), {"name": 'mouse\u0001"\\'})
        self.assertIn(b"\\u0001", payload)
        with self.assertRaises(helper.HelperError):
            helper.bounded_json({"value": "x" * helper.MAX_JSON_BYTES})

        started = time.monotonic()
        with self.assertRaises(TimeoutError):
            helper.read_process_output(
                ["bash", "-c", "sleep 10"],
                time.monotonic() + 0.2,
                call_seconds=0.1,
                max_output_bytes=1024,
            )
        self.assertLess(time.monotonic() - started, 1.0)

    def test_udev_export_parser_keeps_only_event_nodes(self):
        helper = load_helper_module()
        raw = (
            b"P: /devices/mouse\n"
            b"N: input/event7\n"
            b"E: DEVNAME=/dev/input/event7\n"
            b"E: ID_INPUT_MOUSE=1\n"
            b"E: ID_BUS=usb\n"
            b"E: NAME=\"Mouse\\n\"\n\n"
            b"P: /devices/not-an-event\n"
            b"N: input/mouse0\n"
            b"E: DEVNAME=/dev/input/mouse0\n\n"
        )
        records = helper.parse_udev_export(raw)
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0][0], "/dev/input/event7")
        self.assertEqual(records[0][1]["ID_INPUT_MOUSE"], "1")

    def test_detector_uses_one_bounded_udev_export_process(self):
        exported_devices = (
            "P: /devices/usb-mouse\nN: input/event3\nE: DEVNAME=/dev/input/event3\n"
            "E: ID_INPUT_MOUSE=1\nE: ID_BUS=usb\nE: NAME=\"USB Mouse\"\n\n"
            "P: /devices/bluetooth-mouse\nN: input/event4\nE: DEVNAME=/dev/input/event4\n"
            "E: ID_INPUT_MOUSE=1\nE: ID_BUS=bluetooth\nE: NAME=\"Bluetooth Mouse\"\n\n"
            "P: /devices/touchpad\nN: input/event5\nE: DEVNAME=/dev/input/event5\n"
            "E: ID_INPUT_MOUSE=1\nE: ID_INPUT_TOUCHPAD=1\nE: ID_BUS=i2c\nE: NAME=\"Touchpad\"\n\n"
            "P: /devices/trackpoint\nN: input/event6\nE: DEVNAME=/dev/input/event6\n"
            "E: ID_INPUT_MOUSE=1\nE: ID_INPUT_POINTINGSTICK=1\nE: ID_BUS=i2c\nE: NAME=\"TrackPoint\"\n\n"
        )
        self.write_fake_command(
            "udevadm",
            "#!/usr/bin/python3\n"
            "import sys\n"
            "assert sys.argv[1:] == ['info', '--export-db', '--subsystem-match=input']\n"
            f"sys.stdout.write({exported_devices!r})\n",
        )
        result = json.loads(self.run_helper("detect").stdout)
        self.assertEqual(result["schemaVersion"], 1)
        self.assertEqual(result["type"], "detection")
        self.assertTrue(result["ok"])
        self.assertEqual(result["usb"], 1)
        self.assertEqual(result["bluetooth"], 1)
        self.assertEqual(result["total"], 2)
        self.assertEqual(result["devices"], [
            {"name": "USB Mouse", "bus": "usb"},
            {"name": "Bluetooth Mouse", "bus": "bluetooth"},
        ])

        self.write_fake_command("udevadm", "#!/bin/sh\nexit 0\n")
        unplugged = json.loads(self.run_helper("detect").stdout)
        self.assertTrue(unplugged["ok"])
        self.assertEqual(unplugged["total"], 0)
        self.assertEqual(unplugged["devices"], [])

        self.write_fake_command("udevadm", "#!/bin/sh\nsleep 10\n")
        started = time.monotonic()
        timed_out = json.loads(self.run_helper("detect", timeout=4).stdout)
        self.assertFalse(timed_out["ok"])
        self.assertEqual(timed_out["error"], "timeout")
        self.assertLess(time.monotonic() - started, 3.0)


if __name__ == "__main__":
    unittest.main()
