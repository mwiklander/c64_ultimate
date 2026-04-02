#!/usr/bin/env python3
import argparse
import pathlib
import re
import tkinter as tk
from tkinter import messagebox

TILE_COLORS = {
    0: "#9ddcff",  # sky / erase
    1: "#8b5a2b",  # dirt
    2: "#8a8a8a",  # stone
    3: "#3cb043",  # grass
    4: "#ffd54f",  # flag
    5: "#f4b400",  # pineapple
    6: "#e53935",  # heart
}

PALETTE = [
    ("Erase", 0),
    ("Dirt", 1),
    ("Grass", 3),
    ("Stone", 2),
    ("Pineapple", 5),
    ("Heart", 6),
    ("Flag", 4),
]

ROW_BLOCK_RE = (
    r"(?ms)^level{level}_row{row}:"
    r"(?:[ \t]*\.fill[^\n]*\n|\n(?:\s*\.byte[^\n]*\n|\s*\.fill[^\n]*\n)+)"
)


def parse_byte_values(line: str):
    return [int(x) for x in re.findall(r"\b\d+\b", line)]


def resolve_levelset_from_path(input_path: pathlib.Path) -> pathlib.Path:
    input_path = input_path.resolve()

    if input_path.name.startswith("levelset_") and input_path.suffix == ".inc":
        return input_path

    if input_path.name == "active_levelset.inc":
        return resolve_from_active_include(input_path)

    text = input_path.read_text(encoding="utf-8")
    m = re.search(r'\.include\s+"([^"]*levels/active_levelset\.inc)"', text)
    if not m:
        raise ValueError("Could not find levels/active_levelset.inc include in current file")

    active_inc = (input_path.parent / m.group(1)).resolve()
    if not active_inc.exists():
        raise FileNotFoundError(f"Active levelset include not found: {active_inc}")

    return resolve_from_active_include(active_inc)


def resolve_from_active_include(active_inc: pathlib.Path) -> pathlib.Path:
    text = active_inc.read_text(encoding="utf-8")
    m = re.search(r'\.include\s+"([^"]+)"', text)
    if not m:
        raise ValueError(f"No .include entry found in {active_inc}")
    target = (active_inc.parent / m.group(1)).resolve()
    if not target.exists():
        raise FileNotFoundError(f"Levelset file not found: {target}")
    return target


def parse_levelset(levelset_path: pathlib.Path):
    text = levelset_path.read_text(encoding="utf-8")

    m_count = re.search(r"^LEVEL_COUNT\s*=\s*(\d+)", text, re.MULTILINE)
    m_rows = re.search(r"^LEVEL_ROWS\s*=\s*(\d+)", text, re.MULTILINE)
    if not m_count or not m_rows:
        raise ValueError("LEVEL_COUNT / LEVEL_ROWS constants are missing in levelset")

    level_count = int(m_count.group(1))
    level_rows = int(m_rows.group(1))

    levels = []
    for level in range(1, level_count + 1):
        rows = []
        for row in range(level_rows):
            block_pat = ROW_BLOCK_RE.format(level=level, row=row)
            block_m = re.search(block_pat, text)
            if not block_m:
                raise ValueError(f"Missing block: level{level}_row{row}")
            block = block_m.group(0)

            fill_m = re.search(r"\.fill\s+(\d+)\s*,\s*(\d+)", block)
            if fill_m:
                width = int(fill_m.group(1))
                value = int(fill_m.group(2))
                rows.append([value] * width)
                continue

            vals = []
            for ln in block.splitlines():
                if ".byte" in ln:
                    vals.extend(parse_byte_values(ln))
            rows.append(vals)

        widths = {len(r) for r in rows}
        if len(widths) != 1:
            raise ValueError(f"Inconsistent row widths in level {level}: {sorted(widths)}")
        levels.append(rows)

    return {
        "text": text,
        "level_count": level_count,
        "level_rows": level_rows,
        "level_width": len(levels[0][0]),
        "levels": levels,
    }


def format_row_block(level_idx: int, row_idx: int, row_vals):
    out = [f"level{level_idx + 1}_row{row_idx}:"]
    for i in range(0, len(row_vals), 16):
        part = row_vals[i : i + 16]
        out.append("        .byte " + ",".join(str(v) for v in part))
    out.append("")
    return "\n".join(out)


def write_levelset(levelset_path: pathlib.Path, data):
    text = data["text"]
    level_count = data["level_count"]
    level_rows = data["level_rows"]

    for level in range(1, level_count + 1):
        for row in range(level_rows):
            block_pat = ROW_BLOCK_RE.format(level=level, row=row)
            repl = format_row_block(level - 1, row, data["levels"][level - 1][row])
            text, n = re.subn(block_pat, repl, text, count=1)
            if n != 1:
                raise ValueError(f"Could not replace level{level}_row{row}")

    levelset_path.write_text(text, encoding="utf-8")
    data["text"] = text


class EditorApp:
    def __init__(self, root, levelset_path: pathlib.Path, data):
        self.root = root
        self.levelset_path = levelset_path
        self.data = data
        self.level_index = 0
        self.current_tile = 1
        self.cell_w = 12
        self.cell_h = 18
        self.dragging = False

        self.root.title(f"Sprite Demo Level Editor - {levelset_path.name}")

        self.top = tk.Frame(root)
        self.top.pack(fill=tk.X, padx=8, pady=6)

        tk.Label(self.top, text=f"File: {levelset_path}").pack(side=tk.LEFT)

        tk.Label(self.top, text="   Level:").pack(side=tk.LEFT)
        self.level_var = tk.IntVar(value=1)
        self.level_spin = tk.Spinbox(
            self.top,
            from_=1,
            to=self.data["level_count"],
            width=4,
            textvariable=self.level_var,
            command=self.change_level,
        )
        self.level_spin.pack(side=tk.LEFT)

        tk.Button(self.top, text="Save", command=self.save).pack(side=tk.RIGHT)

        self.palette = tk.Frame(root)
        self.palette.pack(fill=tk.X, padx=8, pady=4)

        self.palette_buttons = []
        for label, tile in PALETTE:
            b = tk.Button(
                self.palette,
                text=label,
                width=10,
                bg=TILE_COLORS[tile],
                command=lambda t=tile: self.select_tile(t),
            )
            b.pack(side=tk.LEFT, padx=2)
            self.palette_buttons.append((tile, b))

        self.status_var = tk.StringVar()
        self.status = tk.Label(root, textvariable=self.status_var, anchor="w")
        self.status.pack(fill=tk.X, padx=8)

        holder = tk.Frame(root)
        holder.pack(fill=tk.BOTH, expand=True, padx=8, pady=6)

        self.canvas = tk.Canvas(holder, bg="#202020")
        self.hbar = tk.Scrollbar(holder, orient=tk.HORIZONTAL, command=self.canvas.xview)
        self.vbar = tk.Scrollbar(holder, orient=tk.VERTICAL, command=self.canvas.yview)
        self.canvas.configure(xscrollcommand=self.hbar.set, yscrollcommand=self.vbar.set)

        self.canvas.grid(row=0, column=0, sticky="nsew")
        self.vbar.grid(row=0, column=1, sticky="ns")
        self.hbar.grid(row=1, column=0, sticky="ew")

        holder.grid_rowconfigure(0, weight=1)
        holder.grid_columnconfigure(0, weight=1)

        self.rect_map = {}
        self.draw_grid()

        self.canvas.bind("<Button-1>", self.on_click)
        self.canvas.bind("<B1-Motion>", self.on_drag)
        self.canvas.bind("<ButtonRelease-1>", self.on_release)
        self.level_spin.bind("<Return>", lambda _e: self.change_level())
        self.root.bind("<Control-s>", lambda _e: self.save())

        self.select_tile(self.current_tile)
        self.update_status("Ready")

    def update_status(self, msg):
        self.status_var.set(
            f"{msg} | level {self.level_index + 1}/{self.data['level_count']} | "
            f"rows {self.data['level_rows']} | width {self.data['level_width']}"
        )

    def select_tile(self, tile):
        self.current_tile = tile
        for t, b in self.palette_buttons:
            b.configure(relief=(tk.SUNKEN if t == tile else tk.RAISED))
        self.update_status(f"Selected tile {tile}")

    def change_level(self):
        lvl = max(1, min(self.data["level_count"], int(self.level_var.get())))
        self.level_var.set(lvl)
        self.level_index = lvl - 1
        self.draw_grid()
        self.update_status("Level changed")

    def draw_grid(self):
        self.canvas.delete("all")
        self.rect_map.clear()
        rows = self.data["level_rows"]
        cols = self.data["level_width"]

        for r in range(rows):
            for c in range(cols):
                x0 = c * self.cell_w
                y0 = r * self.cell_h
                x1 = x0 + self.cell_w
                y1 = y0 + self.cell_h
                tile = self.data["levels"][self.level_index][r][c]
                rect = self.canvas.create_rectangle(
                    x0,
                    y0,
                    x1,
                    y1,
                    fill=TILE_COLORS.get(tile, "#000000"),
                    outline="#303030",
                )
                self.rect_map[(r, c)] = rect

        self.canvas.configure(scrollregion=(0, 0, cols * self.cell_w, rows * self.cell_h))

    def paint_at_event(self, event):
        x = self.canvas.canvasx(event.x)
        y = self.canvas.canvasy(event.y)
        c = int(x // self.cell_w)
        r = int(y // self.cell_h)

        if r < 0 or c < 0:
            return
        if r >= self.data["level_rows"] or c >= self.data["level_width"]:
            return

        row = self.data["levels"][self.level_index][r]
        if row[c] == self.current_tile:
            return

        row[c] = self.current_tile
        rect = self.rect_map[(r, c)]
        self.canvas.itemconfigure(rect, fill=TILE_COLORS.get(self.current_tile, "#000000"))

    def on_click(self, event):
        self.dragging = True
        self.paint_at_event(event)

    def on_drag(self, event):
        if self.dragging:
            self.paint_at_event(event)

    def on_release(self, _event):
        self.dragging = False

    def save(self):
        try:
            write_levelset(self.levelset_path, self.data)
            self.update_status("Saved")
        except Exception as exc:
            messagebox.showerror("Save failed", str(exc))


def main():
    parser = argparse.ArgumentParser(description="Mouse-based editor for sprite_demo level include files")
    parser.add_argument("file", help="Path to active file (main.asm or a levelset include)")
    args = parser.parse_args()

    source_path = pathlib.Path(args.file)
    if not source_path.exists():
        raise SystemExit(f"Input file does not exist: {source_path}")

    levelset_path = resolve_levelset_from_path(source_path)
    data = parse_levelset(levelset_path)

    root = tk.Tk()
    app = EditorApp(root, levelset_path, data)
    root.geometry("1200x520")
    root.mainloop()


if __name__ == "__main__":
    main()
