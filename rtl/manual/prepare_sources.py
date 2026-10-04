"""Separate legacy module contracts from inline listings without changing RTL."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
legacy = ROOT / "rtl_microarchitecture_spec.inline_legacy.md"
if not legacy.exists():
    legacy.write_bytes((ROOT / "rtl_microarchitecture_spec.md").read_bytes())
bundle = (ROOT / "components/hardware_blocks.sv").read_text()
source_map = {}
for folder in (ROOT / "components", ROOT / "numerical"):
    for path in folder.glob("*.sv"):
        if "_tb" in path.name:
            continue
        for kind, name in re.findall(r"(?m)^\s*(module|package)\s+(\w+)\b", path.read_text()):
            source_map[name] = (path, kind)
for match in re.finditer(r"(?ms)^module\s+(\w+)\b.*?^endmodule\b", bundle):
    name = match.group(1)
    path = ROOT / "components/library" / f"{name}.sv"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("// Extracted executable baseline; physical GPU parameters remain provisional.\n" + match.group() + "\n")
    source_map[name] = (path, "module")

sections = {}
parts = re.split(r"(?m)^### 4\.(\d+)\. (.+)\n", legacy.read_text())
for index in range(1, len(parts), 3):
    number, title, text = int(parts[index]), parts[index + 1], parts[index + 2]
    if number == 58:
        text = re.split(r"(?m)^## 5\.", text)[0]
    names = []
    def replace_code(match):
        links = []
        for kind, name in re.findall(r"(?m)^\s*(module|package)\s+(\w+)\b", match.group(1)):
            if name not in source_map:
                matches = [p for p in ROOT.rglob("*.sv") if "failure" not in str(p) and "_tb" not in p.name
                           and re.search(r"(?m)^\s*" + kind + r"\s+" + re.escape(name) + r"\b", p.read_text())]
                if not matches:
                    raise ValueError("Missing source: " + name)
                source_map[name] = (sorted(matches)[0], kind)
            path, _ = source_map[name]
            names.append(name)
            links.append(f"[{path.name}]({path.resolve()})")
        if not links:
            raise ValueError("Code listing has no named source")
        return "\n**Source implementation:** " + ", ".join(links) + "\n"
    text = re.sub(r"```systemverilog\n(.*?)```", replace_code, text, flags=re.S)
    def relink(match):
        label, target = match.groups()
        if target.startswith(("http:", "https:", "#", "/")):
            return match.group()
        path, separator, anchor = target.partition("#")
        return f"[{label}]({(ROOT / path).resolve()}{separator}{anchor})"
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", relink, text)
    text = text.replace("**Inline behavioral implementation.**", "**Linked behavioral implementation.**")
    sections[number] = {"title": title, "text": text.strip(), "modules": list(dict.fromkeys(names))}

for name, (source, kind) in source_map.items():
    if kind != "module":
        continue
    header = re.search(r"(?s)\bmodule\s+" + re.escape(name) + r"\b(.*?);", source.read_text()).group(1)
    model = "ClockedModel" if re.search(r"\bclk\b", header) and re.search(r"\brst\b", header) else "CombinationalModel"
    (ROOT / "cpp" / f"{name}.hpp").write_text(f'#pragma once\n#include "component_model.hpp"\n#include <V{name}.h>\nnamespace rtx_model {{ using {name} = {model}<V{name}>; }}\n')
(ROOT / "manual/legacy_sections.json").write_text(json.dumps(sections, indent=2) + "\n")
(ROOT / "manual/source_map.json").write_text(json.dumps({n: {"path": str(p.resolve()), "kind": k} for n, (p, k) in source_map.items()}, indent=2) + "\n")
print(f"Prepared {len(sections)} implementation contracts and {len(source_map)} source references")
