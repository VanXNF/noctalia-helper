"""Temporary HOME isolation for the noctalia-mod test suite.

Deliberately dependency-free: the sub-project has to be runnable on its own,
without importing anything from the sibling Nyxuri engine.
"""

from __future__ import annotations

import tempfile
from pathlib import Path


class TempEnv:
    """A throwaway HOME with the state directory the CLI expects.

    The suite hands an explicit environment to every subprocess, so this only
    has to provide the tree — it never patches the real ``os.environ``.
    """

    def __init__(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.home = Path(self._tmp.name)

    def __enter__(self) -> "TempEnv":
        for relative in (".config", ".cache", ".local/bin", ".local/state", "runtime"):
            (self.home / relative).mkdir(parents=True, exist_ok=True)
        return self

    def __exit__(self, *exc: object) -> bool:
        self._tmp.cleanup()
        return False
