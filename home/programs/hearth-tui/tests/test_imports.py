"""Every module imports. The build's bytecode step only WARNS on a syntax
error, so without this a broken widgets.py ships and crashes at launch."""

import importlib
import pkgutil

import hearth_tui


def test_all_modules_import():
    for mod in pkgutil.walk_packages(hearth_tui.__path__, "hearth_tui."):
        importlib.import_module(mod.name)
