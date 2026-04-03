#!/usr/bin/env python3
import argparse
import json
import pathlib
import re
import socket
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROW_BLOCK_RE = (
    r"(?ms)^level{level}_row{row}:"
    r"(?:[ \t]*\.fill[^\n]*\n|\n(?:\s*\.byte[^\n]*\n|\s*\.fill[^\n]*\n)+)"
)

PALETTE = [
    {"label": "Erase", "tile": 0, "color": "#9ddcff"},
    {"label": "Dirt", "tile": 1, "color": "#8b5a2b"},
    {"label": "Grass", "tile": 3, "color": "#3cb043"},
    {"label": "Stone", "tile": 2, "color": "#8a8a8a"},
    {"label": "Chest", "tile": 4, "color": "#8b5a2b"},
    {"label": "Pineapple", "tile": 5, "color": "#f4b400"},
    {"label": "Heart", "tile": 6, "color": "#e53935"},
    {"label": "Key", "tile": 7, "color": "#f2c94c"},
]


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


def make_html():
    return """<!doctype html>
<html>
<head>
  <meta charset=\"utf-8\" />
  <title>Sprite Demo Level Editor</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; background: #1e1e1e; color: #ddd; }
    .top { padding: 10px 12px; border-bottom: 1px solid #333; display: flex; gap: 12px; align-items: center; flex-wrap: wrap; }
    .palette { padding: 8px 12px; border-bottom: 1px solid #333; display: flex; gap: 6px; flex-wrap: wrap; }
    button.tile { border: 2px solid #444; color: #111; font-weight: 600; padding: 6px 10px; cursor: pointer; }
    button.tile.active { border-color: #fff; }
    #status { padding: 8px 12px; color: #9fd; }
    #wrap { padding: 10px 12px; overflow: auto; height: calc(100vh - 150px); }
    #grid { image-rendering: pixelated; border: 1px solid #444; background: #111; cursor: crosshair; }
    select, button.action { background: #2a2a2a; color: #ddd; border: 1px solid #555; padding: 6px 8px; }
  </style>
</head>
<body>
  <div class=\"top\">
    <label>Level <select id=\"levelSelect\"></select></label>
    <button class=\"action\" id=\"saveBtn\">Save</button>
    <span id=\"filePath\"></span>
  </div>
  <div class=\"palette\" id=\"palette\"></div>
  <div id=\"status\">Loading...</div>
  <div id=\"wrap\"><canvas id=\"grid\"></canvas></div>

<script>
let model = null;
let currentLevel = 0;
let currentTile = 1;
let dragging = false;
const cellW = 12;
const cellH = 18;
const tileColors = {0:'#9ddcff',1:'#8b5a2b',2:'#8a8a8a',3:'#3cb043',4:'#8b5a2b',5:'#f4b400',6:'#e53935',7:'#f2c94c'};

function setStatus(msg){ document.getElementById('status').textContent = msg; }

function buildPalette(){
  const holder = document.getElementById('palette');
  holder.innerHTML = '';
  for (const p of model.palette){
    const b = document.createElement('button');
    b.className = 'tile' + (p.tile===currentTile ? ' active' : '');
    b.style.background = p.color;
    b.textContent = p.label;
    b.onclick = () => { currentTile = p.tile; buildPalette(); setStatus(`Selected tile ${currentTile}`); };
    holder.appendChild(b);
  }
}

function buildLevelSelect(){
  const sel = document.getElementById('levelSelect');
  sel.innerHTML = '';
  for (let i=0;i<model.level_count;i++){
    const o = document.createElement('option');
    o.value = i;
    o.textContent = String(i+1);
    sel.appendChild(o);
  }
  sel.value = currentLevel;
  sel.onchange = () => { currentLevel = parseInt(sel.value, 10); draw(); };
}

function draw(){
  const canvas = document.getElementById('grid');
  const ctx = canvas.getContext('2d');
  const rows = model.level_rows;
  const cols = model.level_width;
  canvas.width = cols * cellW;
  canvas.height = rows * cellH;

  const level = model.levels[currentLevel];
  for (let r=0;r<rows;r++){
    for (let c=0;c<cols;c++){
      ctx.fillStyle = tileColors[level[r][c]] || '#000';
      ctx.fillRect(c*cellW, r*cellH, cellW, cellH);
      ctx.strokeStyle = '#303030';
      ctx.strokeRect(c*cellW, r*cellH, cellW, cellH);
    }
  }

  setStatus(`Level ${currentLevel+1}/${model.level_count} | rows ${rows} | width ${cols}`);
}

function paintFromEvent(ev){
  const canvas = document.getElementById('grid');
  const rect = canvas.getBoundingClientRect();
  const x = ev.clientX - rect.left;
  const y = ev.clientY - rect.top;
  const c = Math.floor(x / cellW);
  const r = Math.floor(y / cellH);
  if (r < 0 || c < 0 || r >= model.level_rows || c >= model.level_width) return;
  model.levels[currentLevel][r][c] = currentTile;
  draw();
}

async function save(){
  const res = await fetch('/api/save', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({levels: model.levels})
  });
  const data = await res.json();
  if (!res.ok){ setStatus('Save failed: ' + data.error); return; }
  setStatus('Saved to ' + data.path);
}

async function init(){
  const res = await fetch('/api/data');
  model = await res.json();
  if (!res.ok){ setStatus('Load failed: ' + (model.error || 'unknown')); return; }

  document.getElementById('filePath').textContent = model.path;
  buildPalette();
  buildLevelSelect();
  draw();

  const canvas = document.getElementById('grid');
  canvas.addEventListener('mousedown', (e)=>{ dragging=true; paintFromEvent(e); });
  window.addEventListener('mouseup', ()=>{ dragging=false; });
  canvas.addEventListener('mousemove', (e)=>{ if (dragging) paintFromEvent(e); });
  document.getElementById('saveBtn').onclick = save;
}

init();
</script>
</body>
</html>
"""


def find_free_port(host="127.0.0.1"):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind((host, 0))
        return s.getsockname()[1]


def run_server(levelset_path: pathlib.Path, data):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            return

        def _json(self, code, payload):
            body = json.dumps(payload).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/" or self.path.startswith("/?"):
                html = make_html().encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(html)))
                self.end_headers()
                self.wfile.write(html)
                return

            if self.path == "/api/data":
                self._json(
                    200,
                    {
                        "path": str(levelset_path),
                        "palette": PALETTE,
                        "level_count": data["level_count"],
                        "level_rows": data["level_rows"],
                        "level_width": data["level_width"],
                        "levels": data["levels"],
                    },
                )
                return

            self._json(404, {"error": "not found"})

        def do_POST(self):
            if self.path != "/api/save":
                self._json(404, {"error": "not found"})
                return

            try:
                length = int(self.headers.get("Content-Length", "0"))
                payload = json.loads(self.rfile.read(length).decode("utf-8"))
                levels = payload.get("levels")
                if not isinstance(levels, list):
                    raise ValueError("missing levels")
                data["levels"] = levels
                write_levelset(levelset_path, data)
                self._json(200, {"ok": True, "path": str(levelset_path)})
            except Exception as exc:
                self._json(400, {"error": str(exc)})

    port = find_free_port()
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    url = f"http://127.0.0.1:{port}/"
    print(f"Level editor running at {url}")
    print("Press Ctrl+C to stop.")
    webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


def main():
    parser = argparse.ArgumentParser(description="Mouse-based editor for sprite_demo level include files")
    parser.add_argument("file", help="Path to active file (main.asm or a levelset include)")
    args = parser.parse_args()

    source_path = pathlib.Path(args.file)
    if not source_path.exists():
        raise SystemExit(f"Input file does not exist: {source_path}")

    levelset_path = resolve_levelset_from_path(source_path)
    data = parse_levelset(levelset_path)
    run_server(levelset_path, data)


if __name__ == "__main__":
    main()
