"""Export the real-world HUD fixture, including tests only in this QA build.

Run after the normal web export. Keep other exporters idle: project and export
settings are temporarily changed, then restored byte-for-byte even on failure.
"""

from pathlib import Path
import re
import subprocess


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    presets = root / "export_presets.cfg"
    project = root / "project.godot"
    original_presets = presets.read_bytes()
    original_project = project.read_bytes()
    text = original_presets.decode()
    index = max(map(int, re.findall(r"\[preset\.(\d+)\]", text))) + 1
    block = text[:text.index("[preset.1]")]
    block = block.replace("preset.0", f"preset.{index}")
    block = block.replace('name="Web"', 'name="HUD Verification"')
    block = block.replace("tests/*, tools/*", "tools/*")
    block = block.replace("build/web/index.html", "build/web/hud-check.html")
    main_scene = b'run/main_scene="res://scenes/world.tscn"'
    if main_scene not in original_project:
        raise RuntimeError("The expected game main scene was not found")
    try:
        presets.write_text(text + "\n" + block)
        project.write_bytes(original_project.replace(
            main_scene, b'run/main_scene="res://tests/hud_web_check.tscn"'))
        subprocess.run([
            "godot", "--headless", "--path", str(root), "--export-release",
            "HUD Verification", str(root / "build/web/hud-check.html"),
        ], cwd=root, check=True)
    finally:
        presets.write_bytes(original_presets)
        project.write_bytes(original_project)


if __name__ == "__main__":
    main()
