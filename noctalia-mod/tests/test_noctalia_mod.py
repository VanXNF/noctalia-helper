"""Isolated contract tests for the parallel noctalia-mod first stage."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path
import tempfile
import unittest

from utils import TempEnv


PROJECT = Path(__file__).resolve().parent.parent
CLI = PROJECT / "bin" / "noctalia-mod"


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
        for name in ("niri", "pkill"):
            (fake_bin / name).write_text(common + "exit 0\n")
        # noctalia 除了回 reload，还要能回答 theme-mode-get（部署收尾会问一次）。
        (fake_bin / "noctalia").write_text(
            common
            + 'if [[ ${1-} == msg && ${2-} == theme-mode-get ]]; then\n'
            + '    printf \'%s\\n\' "${FAKE_THEME_MODE:-dark}"\n'
            + "fi\n"
            + "exit 0\n"
        )
        # XDG 图片目录：测试通过 FAKE_PICTURES 指定，默认落在 $HOME/Pictures。
        (fake_bin / "xdg-user-dir").write_text(
            common + 'echo "${FAKE_PICTURES:-$HOME/Pictures}"\n'
        )
        (fake_bin / "gsettings").write_text(
            common
            + 'if [[ ${1-} == get ]]; then printf "\'%s\'\\n" "${FAKE_COLOR_SCHEME:-prefer-dark}"; fi\n'
            + "exit 0\n"
        )
        (fake_bin / "pacman").write_text(
            common
            + "[[ ${1-} == -Q ]] && exit 1\n"
            + "exit 0\n"
        )
        (fake_bin / "sudo").write_text(
            common
            + 'if [[ ${1-} == -v ]]; then exit 0; fi\n'
            + 'exec "$@"\n'
        )
        for path in fake_bin.iterdir():
            path.chmod(0o755)
        return fake_bin, log

    def _run(
        self,
        env: TempEnv,
        fake_bin: Path,
        *args: str,
        cli: Path = CLI,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
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
        if extra_env:
            child_env.update(extra_env)
        return subprocess.run(
            [str(cli), *args],
            cwd=PROJECT,
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

    def test_all_modules_install_in_one_transaction(self) -> None:
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
            self.assertTrue((config / "fastfetch" / "config.jsonc").is_file())
            self.assertTrue((config / "xdg-desktop-portal" / "portals.conf").is_file())
            self.assertTrue((config / "zed" / "settings.json").is_file())

    def test_migrated_content_modules_carry_no_old_engine_leftovers(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            installed = self._run(
                env, fake_bin, "install", "fastfetch", "xdg-desktop-portal", "zed", "--yes"
            )
            self.assertEqual(installed.returncode, 0, installed.stderr)
            config = env.home / ".config"
            # 旧引擎的 manifest 是给旧引擎读的，不是配置，不该进 ~/.config。
            self.assertFalse((config / "xdg-desktop-portal" / ".module.toml").exists())
            # 项目名残留会顺着随包内容一路部署下去，所以正面盯一下。
            fastfetch = (config / "fastfetch" / "config.jsonc").read_text()
            self.assertIn("Noctalia Mod", fastfetch)
            self.assertNotIn("Nyxuri", fastfetch)

    def test_portal_module_installs_the_backends_its_config_names(self) -> None:
        """Routing that points at gnome/gtk is a lie unless those backends get installed."""
        with TempEnv() as env:
            fake_bin, log = self._fake_commands(env)
            result = self._run(env, fake_bin, "deps", "xdg-desktop-portal", "--yes")
            self.assertEqual(result.returncode, 0, result.stderr)
            install_line = next(
                line for line in log.read_text().splitlines() if line.startswith("sudo <pacman> <-S>")
            )
            installed = set(re.findall(r"<([^>]*)>", install_line))
            for package in (
                "xdg-desktop-portal",
                "xdg-desktop-portal-gtk",
                "xdg-desktop-portal-gnome",
                "gnome-keyring",
            ):
                self.assertIn(package, installed)

    def _kitty_preset_dir(self, env: TempEnv, name: str) -> Path:
        return env.home / ".config" / "noctalia-mod" / "presets" / "kitty" / name

    def test_preset_save_writes_a_user_preset_without_custom_files(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            installed = self._run(env, fake_bin, "install", "kitty", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            kitty = env.home / ".config" / "kitty"
            with (kitty / "kitty.conf").open("a", encoding="utf-8") as handle:
                handle.write("\n# my own edit\n")
            (kitty / "__custom__.conf").write_text("private\n", encoding="utf-8")

            saved = self._run(env, fake_bin, "preset", "kitty", "save", "mine", "--yes")
            self.assertEqual(saved.returncode, 0, saved.stderr)
            preset = self._kitty_preset_dir(env, "mine")
            self.assertIn("# my own edit", (preset / "kitty.conf").read_text())
            self.assertTrue(
                (preset / "current-theme.conf").is_symlink(),
                "runtime symlinks travel with the preset as links",
            )
            self.assertFalse(
                (preset / "__custom__.conf").exists(),
                "__custom__ is the user's live override and does not belong in a preset",
            )

    def test_preset_save_refuses_reserved_and_official_names(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            self._run(env, fake_bin, "install", "kitty", "--yes")

            reserved = self._run(env, fake_bin, "preset", "kitty", "save", "default", "--yes")
            self.assertNotEqual(reserved.returncode, 0)
            self.assertIn("reserved", reserved.stderr)

            official = self._run(env, fake_bin, "preset", "kitty", "save", "transparent", "--yes")
            self.assertNotEqual(official.returncode, 0)
            self.assertIn("shipped by the repository", official.stderr)
            self.assertFalse(self._kitty_preset_dir(env, "transparent").exists())

            bad_name = self._run(
                env, fake_bin, "preset", "kitty", "save", "Not-An-Identifier", "--yes"
            )
            self.assertNotEqual(bad_name.returncode, 0)

    def test_preset_list_reports_source_and_active(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            self._run(env, fake_bin, "install", "kitty", "--yes")
            self._run(env, fake_bin, "preset", "kitty", "save", "mine", "--yes")

            listed = self._run(env, fake_bin, "preset", "kitty", "list")
            self.assertEqual(listed.returncode, 0, listed.stderr)
            self.assertIn("preset\tsource\tactive", listed.stdout)
            self.assertIn("default\tofficial\tyes", listed.stdout)
            self.assertIn("transparent\tofficial\tno", listed.stdout)
            self.assertIn("mine\tuser\tno", listed.stdout)

            applied = self._run(env, fake_bin, "preset", "kitty", "apply", "mine", "--yes")
            self.assertEqual(applied.returncode, 0, applied.stderr)
            after = self._run(env, fake_bin, "preset", "kitty", "list")
            self.assertIn("mine\tuser\tyes", after.stdout)
            self.assertIn("default\tofficial\tno", after.stdout)

    def test_preset_apply_deploys_the_saved_content(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            config = env.home / ".config"
            self._run(env, fake_bin, "install", "kitty", "--yes")
            with (config / "kitty" / "kitty.conf").open("a", encoding="utf-8") as handle:
                handle.write("\n# saved variant\n")
            self._run(env, fake_bin, "preset", "kitty", "save", "mine", "--yes")

            reset = self._run(env, fake_bin, "preset", "kitty", "apply", "default", "--yes")
            self.assertEqual(reset.returncode, 0, reset.stderr)
            self.assertNotIn("# saved variant", (config / "kitty" / "kitty.conf").read_text())

            applied = self._run(env, fake_bin, "preset", "kitty", "apply", "mine", "--yes")
            self.assertEqual(applied.returncode, 0, applied.stderr)
            self.assertIn("# saved variant", (config / "kitty" / "kitty.conf").read_text())

    def test_preset_save_overwrite_asks_first(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            config = env.home / ".config"
            self._run(env, fake_bin, "install", "kitty", "--yes")
            self._run(env, fake_bin, "preset", "kitty", "save", "mine", "--yes")
            preset = self._kitty_preset_dir(env, "mine")
            original = (preset / "kitty.conf").read_text()

            with (config / "kitty" / "kitty.conf").open("a", encoding="utf-8") as handle:
                handle.write("\n# second version\n")
            refused = self._run(env, fake_bin, "preset", "kitty", "save", "mine")
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn("without --yes", refused.stderr)
            self.assertEqual(
                (preset / "kitty.conf").read_text(),
                original,
                "a refused overwrite must not touch the preset",
            )

            overwritten = self._run(env, fake_bin, "preset", "kitty", "save", "mine", "--yes")
            self.assertEqual(overwritten.returncode, 0, overwritten.stderr)
            self.assertIn("# second version", (preset / "kitty.conf").read_text())

    def test_preset_delete_refuses_official_and_warns_when_active(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            self._run(env, fake_bin, "install", "kitty", "--yes")
            self._run(env, fake_bin, "preset", "kitty", "save", "mine", "--yes")
            self._run(env, fake_bin, "preset", "kitty", "apply", "mine", "--yes")

            official = self._run(env, fake_bin, "preset", "kitty", "delete", "transparent")
            self.assertNotEqual(official.returncode, 0)
            self.assertIn("shipped by the repository", official.stderr)

            deleted = self._run(env, fake_bin, "preset", "kitty", "delete", "mine")
            self.assertEqual(deleted.returncode, 0, deleted.stderr)
            self.assertIn("active", deleted.stderr)
            self.assertFalse(self._kitty_preset_dir(env, "mine").exists())
            self.assertFalse(
                (env.home / ".config" / "noctalia-mod" / "presets" / "kitty").exists(),
                "an emptied module directory should not be left behind",
            )

    def test_preset_edit_needs_a_terminal_and_refuses_official(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            self._run(env, fake_bin, "install", "kitty", "--yes")
            self._run(env, fake_bin, "preset", "kitty", "save", "mine", "--yes")

            official = self._run(env, fake_bin, "preset", "kitty", "edit", "transparent")
            self.assertNotEqual(official.returncode, 0)
            self.assertIn("shipped by the repository", official.stderr)

            headless = self._run(env, fake_bin, "preset", "kitty", "edit", "mine")
            self.assertNotEqual(headless.returncode, 0)
            self.assertIn(str(self._kitty_preset_dir(env, "mine")), headless.stderr)

    def test_preset_save_and_apply_for_a_single_file_target(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            target = env.home / ".config" / "starship.toml"
            self._run(env, fake_bin, "install", "starship", "--yes")
            shipped = target.read_text()
            with target.open("a", encoding="utf-8") as handle:
                handle.write("\n# saved variant\n")

            saved = self._run(env, fake_bin, "preset", "starship", "save", "mine", "--yes")
            self.assertEqual(saved.returncode, 0, saved.stderr)
            preset_file = (
                env.home / ".config" / "noctalia-mod" / "presets" / "starship" / "mine"
                / "starship.toml"
            )
            self.assertTrue(preset_file.is_file())

            self._run(env, fake_bin, "preset", "starship", "apply", "default", "--yes")
            self.assertEqual(target.read_text(), shipped)
            applied = self._run(env, fake_bin, "preset", "starship", "apply", "mine", "--yes")
            self.assertEqual(applied.returncode, 0, applied.stderr)
            self.assertIn("# saved variant", target.read_text())

    def test_install_freezes_a_module_whose_preset_disappeared(self) -> None:
        """PLAN §4: never silently fall back to default over the user's own config."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            config = env.home / ".config"
            state = env.home / ".local" / "state" / "noctalia-mod" / "modules" / "kitty.state"
            self._run(env, fake_bin, "install", "kitty", "--yes")
            with (config / "kitty" / "kitty.conf").open("a", encoding="utf-8") as handle:
                handle.write("\n# mine\n")
            self._run(env, fake_bin, "preset", "kitty", "save", "mine", "--yes")
            self._run(env, fake_bin, "preset", "kitty", "apply", "mine", "--yes")
            self._run(env, fake_bin, "preset", "kitty", "delete", "mine")
            before_state = state.read_text()
            before_config = (config / "kitty" / "kitty.conf").read_text()

            planned = self._run(env, fake_bin, "plan", "kitty")
            self.assertEqual(planned.returncode, 0, planned.stderr)
            self.assertIn("preset-missing\tkitty\tmine\tfrozen", planned.stdout)

            installed = self._run(env, fake_bin, "install", "kitty", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            self.assertIn("no longer exists", installed.stderr)
            self.assertEqual((config / "kitty" / "kitty.conf").read_text(), before_config)
            self.assertEqual(
                state.read_text(),
                before_state,
                "a frozen module must not have its ledger rewritten — that would erase drift",
            )

    def test_install_restores_defaults_when_the_preset_and_target_are_both_gone(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            config = env.home / ".config"
            state = env.home / ".local" / "state" / "noctalia-mod" / "modules" / "kitty.state"
            self._run(env, fake_bin, "install", "kitty", "--yes")
            with (config / "kitty" / "kitty.conf").open("a", encoding="utf-8") as handle:
                handle.write("\n# mine\n")
            self._run(env, fake_bin, "preset", "kitty", "save", "mine", "--yes")
            self._run(env, fake_bin, "preset", "kitty", "apply", "mine", "--yes")
            self._run(env, fake_bin, "preset", "kitty", "delete", "mine")
            shutil.rmtree(config / "kitty")

            installed = self._run(env, fake_bin, "install", "kitty", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            self.assertNotIn("# mine", (config / "kitty" / "kitty.conf").read_text())
            recorded = dict(line.split("\t", 1) for line in state.read_text().splitlines())
            self.assertEqual(recorded["preset"], "default")

    def test_setup_defaults_to_the_core_set_and_summarises(self) -> None:
        """PLAN §11 B: setup is the guided path from zero to a desktop, core set only."""
        with TempEnv() as env:
            fake_bin, log = self._fake_commands(env)
            result = self._run(env, fake_bin, "setup", "--yes")
            self.assertEqual(result.returncode, 0, result.stderr)

            config = env.home / ".config"
            self.assertTrue((config / "niri" / "config.kdl").is_file())
            self.assertTrue((config / "noctalia" / "noctalia-config.toml").is_file())
            for extra in ("kitty", "fish", "starship.toml"):
                self.assertFalse(
                    (config / extra).exists(),
                    f"{extra} must not be in the default setup set",
                )

            # One checklist, one authorisation, packages before configuration.
            self.assertEqual(result.stdout.count("Noctalia Mod setup"), 1)
            self.assertIn("missing-repo", result.stdout)
            self.assertIn("module\tniri", result.stdout)
            commands = log.read_text()
            self.assertEqual(commands.count("sudo <-v>"), 1, "sudo must be primed exactly once")
            install_line = next(
                line for line in commands.splitlines() if line.startswith("sudo <pacman> <-S>")
            )
            self.assertIn(" <niri>", install_line)
            self.assertIn(" <noctalia>", install_line)
            self.assertLess(
                commands.index("sudo <pacman> <-S>"),
                commands.index("niri <msg> <action> <reload-config>"),
                "packages are installed before the configuration is deployed",
            )
            self.assertIn("setup complete", result.stdout)
            self.assertIn(f"deployed\tniri\t{config / 'niri'}", result.stdout)
            self.assertIn(f"deployed\tnoctalia\t{config / 'noctalia'}", result.stdout)
            self.assertIn("installed\tniri", result.stdout)
            self.assertIn("undo\tnoctalia-mod rollback", result.stdout)

    def test_setup_refuses_without_yes_and_writes_nothing(self) -> None:
        with TempEnv() as env:
            fake_bin, log = self._fake_commands(env)
            refused = self._run(env, fake_bin, "setup")
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn("without --yes", refused.stderr)
            self.assertFalse((env.home / ".config" / "niri").exists())
            self.assertFalse((env.home / ".config" / "noctalia").exists())
            if log.exists():
                self.assertNotIn(
                    "<-S>",
                    log.read_text(),
                    "nothing may be installed before the single confirmation",
                )

    def test_setup_reruns_converge(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            config = env.home / ".config"
            first = self._run(env, fake_bin, "setup", "--yes")
            self.assertEqual(first.returncode, 0, first.stderr)
            before = sorted(path.relative_to(config).as_posix() for path in config.rglob("*"))

            again = self._run(env, fake_bin, "setup", "--yes")
            self.assertEqual(again.returncode, 0, again.stderr)
            after = sorted(path.relative_to(config).as_posix() for path in config.rglob("*"))
            self.assertEqual(before, after, "a re-run must not add or drop configuration")
            self.assertEqual(
                [name for name in after if "noctalia-mod." in name],
                [],
                "staging directories must not survive a run",
            )

            ledger = env.home / ".local" / "state" / "noctalia-mod" / "packages.tsv"
            lines = ledger.read_text().splitlines()
            self.assertEqual(len(lines), len(set(lines)), "the package ledger must not duplicate")

    def test_setup_with_installs_a_declared_optional_program(self) -> None:
        """Optional programs are opt-in; --with is the only way to ask for one."""
        with TempEnv() as env:
            fake_bin, log = self._fake_commands(env)
            with tempfile.TemporaryDirectory() as tmp:
                tree = self._probe_tree(
                    tmp,
                    "MODULE_ID='probe'\nMODULE_TARGET='probe'\n"
                    "MODULE_REPO_PACKAGES=(probe-package)\n"
                    "MODULE_OPTIONAL_COMMANDS=('noctalia-mod-absent-extra:probe-extra-package')\n",
                    {"probe.conf": "x\n"},
                )
                cli = tree / "bin" / "noctalia-mod"
                default = self._run(env, fake_bin, "setup", "probe", "--yes", cli=cli)
                self.assertEqual(default.returncode, 0, default.stderr)
                self.assertNotIn(
                    "probe-extra-package",
                    next(
                        line
                        for line in log.read_text().splitlines()
                        if line.startswith("sudo <pacman> <-S>")
                    ),
                    "an optional program must stay out of the default install",
                )
                self.assertIn(
                    "optional\tprobe\tnoctalia-mod-absent-extra\tprobe-extra-package",
                    default.stdout,
                )

                asked = self._run(
                    env, fake_bin, "setup", "probe", "--with", "noctalia-mod-absent-extra",
                    "--yes", cli=cli,
                )
                self.assertEqual(asked.returncode, 0, asked.stderr)
                install_line = next(
                    line
                    for line in log.read_text().splitlines()
                    if line.startswith("sudo <pacman> <-S>")
                    and "probe-extra-package" in line
                )
                self.assertTrue(
                    install_line.startswith(
                        "sudo <pacman> <-S> <--needed> <--noconfirm> <--> "
                    ),
                    install_line,
                )
                self.assertIn("installed\t", asked.stdout)
                self.assertIn("probe-extra-package", asked.stdout)

    def test_setup_rejects_an_unknown_with_program(self) -> None:
        """--with cannot conjure packages: only declared optional programs resolve."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            with tempfile.TemporaryDirectory() as tmp:
                tree = self._probe_tree(
                    tmp,
                    "MODULE_ID='probe'\nMODULE_TARGET='probe'\n"
                    "MODULE_REPO_PACKAGES=(probe-package)\n"
                    "MODULE_OPTIONAL_COMMANDS=('noctalia-mod-absent-extra:probe-extra-package')\n",
                    {"probe.conf": "x\n"},
                )
                result = self._run(
                    env, fake_bin, "setup", "probe", "--with", "definitely-not-declared",
                    "--yes", cli=tree / "bin" / "noctalia-mod",
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("not a declared optional program", result.stderr)
                self.assertIn("noctalia-mod-absent-extra", result.stderr)
                self.assertFalse((env.home / ".config" / "probe").exists())

    def test_setup_with_requires_a_program_name(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            result = self._run(env, fake_bin, "setup", "--with")
            self.assertEqual(result.returncode, 2)
            self.assertIn("--with requires a program name", result.stderr)

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
                f"source {PROJECT / 'lib/common.sh'}; "
                f"source {PROJECT / 'lib/package-manager.sh'}; "
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
                cwd=PROJECT,
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
                cwd=PROJECT,
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


    def test_deps_installs_packages_without_touching_config(self) -> None:
        with TempEnv() as env:
            fake_bin, log = self._fake_commands(env)

            refused = self._run(env, fake_bin, "deps", "niri", "noctalia")
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn("without --yes", refused.stderr)

            installed = self._run(env, fake_bin, "deps", "niri", "noctalia", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            self.assertFalse(
                (env.home / ".config" / "niri").exists(),
                "the dependency stage must not deploy configuration",
            )

            commands = log.read_text()
            self.assertIn("sudo <-v>", commands, "sudo must be primed once up front")
            # 断言 argv 形状，不锁死包清单——清单会随模块声明变化，形状不会。
            install_line = next(
                line
                for line in commands.splitlines()
                if line.startswith("sudo <pacman> <-S>")
            )
            self.assertTrue(
                install_line.startswith(
                    "sudo <pacman> <-S> <--needed> <--noconfirm> <--> "
                ),
                install_line,
            )
            self.assertIn(" <niri>", install_line)
            self.assertIn(" <noctalia>", install_line)
            self.assertIn(" <kitty>", install_line, "config-spawned programs must be installed")

    def test_deps_is_a_noop_when_every_package_is_present(self) -> None:
        with TempEnv() as env:
            fake_bin, log = self._fake_commands(env)
            # Everything installed: pacman -Q succeeds.
            (fake_bin / "pacman").write_text("#!/usr/bin/env bash\nexit 0\n")
            (fake_bin / "pacman").chmod(0o755)

            result = self._run(env, fake_bin, "deps", "niri", "noctalia", "--yes")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("nothing to install", result.stdout)
            self.assertFalse(log.exists(), "no package manager or sudo call was needed")

    def test_deps_checks_the_aur_helper_before_installing_anything(self) -> None:
        """Ordering contract: no repo package gets installed before the AUR helper is verified.

        Runs against the library with a PATH that holds only the fake commands, so the
        result does not depend on whether the host happens to have paru or yay.
        """
        with TempEnv() as env:
            fake_bin, log = self._fake_commands(env)
            script = (
                f"source {PROJECT / 'lib/common.sh'}; "
                f"source {PROJECT / 'lib/package-manager.sh'}; "
                "PLAN_REPO_PACKAGES=(probe-repo); PLAN_AUR_PACKAGES=(probe-aur); "
                "install_dependencies"
            )
            child_env = os.environ.copy()
            child_env.update({"PATH": str(fake_bin), "FAKE_LOG": str(log)})
            result = subprocess.run(
                ["/bin/bash", "-c", script],
                cwd=PROJECT,
                env=child_env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("neither paru nor yay", result.stderr)
            if log.exists():
                self.assertNotIn(
                    "pacman <-S>",
                    log.read_text(),
                    "repo packages must not be installed before the AUR helper is verified",
                )

    def _probe_tree(self, tmp: str, module_conf: str, files: dict[str, str]) -> Path:
        tree = Path(tmp) / "noctalia-mod"
        shutil.copytree(PROJECT, tree)
        module = tree / "modules" / "probe"
        (module / "files").mkdir(parents=True)
        (module / "module.conf").write_text(module_conf, encoding="utf-8")
        for name, body in files.items():
            (module / "files" / name).write_text(body, encoding="utf-8")
        return tree

    def test_check_rejects_a_spawned_program_that_is_never_declared(self) -> None:
        """P1-6: a config that spawns a program must say so, or nobody installs it."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            with tempfile.TemporaryDirectory() as tmp:
                tree = self._probe_tree(
                    tmp,
                    "MODULE_ID='probe'\nMODULE_TARGET='probe'\n",
                    {"probe.kdl": 'Mod+X { spawn "never-declared-tool"; }\n'},
                )
                result = self._run(
                    env, fake_bin, "check", cli=tree / "bin" / "noctalia-mod"
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("undeclared-command", result.stdout)
                self.assertIn("never-declared-tool", result.stdout)

    def test_check_rejects_a_required_command_without_its_package(self) -> None:
        """A required program whose package nobody declares can never be installed."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            with tempfile.TemporaryDirectory() as tmp:
                tree = self._probe_tree(
                    tmp,
                    "MODULE_ID='probe'\nMODULE_TARGET='probe'\n"
                    "MODULE_REQUIRED_COMMANDS=('probe-tool:probe-package')\n",
                    {"probe.conf": "x\n"},
                )
                result = self._run(
                    env, fake_bin, "check", cli=tree / "bin" / "noctalia-mod"
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unbound-command", result.stdout)
                self.assertIn("probe-tool:probe-package", result.stdout)

    def test_declaring_program_and_package_satisfies_both_checks(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            with tempfile.TemporaryDirectory() as tmp:
                tree = self._probe_tree(
                    tmp,
                    "MODULE_ID='probe'\nMODULE_TARGET='probe'\n"
                    "MODULE_REPO_PACKAGES=(probe-package)\n"
                    "MODULE_REQUIRED_COMMANDS=('probe-tool:probe-package')\n",
                    {"probe.kdl": 'Mod+X { spawn "probe-tool"; }\n'},
                )
                result = self._run(
                    env, fake_bin, "check", cli=tree / "bin" / "noctalia-mod"
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_plan_reports_a_required_program_that_is_not_installed(self) -> None:
        """The package loop can report success while the command is still absent."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            with tempfile.TemporaryDirectory() as tmp:
                tree = self._probe_tree(
                    tmp,
                    "MODULE_ID='probe'\nMODULE_TARGET='probe'\n"
                    "MODULE_REPO_PACKAGES=(probe-package)\n"
                    "MODULE_REQUIRED_COMMANDS=('noctalia-mod-absent-tool:probe-package')\n"
                    "MODULE_OPTIONAL_COMMANDS=('noctalia-mod-absent-extra:probe-package')\n",
                    {"probe.conf": "x\n"},
                )
                result = self._run(
                    env, fake_bin, "plan", "probe", cli=tree / "bin" / "noctalia-mod"
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("missing-required", result.stdout)
                self.assertIn("noctalia-mod-absent-tool", result.stdout)
                self.assertIn("missing-optional", result.stdout)
                self.assertIn("noctalia-mod-absent-extra", result.stdout)

    def test_runtime_report_is_scoped_to_the_selected_modules(self) -> None:
        """A scoped run must not audit modules the user did not ask for (PLAN §3)."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            with tempfile.TemporaryDirectory() as tmp:
                tree = self._probe_tree(
                    tmp,
                    "MODULE_ID='probe'\nMODULE_TARGET='probe'\n"
                    "MODULE_REPO_PACKAGES=(probe-package)\n"
                    "MODULE_REQUIRED_COMMANDS=('noctalia-mod-absent-tool:probe-package')\n",
                    {"probe.conf": "x\n"},
                )
                cli = tree / "bin" / "noctalia-mod"

                scoped = self._run(env, fake_bin, "plan", "niri", cli=cli)
                self.assertEqual(scoped.returncode, 0, scoped.stderr)
                self.assertNotIn("noctalia-mod-absent-tool", scoped.stdout)

                asked_for = self._run(env, fake_bin, "plan", "probe", cli=cli)
                self.assertEqual(asked_for.returncode, 0, asked_for.stderr)
                self.assertIn("missing-required\tprobe\tnoctalia-mod-absent-tool", asked_for.stdout)

                deps = self._run(env, fake_bin, "deps", "niri", "--yes", cli=cli)
                self.assertEqual(deps.returncode, 0, deps.stderr)
                self.assertNotIn("noctalia-mod-absent-tool", deps.stdout)

    def test_install_refuses_on_undeclared_spawned_program(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            with tempfile.TemporaryDirectory() as tmp:
                tree = self._probe_tree(
                    tmp,
                    "MODULE_ID='probe'\nMODULE_TARGET='probe'\n",
                    {"probe.kdl": 'Mod+X { spawn "never-declared-tool"; }\n'},
                )
                result = self._run(
                    env, fake_bin, "install", "probe", "--yes",
                    cli=tree / "bin" / "noctalia-mod",
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("undeclared-command", result.stdout)
                self.assertFalse((env.home / ".config" / "probe").exists())

    def test_pruning_never_deletes_the_snapshot_uninstall_needs(self) -> None:
        """P0-1: the ledger's recovery point must survive pruning, or uninstall loses data."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            config = env.home / ".config"
            (config / "niri").mkdir(parents=True)
            (config / "niri" / "user-notes.kdl").write_text("USER ORIGINAL\n")

            installed = self._run(env, fake_bin, "install", "niri", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            self.assertFalse((config / "niri" / "user-notes.kdl").exists())

            state_file = (
                env.home / ".local" / "state" / "noctalia-mod" / "modules" / "niri.state"
            )
            recovery = dict(
                line.split("\t", 1) for line in state_file.read_text().splitlines()
            )["last_snapshot"]

            # Push the recovery snapshot well past the retention limit.
            for index in range(34):
                filler = self._run(env, fake_bin, "snapshot", f"filler {index}")
                self.assertEqual(filler.returncode, 0, filler.stderr)

            snapshots = env.home / ".local" / "state" / "noctalia-mod" / "snapshots"
            self.assertTrue(
                (snapshots / recovery).is_dir(),
                "pruning deleted the snapshot the module ledger still points at",
            )

            uninstalled = self._run(env, fake_bin, "uninstall", "niri", "--yes")
            self.assertEqual(uninstalled.returncode, 0, uninstalled.stderr)
            self.assertEqual((config / "niri" / "user-notes.kdl").read_text(), "USER ORIGINAL\n")

    def test_uninstall_says_so_when_the_recovery_point_is_gone(self) -> None:
        """Losing the recovery point may not happen silently (PLAN §6)."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            config = env.home / ".config"
            (config / "niri").mkdir(parents=True)
            (config / "niri" / "user-notes.kdl").write_text("USER ORIGINAL\n")

            installed = self._run(env, fake_bin, "install", "niri", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            state_file = (
                env.home / ".local" / "state" / "noctalia-mod" / "modules" / "niri.state"
            )
            recovery = dict(
                line.split("\t", 1) for line in state_file.read_text().splitlines()
            )["last_snapshot"]

            removed = self._run(env, fake_bin, "snapshot", "delete", recovery)
            self.assertEqual(removed.returncode, 0, removed.stderr)
            self.assertIn("recovery point", removed.stderr)

            uninstalled = self._run(env, fake_bin, "uninstall", "niri", "--yes")
            self.assertEqual(uninstalled.returncode, 0, uninstalled.stderr)
            self.assertIn("cannot be restored", uninstalled.stderr)
            self.assertFalse((config / "niri" / "user-notes.kdl").exists())

    def test_prune_orders_by_creation_time_not_by_snapshot_id(self) -> None:
        """Retention must follow created_at; IDs share a second and end in random digits."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            snapshots = env.home / ".local" / "state" / "noctalia-mod" / "snapshots"
            # ID order deliberately contradicts creation order.
            plan = {
                "snapshot_20260101_000000_000001": "2026-01-01T00:00:00Z",  # oldest
                "snapshot_20260101_000000_000002": "2026-01-04T00:00:00Z",  # newest
                "snapshot_20260101_000000_000003": "2026-01-02T00:00:00Z",
                "snapshot_20260101_000000_000004": "2026-01-03T00:00:00Z",
            }
            for snapshot_id, created in plan.items():
                directory = snapshots / snapshot_id
                directory.mkdir(parents=True)
                (directory / "meta.tsv").write_text(
                    f"created_at\t{created}\nkind\tmanual\nnote\t\n", encoding="utf-8"
                )

            script = (
                f"source {PROJECT / 'lib/common.sh'}; "
                f"source {PROJECT / 'lib/paths.sh'}; "
                f"source {PROJECT / 'lib/state.sh'}; "
                f"source {PROJECT / 'lib/snapshot.sh'}; "
                "NOCTALIA_MOD_SNAPSHOT_LIMIT=2; "
                "snapshot_prune ''"
            )
            child_env = os.environ.copy()
            child_env.update(
                {
                    "HOME": str(env.home),
                    "XDG_STATE_HOME": str(env.home / ".local" / "state"),
                    "XDG_CONFIG_HOME": str(env.home / ".config"),
                    "XDG_CACHE_HOME": str(env.home / ".cache"),
                }
            )
            result = subprocess.run(
                ["/bin/bash", "-c", script],
                cwd=PROJECT,
                env=child_env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            surviving = sorted(path.name for path in snapshots.iterdir())
            self.assertEqual(
                surviving,
                [
                    "snapshot_20260101_000000_000002",  # 2026-01-04
                    "snapshot_20260101_000000_000004",  # 2026-01-03
                ],
            )

    def test_prune_keeps_a_snapshot_referenced_by_module_state(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            state_root = env.home / ".local" / "state" / "noctalia-mod"
            snapshots = state_root / "snapshots"
            protected = "snapshot_20260101_000000_000001"
            plan = {
                protected: "2026-01-01T00:00:00Z",  # oldest, but referenced
                "snapshot_20260101_000000_000002": "2026-01-04T00:00:00Z",
                "snapshot_20260101_000000_000003": "2026-01-03T00:00:00Z",
                "snapshot_20260101_000000_000004": "2026-01-02T00:00:00Z",
            }
            for snapshot_id, created in plan.items():
                directory = snapshots / snapshot_id
                directory.mkdir(parents=True)
                (directory / "meta.tsv").write_text(
                    f"created_at\t{created}\nkind\tmanual\nnote\t\n", encoding="utf-8"
                )
            (state_root / "modules").mkdir(parents=True)
            (state_root / "modules" / "niri.state").write_text(
                f"enabled\t1\nlast_snapshot\t{protected}\n", encoding="utf-8"
            )

            script = (
                f"source {PROJECT / 'lib/common.sh'}; "
                f"source {PROJECT / 'lib/paths.sh'}; "
                f"source {PROJECT / 'lib/state.sh'}; "
                f"source {PROJECT / 'lib/snapshot.sh'}; "
                "NOCTALIA_MOD_SNAPSHOT_LIMIT=1; "
                "snapshot_prune ''"
            )
            child_env = os.environ.copy()
            child_env.update(
                {
                    "HOME": str(env.home),
                    "XDG_STATE_HOME": str(env.home / ".local" / "state"),
                    "XDG_CONFIG_HOME": str(env.home / ".config"),
                    "XDG_CACHE_HOME": str(env.home / ".cache"),
                }
            )
            result = subprocess.run(
                ["/bin/bash", "-c", script],
                cwd=PROJECT,
                env=child_env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            surviving = sorted(path.name for path in snapshots.iterdir())
            self.assertEqual(
                surviving,
                [protected, "snapshot_20260101_000000_000002"],
                "the referenced snapshot and the newest one must both survive",
            )

    def test_state_merge_preserves_keys_the_write_does_not_mention(self) -> None:
        """P1-3: a field the caller does not pass must survive the next install."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            installed = self._run(env, fake_bin, "install", "niri", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)

            state = (
                env.home / ".local" / "state" / "noctalia-mod" / "modules" / "niri.state"
            )
            with state.open("a", encoding="utf-8") as handle:
                handle.write("owner\tnoctalia-mod\npackages\tniri kitty\n")

            again = self._run(env, fake_bin, "install", "niri", "--yes")
            self.assertEqual(again.returncode, 0, again.stderr)

            recorded = dict(
                line.split("\t", 1) for line in state.read_text().splitlines()
            )
            self.assertEqual(
                recorded.get("owner"),
                "noctalia-mod",
                "a field nobody passed was silently dropped by the ledger write",
            )
            self.assertEqual(recorded.get("packages"), "niri kitty")
            self.assertEqual(recorded.get("last_result"), "success")

    def test_reinstall_clears_a_part_key_the_module_no_longer_declares(self) -> None:
        """Merge write keeps unknown keys, so dropped part slots need explicit cleanup."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            with tempfile.TemporaryDirectory() as tmp:
                tree = Path(tmp) / "noctalia-mod"
                shutil.copytree(PROJECT, tree)
                module = tree / "modules" / "probe"
                (module / "files").mkdir(parents=True)
                (module / "parts" / "alpha").mkdir(parents=True)
                (module / "files" / "probe.conf").write_text("base\n", encoding="utf-8")
                (module / "parts" / "alpha" / "default.kdl").write_text(
                    "part\n", encoding="utf-8"
                )
                (module / "module.conf").write_text(
                    "MODULE_ID='probe'\nMODULE_TARGET='probe'\n"
                    "MODULE_PARTS=(alpha)\n"
                    "MODULE_PART_ALPHA_TARGET='alpha.kdl'\n"
                    "MODULE_PART_ALPHA_DEFAULT='default'\n",
                    encoding="utf-8",
                )
                installed = self._run(
                    env, fake_bin, "install", "probe", "--yes",
                    cli=tree / "bin" / "noctalia-mod",
                )
                self.assertEqual(installed.returncode, 0, installed.stderr)
                state = (
                    env.home / ".local" / "state" / "noctalia-mod"
                    / "modules" / "probe.state"
                )
                self.assertIn("part.alpha", state.read_text())

                # The module drops the slot; the ledger must not keep advertising it.
                (module / "module.conf").write_text(
                    "MODULE_ID='probe'\nMODULE_TARGET='probe'\n", encoding="utf-8"
                )
                reinstalled = self._run(
                    env, fake_bin, "install", "probe", "--yes",
                    cli=tree / "bin" / "noctalia-mod",
                )
                self.assertEqual(reinstalled.returncode, 0, reinstalled.stderr)
                self.assertNotIn("part.alpha", state.read_text())

    def test_state_put_many_updates_in_place_and_appends_new_keys(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            state_root = env.home / ".local" / "state" / "noctalia-mod"
            target = state_root / "modules" / "probe.state"
            target.parent.mkdir(parents=True)
            target.write_text("a\t1\nb\t2\nc\t3\n", encoding="utf-8")

            script = (
                f"source {PROJECT / 'lib/common.sh'}; "
                f"source {PROJECT / 'lib/paths.sh'}; "
                f"source {PROJECT / 'lib/state.sh'}; "
                f"state_put_many {target} b 9 d 4"
            )
            child_env = os.environ.copy()
            child_env.update(
                {
                    "HOME": str(env.home),
                    "XDG_STATE_HOME": str(env.home / ".local" / "state"),
                    "XDG_CONFIG_HOME": str(env.home / ".config"),
                    "XDG_CACHE_HOME": str(env.home / ".cache"),
                }
            )
            result = subprocess.run(
                ["/bin/bash", "-c", script],
                cwd=PROJECT,
                env=child_env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                target.read_text(),
                "a\t1\nb\t9\nc\t3\nd\t4\n",
                "unmentioned keys, position and new keys must all be preserved",
            )

            odd = subprocess.run(
                ["/bin/bash", "-c", script.replace("b 9 d 4", "b 9 d")],
                cwd=PROJECT,
                env=child_env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(odd.returncode, 0)
            self.assertIn("key/value pairs", odd.stderr)

    def test_drift_reports_only_files_the_project_would_overwrite(self) -> None:
        """P1-1: user-owned and runtime-written files are not drift; managed ones are."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            installed = self._run(env, fake_bin, "install", "niri", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            niri = env.home / ".config" / "niri"

            clean = self._run(env, fake_bin, "plan", "niri")
            self.assertNotIn("drift", clean.stdout)

            # A __custom__ file, a declared preserve file, and the runtime symlink:
            # all three are expected to change outside the project.
            with (niri / "input__custom__.kdl").open("a", encoding="utf-8") as handle:
                handle.write("\n// user custom\n")
            with (niri / "monitor.kdl").open("a", encoding="utf-8") as handle:
                handle.write("\n// user monitor\n")
            eyecare = niri / "effects_eyecare.kdl"
            (niri / "effects.kdl").unlink()
            (niri / "effects.kdl").symlink_to(eyecare)

            tolerated = self._run(env, fake_bin, "plan", "niri")
            self.assertNotIn(
                "drift",
                tolerated.stdout,
                "editing __custom__/preserve files must not be reported as drift",
            )

            with (niri / "layout.kdl").open("a", encoding="utf-8") as handle:
                handle.write("\n// user edit\n")
            drifted = self._run(env, fake_bin, "plan", "niri")
            self.assertIn("drift\tniri\tchanged", drifted.stdout)

            redeployed = self._run(env, fake_bin, "install", "niri", "--yes")
            self.assertEqual(redeployed.returncode, 0, redeployed.stderr)
            settled = self._run(env, fake_bin, "plan", "niri")
            self.assertNotIn("drift", settled.stdout, "a redeploy must record a fresh fingerprint")

    def test_drift_reports_a_target_that_disappeared(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            installed = self._run(env, fake_bin, "install", "niri", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)

            shutil.rmtree(env.home / ".config" / "niri")
            planned = self._run(env, fake_bin, "plan", "niri")
            self.assertIn("drift\tniri\tmissing", planned.stdout)

    def test_deps_records_only_what_it_installed(self) -> None:
        """P1-2: the ledger answers 'which packages are ours', so pre-existing ones stay out."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            # kitty is already on the system; everything else is missing.
            (fake_bin / "pacman").write_text(
                "#!/usr/bin/env bash\n"
                'if [[ ${1-} == -Q ]]; then\n'
                '    [[ "$*" == *kitty* ]] && exit 0\n'
                "    exit 1\n"
                "fi\n"
                "exit 0\n"
            )
            (fake_bin / "pacman").chmod(0o755)

            result = self._run(env, fake_bin, "deps", "niri", "--yes")
            self.assertEqual(result.returncode, 0, result.stderr)

            ledger = env.home / ".local" / "state" / "noctalia-mod" / "packages.tsv"
            recorded = dict(
                line.split("\t", 1) for line in ledger.read_text().splitlines()
            )
            self.assertEqual(recorded.get("niri"), "repo")
            self.assertEqual(recorded.get("libnotify"), "repo")
            self.assertNotIn("kitty", recorded, "a package we did not install is not our ledger entry")

            # Re-running must not duplicate entries.
            again = self._run(env, fake_bin, "deps", "niri", "--yes")
            self.assertEqual(again.returncode, 0, again.stderr)
            lines = ledger.read_text().splitlines()
            self.assertEqual(len(lines), len(set(lines)))

    def test_fresh_install_ships_effects_symlink_and_keeps_runtime_state(self) -> None:
        """A fresh niri install must resolve include "effects.kdl"; a runtime repoint wins."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            installed = self._run(env, fake_bin, "install", "niri", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)

            link = env.home / ".config" / "niri" / "effects.kdl"
            self.assertTrue(link.is_symlink(), "fresh install must provide effects.kdl")
            self.assertTrue(link.exists(), "effects.kdl must resolve without running any script")

            eyecare = env.home / ".config" / "niri" / "effects_eyecare.kdl"
            link.unlink()
            link.symlink_to(eyecare)
            redeployed = self._run(env, fake_bin, "install", "niri", "--yes")
            self.assertEqual(redeployed.returncode, 0, redeployed.stderr)
            self.assertEqual(
                link.resolve(),
                eyecare.resolve(),
                "runtime EyeCare link state must survive a redeploy",
            )

    def test_noctalia_ships_every_tool_its_config_references(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            installed = self._run(env, fake_bin, "install", "noctalia", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)

            noctalia = env.home / ".config" / "noctalia"
            for relative in (
                "tools/wallpaper-picker.py",
                "tools/orbit-launcher.py",
                "tools/orbit/config.py",
                "tools/orbit-items__custom__.toml",
                "wallpaper-hook.sh",
                "mpv-hook.lua",
            ):
                self.assertTrue((noctalia / relative).is_file(), relative)
            self.assertTrue(os.access(noctalia / "tools" / "orbit-launcher.py", os.X_OK))
            self.assertTrue(os.access(noctalia / "wallpaper-hook.sh", os.X_OK))

            palette = (noctalia / "tools" / "orbit" / "palette.py").read_text()
            self.assertIn("~/.cache/noctalia-mod/palette.toml", palette)
            self.assertNotIn("nyxuri", palette.lower())

    def test_reference_check_rejects_a_dangling_reference(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            clean = self._run(env, fake_bin, "check")
            self.assertEqual(clean.returncode, 0, clean.stderr)

            with tempfile.TemporaryDirectory() as tmp:
                tree = Path(tmp) / "noctalia-mod"
                shutil.copytree(PROJECT, tree)
                module = tree / "modules" / "probe"
                (module / "files").mkdir(parents=True)
                (module / "module.conf").write_text(
                    "MODULE_ID='probe'\nMODULE_TARGET='probe'\n", encoding="utf-8"
                )
                (module / "files" / "probe.conf").write_text(
                    'path = "~/.config/absent/thing.conf"\n', encoding="utf-8"
                )

                result = self._run(
                    env, fake_bin, "check", cli=tree / "bin" / "noctalia-mod"
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("absent/thing.conf", result.stdout)

    def test_deploy_refuses_when_a_reference_is_dangling(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            with tempfile.TemporaryDirectory() as tmp:
                tree = Path(tmp) / "noctalia-mod"
                shutil.copytree(PROJECT, tree)
                module = tree / "modules" / "probe"
                (module / "files").mkdir(parents=True)
                (module / "module.conf").write_text(
                    "MODULE_ID='probe'\nMODULE_TARGET='probe'\n", encoding="utf-8"
                )
                (module / "files" / "probe.conf").write_text(
                    'path = "~/.config/absent/thing.conf"\n', encoding="utf-8"
                )

                result = self._run(
                    env, fake_bin, "install", "probe", "--yes",
                    cli=tree / "bin" / "noctalia-mod",
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unresolved-ref", result.stdout)
                self.assertFalse((env.home / ".config" / "probe").exists())

    def _lib_run(
        self, env: TempEnv, script: str, **overrides: str
    ) -> subprocess.CompletedProcess[str]:
        child_env = os.environ.copy()
        child_env.update(
            {
                "HOME": str(env.home),
                "XDG_CONFIG_HOME": str(env.home / ".config"),
                "XDG_STATE_HOME": str(env.home / ".local" / "state"),
                "XDG_CACHE_HOME": str(env.home / ".cache"),
            }
        )
        child_env.update(overrides)
        return subprocess.run(
            ["/bin/bash", "-c", script],
            cwd=PROJECT,
            env=child_env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_root_is_refused_by_the_uid_guard(self) -> None:
        with TempEnv() as env:
            refused = self._lib_run(
                env, f"source {PROJECT / 'lib/common.sh'}; require_non_root 0"
            )
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn("do not run noctalia-mod as root", refused.stderr)

            allowed = self._lib_run(
                env, f"source {PROJECT / 'lib/common.sh'}; require_non_root 1000"
            )
            self.assertEqual(allowed.returncode, 0, allowed.stderr)

    def test_environment_summary_reports_what_the_host_is_missing(self) -> None:
        with TempEnv() as env:
            bare = env.home / "bare-bin"
            bare.mkdir()
            script = f"source {PROJECT / 'lib/common.sh'}; environment_summary"

            missing = self._lib_run(env, script, PATH=str(bare))
            self.assertEqual(missing.returncode, 0, missing.stderr)
            self.assertIn("niri is not currently on PATH", missing.stdout)
            self.assertIn("Noctalia is not currently on PATH", missing.stdout)

            present = env.home / "full-bin"
            present.mkdir()
            for name in ("niri", "noctalia"):
                (present / name).write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
                (present / name).chmod(0o755)
            found = self._lib_run(env, script, PATH=str(present))
            self.assertNotIn("not currently on PATH", found.stdout)

            # The CachyOS line must follow the marker, whichever host runs this.
            marker = env.home / "cachyos-release"
            marker.write_text("", encoding="utf-8")
            on_target = self._lib_run(
                env, script, PATH=str(present), NOCTALIA_MOD_CACHYOS_MARKER=str(marker)
            )
            self.assertIn("CachyOS detected", on_target.stdout)
            off_target = self._lib_run(
                env,
                script,
                PATH=str(present),
                NOCTALIA_MOD_CACHYOS_MARKER=str(env.home / "absent"),
            )
            self.assertIn("CachyOS marker not found", off_target.stdout)

    def test_concurrent_runs_are_refused_by_the_project_lock(self) -> None:
        import fcntl

        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            state_root = env.home / ".local" / "state" / "noctalia-mod"
            state_root.mkdir(parents=True)

            with (state_root / "lock").open("w") as handle:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                blocked = self._run(env, fake_bin, "install", "niri", "--yes")
            self.assertNotEqual(blocked.returncode, 0)
            self.assertIn("already running", blocked.stderr)
            self.assertFalse(
                (env.home / ".config" / "niri").exists(),
                "a refused run must not deploy anything",
            )

            unblocked = self._run(env, fake_bin, "install", "niri", "--yes")
            self.assertEqual(unblocked.returncode, 0, unblocked.stderr)

    def test_uninstall_fallback_keeps_custom_and_preserve_content(self) -> None:
        """Without a recovery snapshot, only managed files may go away."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            installed = self._run(env, fake_bin, "install", "niri", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            niri = env.home / ".config" / "niri"

            state_file = (
                env.home / ".local" / "state" / "noctalia-mod" / "modules" / "niri.state"
            )
            recovery = dict(
                line.split("\t", 1) for line in state_file.read_text().splitlines()
            )["last_snapshot"]
            removed = self._run(env, fake_bin, "snapshot", "delete", recovery)
            self.assertEqual(removed.returncode, 0, removed.stderr)

            uninstalled = self._run(env, fake_bin, "uninstall", "niri", "--yes")
            self.assertEqual(uninstalled.returncode, 0, uninstalled.stderr)
            for kept in ("input__custom__.kdl", "__custom__.kdl", "monitor.kdl", "effects.kdl"):
                self.assertTrue((niri / kept).exists(), f"{kept} must survive uninstall")
            for gone in ("layout.kdl", "config.kdl", "animations.kdl"):
                self.assertFalse((niri / gone).exists(), f"{gone} should have been removed")

    def test_xdg_pictures_placeholder_follows_the_users_pictures_dir(self) -> None:
        """PLAN §4: the shipped config must not hardcode a locale-specific 图片 path."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            pictures = env.home / "Pics"
            pictures.mkdir()
            installed = self._run(
                env, fake_bin, "install", "noctalia", "niri", "--yes",
                extra_env={"FAKE_PICTURES": str(pictures)},
            )
            self.assertEqual(installed.returncode, 0, installed.stderr)
            config = env.home / ".config"
            office = (config / "noctalia" / "noctalia-config.toml").read_text()
            self.assertIn(f'directory = "{pictures}/Wallpapers"', office)
            self.assertIn(f'video_directory = "{pictures}/Wallpapers/video"', office)
            niri = (config / "niri" / "config.kdl").read_text()
            self.assertIn(f'screenshot-path "{pictures}/Screenshots/', niri)
            for text in (office, niri):
                self.assertNotIn("@XDG_PICTURES@", text, "an unsubstituted placeholder must never ship")
            self.assertNotIn(f"{env.home}/图片", office, "no locale-specific hardcoded path may ship")

    def test_xdg_pictures_falls_back_when_the_tool_cannot_answer(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            # 答不出来（缺失、超时、或给的不是绝对路径）时才回退 $HOME/Pictures。
            # 注意不能靠"删掉替身"来测这个：PATH 后面还有真的 xdg-user-dir，
            # 它在没有 user-dirs.dirs 时会按 XDG 规定答 $HOME。
            (fake_bin / "xdg-user-dir").write_text("#!/usr/bin/env bash\nexit 1\n")
            (fake_bin / "xdg-user-dir").chmod(0o755)
            installed = self._run(env, fake_bin, "install", "noctalia", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            office = (env.home / ".config" / "noctalia" / "noctalia-config.toml").read_text()
            self.assertIn(f'directory = "{env.home}/Pictures/Wallpapers"', office)

    def test_theme_sync_follows_the_current_mode(self) -> None:
        """P1-8: Noctalia sets color-scheme but never gtk-theme or settings.ini."""
        with TempEnv() as env:
            fake_bin, log = self._fake_commands(env)
            dark = self._run(env, fake_bin, "theme", "sync", extra_env={"FAKE_THEME_MODE": "dark"})
            self.assertEqual(dark.returncode, 0, dark.stderr)
            settings = env.home / ".config" / "gtk-3.0" / "settings.ini"
            self.assertIn("gtk-theme-name = adw-gtk3-dark", settings.read_text())
            self.assertIn("gtk-application-prefer-dark-theme = true", settings.read_text())
            self.assertIn(
                "gsettings <set> <org.gnome.desktop.interface> <color-scheme> <prefer-dark>",
                log.read_text(),
            )
            self.assertIn(
                "gsettings <set> <org.gnome.desktop.interface> <gtk-theme> <adw-gtk3-dark>",
                log.read_text(),
            )

            light = self._run(env, fake_bin, "theme", "sync", extra_env={"FAKE_THEME_MODE": "light"})
            self.assertEqual(light.returncode, 0, light.stderr)
            self.assertIn("gtk-theme-name = adw-gtk3", settings.read_text())
            self.assertIn("gtk-application-prefer-dark-theme = false", settings.read_text())
            for version in ("gtk-3.0", "gtk-4.0"):
                self.assertTrue((env.home / ".config" / version / "settings.ini").is_file(), version)

    def test_theme_sync_preserves_unrelated_settings_ini_content(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            settings = env.home / ".config" / "gtk-3.0" / "settings.ini"
            settings.parent.mkdir(parents=True)
            settings.write_text(
                "[Settings]\ngtk-theme-name = old-theme\ngtk-font-name = Some Font 11\n",
                encoding="utf-8",
            )
            result = self._run(env, fake_bin, "theme", "sync", extra_env={"FAKE_THEME_MODE": "dark"})
            self.assertEqual(result.returncode, 0, result.stderr)
            content = settings.read_text()
            self.assertIn("gtk-font-name = Some Font 11", content)
            self.assertIn("gtk-theme-name = adw-gtk3-dark", content)
            self.assertNotIn("old-theme", content)

    def test_theme_status_reports_what_is_expected(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            result = self._run(env, fake_bin, "theme", "status", extra_env={"FAKE_THEME_MODE": "light"})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("mode\tlight", result.stdout)
            self.assertIn("expected-gtk-theme\tadw-gtk3", result.stdout)

    def test_deploy_syncs_the_theme_without_failing_the_install(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            (fake_bin / "gsettings").write_text("#!/usr/bin/env bash\nexit 1\n")
            (fake_bin / "gsettings").chmod(0o755)
            installed = self._run(env, fake_bin, "install", "noctalia", "--yes")
            self.assertEqual(
                installed.returncode, 0,
                "a broken gsettings must not fail a successful config deploy",
            )
            self.assertTrue((env.home / ".config" / "gtk-3.0" / "settings.ini").is_file())

    def test_wallpaper_deploy_records_only_what_it_placed(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            pictures = env.home / "Pics"
            first = self._run(
                env, fake_bin, "wallpapers", "deploy",
                extra_env={"FAKE_PICTURES": str(pictures)},
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            wallpapers = pictures / "Wallpapers"
            self.assertTrue((wallpapers / "lawson_fuji.webp").is_file())
            ledger = wallpapers / ".noctalia-mod-managed"
            self.assertEqual(ledger.read_text().split(), ["lawson_fuji.webp"])
            self.assertIn("1 new", first.stdout)

            # 用户自己的图不属于我们，也不该进账本。
            (wallpapers / "mine.webp").write_text("user file\n", encoding="utf-8")
            second = self._run(
                env, fake_bin, "wallpapers", "deploy",
                extra_env={"FAKE_PICTURES": str(pictures)},
            )
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertIn("0 new, 1 already present", second.stdout)
            self.assertEqual(ledger.read_text().split(), ["lawson_fuji.webp"])

    def test_wallpapers_remove_keeps_user_files_and_refuses_unsafe_entries(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            pictures = env.home / "Pics"
            self._run(env, fake_bin, "wallpapers", "deploy", extra_env={"FAKE_PICTURES": str(pictures)})
            wallpapers = pictures / "Wallpapers"
            (wallpapers / "mine.webp").write_text("user file\n", encoding="utf-8")

            removed = self._run(
                env, fake_bin, "wallpapers", "remove", extra_env={"FAKE_PICTURES": str(pictures)}
            )
            self.assertEqual(removed.returncode, 0, removed.stderr)
            self.assertFalse((wallpapers / "lawson_fuji.webp").exists())
            self.assertTrue((wallpapers / "mine.webp").is_file(), "only ledger entries may be removed")
            self.assertFalse((wallpapers / ".noctalia-mod-managed").exists(), "an empty ledger is deleted")

            # 手改过的账本里出现越界路径：拒绝，并且留在账本里等下次再报。
            (wallpapers / ".noctalia-mod-managed").write_text("../../etc/passwd\n", encoding="utf-8")
            unsafe = self._run(
                env, fake_bin, "wallpapers", "remove", extra_env={"FAKE_PICTURES": str(pictures)}
            )
            self.assertEqual(unsafe.returncode, 0, unsafe.stderr)
            self.assertIn("refusing an unsafe ledger entry", unsafe.stderr)
            self.assertEqual(
                (wallpapers / ".noctalia-mod-managed").read_text().strip(), "../../etc/passwd"
            )
            self.assertTrue(Path("/etc/passwd").is_file())

    def test_setup_deploys_wallpapers_but_install_does_not(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            pictures = env.home / "Pics"
            extra = {"FAKE_PICTURES": str(pictures)}

            installed = self._run(env, fake_bin, "install", "kitty", "--yes", extra_env=extra)
            self.assertEqual(installed.returncode, 0, installed.stderr)
            self.assertFalse((pictures / "Wallpapers").exists(), "install only touches ~/.config")

            configured = self._run(env, fake_bin, "setup", "--yes", extra_env=extra)
            self.assertEqual(configured.returncode, 0, configured.stderr)
            self.assertTrue((pictures / "Wallpapers" / "lawson_fuji.webp").is_file())
            self.assertIn("wallpapers\t1 new", configured.stdout)

    def test_runtime_written_files_do_not_report_drift(self) -> None:
        """P1-9: Noctalia rewrites these in place, so they must not count as drift."""
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            installed = self._run(env, fake_bin, "install", "kitty", "starship", "--yes")
            self.assertEqual(installed.returncode, 0, installed.stderr)
            config = env.home / ".config"

            clean = self._run(env, fake_bin, "plan", "kitty", "starship")
            self.assertNotIn("drift", clean.stdout)

            # 模拟 Noctalia 的内置模板：改写 kitty.conf / themes/noctalia.conf / starship.toml
            with (config / "kitty" / "kitty.conf").open("a", encoding="utf-8") as handle:
                handle.write("\ninclude themes/noctalia.conf\n")
            with (config / "kitty" / "themes" / "noctalia.conf").open("a", encoding="utf-8") as handle:
                handle.write("color0 #000000\n")
            with (config / "starship.toml").open("a", encoding="utf-8") as handle:
                handle.write("# >>> NOCTALIA STARSHIP PALETTE >>>\n")

            rewritten = self._run(env, fake_bin, "plan", "kitty", "starship")
            self.assertEqual(rewritten.returncode, 0, rewritten.stderr)
            self.assertNotIn(
                "drift", rewritten.stdout,
                "files declared as runtime-written must not be reported as drift",
            )
            self.assertIn(
                "include themes/noctalia.conf",
                (config / "kitty" / "kitty.conf").read_text(),
                "declaring a runtime writer must not make the file preserve-on-deploy",
            )

    def test_runtime_written_files_are_still_overwritten_by_a_deploy(self) -> None:
        with TempEnv() as env:
            fake_bin, _ = self._fake_commands(env)
            self._run(env, fake_bin, "install", "starship", "--yes")
            target = env.home / ".config" / "starship.toml"
            shipped = target.read_text()
            with target.open("a", encoding="utf-8") as handle:
                handle.write("\n# runtime noise\n")

            again = self._run(env, fake_bin, "install", "starship", "--yes")
            self.assertEqual(again.returncode, 0, again.stderr)
            self.assertEqual(
                target.read_text(), shipped,
                "runtime-written is about the fingerprint only — the module still owns the file",
            )

    def test_module_metadata_is_validated(self) -> None:
        cases = {
            "id mismatch": (
                "MODULE_ID='other'\nMODULE_TARGET='probe'\n",
                "module id mismatch",
            ),
            "escaping target": (
                "MODULE_ID='probe'\nMODULE_TARGET='../escape'\n",
                "invalid target",
            ),
            "invalid package": (
                "MODULE_ID='probe'\nMODULE_TARGET='probe'\n"
                "MODULE_REPO_PACKAGES=('not a package')\n",
                "invalid package",
            ),
            "required command without a package": (
                "MODULE_ID='probe'\nMODULE_TARGET='probe'\n"
                "MODULE_REQUIRED_COMMANDS=('no-package-here')\n",
                "invalid required command",
            ),
            "invalid part slot": (
                "MODULE_ID='probe'\nMODULE_TARGET='probe'\nMODULE_PARTS=(Bad)\n",
                "invalid part",
            ),
            "escaping runtime-write": (
                "MODULE_ID='probe'\nMODULE_TARGET='probe'\n"
                "MODULE_RUNTIME_WRITES=('../escape')\n",
                "invalid relative path",
            ),
        }
        for label, (conf, expected) in cases.items():
            with self.subTest(label), TempEnv() as env:
                root = env.home / "project"
                (root / "modules" / "probe" / "files").mkdir(parents=True)
                (root / "modules" / "probe" / "module.conf").write_text(
                    conf, encoding="utf-8"
                )
                (root / "modules" / "probe" / "files" / "probe.conf").write_text(
                    "x\n", encoding="utf-8"
                )
                script = (
                    f"source {PROJECT / 'lib/common.sh'}; "
                    f"source {PROJECT / 'lib/paths.sh'}; "
                    f"source {PROJECT / 'lib/module-loader.sh'}; "
                    "module_load probe"
                )
                result = self._lib_run(env, script, NOCTALIA_MOD_ROOT=str(root))
                self.assertNotEqual(result.returncode, 0, label)
                self.assertIn(expected, result.stderr, label)


if __name__ == "__main__":
    unittest.main()
