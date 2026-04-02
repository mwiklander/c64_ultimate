#!/usr/bin/env python3
import pathlib
import re
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOLS_DIR = REPO_ROOT / "tools"
sys.path.insert(0, str(TOOLS_DIR))

from level_editor_web import parse_levelset, write_levelset

FILES = [
    pathlib.Path("projects/sprite_demo/levels/levelset_default.inc"),
    pathlib.Path("projects/sprite_demo/levels/levelset_alt.inc"),
]


def gen_ptr_table(sig: str) -> str:
    name = "level_row_ptr_lo" if sig == "<" else "level_row_ptr_hi"
    lines = [f"{name}:"]
    for level in range(1, 6):
        for base in (0, 5, 10):
            parts = ",".join(f"{sig}level{level}_row{r}" for r in range(base, base + 5))
            lines.append(f"        .byte {parts}")
    return "\n".join(lines) + "\n\n"


for p in FILES:
    data = parse_levelset(p)

    for li in range(data["level_count"]):
        rows = data["levels"][li]
        width = data["level_width"]

        top_nonzero = any(any(v != 0 for v in rows[r]) for r in range(5))
        bottom_nonzero = any(any(v != 0 for v in rows[r]) for r in range(10, 15))

        if top_nonzero and not bottom_nonzero:
            old = [rows[r][:] for r in range(5)]
            for r in range(10):
                rows[r] = [0] * width
            for r in range(5):
                rows[10 + r] = old[r]

    write_levelset(p, data)

    text = p.read_text(encoding="utf-8")
    lo = gen_ptr_table("<")
    hi = gen_ptr_table(">")
    text = re.sub(r"(?ms)^level_row_ptr_lo:\n.*?^level_row_ptr_hi:\n.*?(?=^; Level 1 )", lo + hi, text)
    text = text.replace(
        "; Logical row 0..9 = new empty space above, row 10..14 = original playfield.\n",
        "; Logical rows are top-to-bottom: row 0 is top, row 14 is bottom.\n",
    )
    p.write_text(text, encoding="utf-8")
    print(f"updated {p}")
