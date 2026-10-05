"""Isolated contract tests for the parallel noctalia-mod first stage."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
import unittest

from tests.utils import TempEnv


ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "noctalia-mod" / "bin" / "noctalia-mod"


class NoctaliaModTest(unittest.TestCase):
    def _fake_commands(self, env: TempEnv) -> tuple[Path, Path]:
        fake_bin = env.home / "fake-bin"
        fake_bin.mkdir()
        log = env.home / "commands.log"
        common = """#!/usr/bin/env bash
printf '%s' "$(basename \"$0\")" >> \"$FAKE_LOG\"
printf ' <%s>' \"$@\" >> \"$FAKE_LOG\"
printf '\\n' >> \"$FAKE_LOG\"
"""
        for name in ("niri", "noctalia", "pkill"):
            (fake_bin / name).write_text(common + "exit 0\n")
        (fake_bin / "pacman").write_text(
            common
            + "[[ ${1-} == -Q ]] && exit 1\n"
            + "exit 0\n"
        )
        (fake_bin / "sudo").write_text(common + 'exec "$@"\n')
        for path in fake_bin.iterdir():
            path.chmod(0o755)
        return fake_bin, log

    def _run(self, env: TempEnv, fake_bin: Path, *args: str) -> subprocess.CompletedProcess[str]:
        child_env = os.environ.copy()
        child_env.update(
            {
                "HOME": str(env.home),
                "XDG_CONFIG_HOME": str(env.home / ".config"),
                "XDG_STATE_HOME": str(env.home / ".local" / "state"),
                "XDG_CACHE_HOME": str(env.home / ".cache"),
                "XDG_RUNTIME_DIR": str(env.home / "runtime"),
                "FAKE_LOG": str(env.home / "commands.log"),
                "PATH": f"{fake_bin}:{child_env['PATH']}",
            }
        )
        return subprocess.run(
            [str(CLI), *args],
            cwd=ROOT,
            env=child_env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_list_plan_and_noninteractive_guard(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            listed = self._run(env, fake_bin, "list")
            self.assertEqual(listed.returncode, 0, listed.stderr)
            self.assertIn("niri\tniri", listed.stdout)
            self.assertIn("starship\tstarship.toml", listed.stdout)

            planned = self._run(env, fake_bin, "plan", "niri", "noctalia")
            self.assertEqual(planned.returncode, 0, planned.stderr)
            self.assertIn("module\tniri", planned.stdout)
            self.assertIn("module\tnoctalia", planned.stdout)

            refused = self._run(env, fake_bin, "install", "niri")
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn("without --yes", refused.stderr)
            self.assertFalse((env.home / ".config" / "niri").exists())

    def test_all_first_stage_modules_install_in_one_transaction(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            installed = self._run(env, fake_bin, "install", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            config = env.home / ".config"
            self.assertTrue((config / "niri" / "config.kdl").is_file())
            self.assertTrue((config / "noctalia" / "noctalia-config.toml").is_file())
            self.assertTrue((config / "kitty" / "kitty.conf").is_file())
            self.assertTrue((config / "fish" / "config.fish").is_file())
            self.assertTrue((config / "starship.toml").is_file())

    def test_install_parts_snapshot_rollback_and_uninstall(self) -> None:
        with TempEnv() as env:
            fake_bin, log = self._fake_commands(env)
            config = env.home / ".config"
            (config / "niri").mkdir(parents=True)
            (config / "kitty").mkdir(parents=True)
            (config / "niri" / "monitor.kdl").write_text("user monitor\n")
            (config / "kitty" / "__custom__.conf").write_text("user custom\n")

            installed = self._run(env, fake_bin, "install", "niri", "kitty", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            self.assertEqual((config / "niri" / "monitor.kdl").read_text(), "user monitor\n")
            self.assertEqual((config / "kitty" / "__custom__.conf").read_text(), "user custom\n")

            default_glow = (config / "niri" / "glow.kdl").read_text()
            part = self._run(env, fake_bin, "part", "niri", "glow", "apply", "glow", "--yes")
            self.assertEqual(part.returncode, 0, part.stderr)
            self.assertNotEqual((config / "niri" / "glow.kdl").read_text(), default_glow)
            self.assertIn('width 2', (config / "niri" / "glow.kdl").read_text())

            snapshot = self._run(env, fake_bin, "snapshot", "before edit")
            self.assertEqual(snapshot.returncode, 0, snapshot.stderr)
            snapshot_id = snapshot.stdout.strip().split(": ", 1)[1]
            self.assertTrue(
                (env.home / ".local" / "state" / "noctalia-mod" / "snapshots" / snapshot_id).is_dir()
            )
            original_kitty = (config / "kitty" / "kitty.conf").read_text()
            (config / "kitty" / "kitty.conf").write_text("changed\n")

            rollback = self._run(env, fake_bin, "rollback", snapshot_id)
            self.assertEqual(rollback.returncode, 0, rollback.stderr)
            self.assertEqual((config / "kitty" / "kitty.conf").read_text(), original_kitty)

            uninstall = self._run(env, fake_bin, "uninstall", "kitty", "--yes")
            self.assertEqual(uninstall.returncode, 0, uninstall.stderr)
            self.assertTrue((config / "kitty" / "__custom__.conf").is_file())
            self.assertFalse((config / "kitty" / "kitty.conf").exists())

            commands = log.read_text()
            self.assertIn("sudo <pacman> <-S> <--needed> <--noconfirm> <--> <niri> <kitty>", commands)
            self.assertIn("niri <msg> <action> <reload-config>", commands)
            self.assertIn("pkill <-SIGUSR1> <-x> <kitty>", commands)


    def test_snapshot_and_argument_boundaries(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            installed = self._run(env, fake_bin, "install", "kitty", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            snapshot = self._run(env, fake_bin, "snapshot", "safe note")
            self.assertEqual(snapshot.returncode, 0, snapshot.stderr)
            snapshot_id = snapshot.stdout.strip().split(": ", 1)[1]

            for args in (
                ("rollback", "../outside"),
                ("snapshot", "delete", "../outside"),
                ("snapshot", "list", "unexpected"),
                ("rollback", snapshot_id, "unexpected"),
                ("preset", "kitty", "list", "unexpected"),
            ):
                result = self._run(env, fake_bin, *args)
                self.assertNotEqual(result.returncode, 0, args)

            outside = env.home / ".local" / "state" / "noctalia-mod" / "outside"
            outside.write_text("must survive\n")
            bad_note = self._run(env, fake_bin, "snapshot", "line1\tline2")
            self.assertNotEqual(bad_note.returncode, 0)
            self.assertEqual(outside.read_text(), "must survive\n")

    def test_nested_custom_entries_and_exact_reload_failure_restore(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            config = env.home / ".config"
            kitty = config / "kitty"
            kitty.mkdir(parents=True)
            nested = kitty / "__custom__" / "private.conf"
            nested.parent.mkdir()
            nested.write_text("private\n")

            installed = self._run(env, fake_bin, "install", "kitty", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            self.assertEqual(nested.read_text(), "private\n")

            niri = fake_bin / "niri"
            niri.write_text("#!/usr/bin/env bash\nexit 1\n")
            niri.chmod(0o755)
            config_niri = config / "niri"
            config_niri.mkdir(parents=True)
            (config_niri / "monitor.kdl").write_text("original monitor\n")
            failed = self._run(env, fake_bin, "install", "niri", "--yes")
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual((config_niri / "monitor.kdl").read_text(), "original monitor\n")
            self.assertFalse((config_niri / "config.kdl").exists())

    def test_aur_package_argument_shape(self) -> None:
        with TempEnv() as env:
            fake_bin, log = self._fake_commands(env)
            paru = fake_bin / "paru"
            paru.write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s' \"$(basename \"$0\")\" >> \"$FAKE_LOG\"\n"
                "printf ' <%s>' \"$@\" >> \"$FAKE_LOG\"\n"
                "printf '\\n' >> \"$FAKE_LOG\"\n"
                "exit 0\n"
            )
            paru.chmod(0o755)
            script = (
                f"source {ROOT / 'noctalia-mod/lib/common.sh'}; "
                f"source {ROOT / 'noctalia-mod/lib/package-manager.sh'}; "
                "package_install aur yes demo-package"
            )
            child_env = os.environ.copy()
            child_env.update(
                {
                    "PATH": f"{fake_bin}:{child_env['PATH']}",
                    "FAKE_LOG": str(log),
                }
            )
            result = subprocess.run(
                ["/bin/bash", "-c", script],
                cwd=ROOT,
                env=child_env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("paru <-S> <--needed> <--noconfirm> <--> <demo-package>", log.read_text())

            no_helper_env = child_env.copy()
            no_helper_env["PATH"] = str(fake_bin)
            paru.rename(fake_bin / "paru.disabled")
            missing = subprocess.run(
                ["/bin/bash", "-c", script],
                cwd=ROOT,
                env=no_helper_env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn("neither paru nor yay", missing.stderr)

    def test_preset_and_invalid_module_do_not_escape(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            invalid = self._run(env, fake_bin, "plan", "../niri")
            self.assertNotEqual(invalid.returncode, 0)
            self.assertIn("invalid module id", invalid.stderr)

            installed = self._run(env, fake_bin, "install", "kitty", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            preset = self._run(env, fake_bin, "preset", "kitty", "apply", "transparent", "--yes")
            self.assertEqual(preset.returncode, 0, preset.stderr)
            state = env.home / ".local" / "state" / "noctalia-mod" / "modules" / "kitty.state"
            self.assertIn("preset\ttransparent", state.read_text())


if __name__ == "__main__":
    unittest.main()
