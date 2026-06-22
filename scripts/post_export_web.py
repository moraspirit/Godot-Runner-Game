#!/usr/bin/env python3
"""Post-process Godot web export for cache-safe deploys.

Heavy files (wasm/pck/js) get a build id in the filename so browsers keep
them cached until you ship a new version. index.html and version.json stay
small and always point at the latest build id.

Usage (CI): BUILD_ID=$GITHUB_SHA SIM_VERSION=6 python3 scripts/post_export_web.py
"""
from __future__ import annotations

import json
import os
import re
import shutil
import sys
from pathlib import Path


def main() -> int:
	web = Path(os.environ.get("WEB_DIR", "build/web"))
	if not web.is_dir():
		print(f"error: web dir not found: {web}", file=sys.stderr)
		return 1

	build = os.environ.get("BUILD_ID") or os.environ.get("GITHUB_SHA") or "dev"
	build = build.strip()[:12]
	sim_version = int(os.environ.get("SIM_VERSION", "6"))

	# Versioned copies of the large artifacts (cached long-term by URL).
	for ext in (".wasm", ".pck", ".js"):
		src = web / f"index{ext}"
		if not src.is_file():
			print(f"warning: missing {src}")
			continue
		dst = web / f"index.{build}{ext}"
		shutil.copy2(src, dst)
		src.unlink()

	html_path = web / "index.html"
	if not html_path.is_file():
		print(f"error: missing {html_path}", file=sys.stderr)
		return 1

	html = html_path.read_text(encoding="utf-8")
	prefix = f"index.{build}"

	html = html.replace('src="index.js"', f'src="{prefix}.js"')
	html = re.sub(r'"executable"\s*:\s*"index"', f'"executable":"{prefix}"', html)
	html = re.sub(r'"index\.pck"', f'"{prefix}.pck"', html)
	html = re.sub(r'"index\.wasm"', f'"{prefix}.wasm"', html)

	meta = (
		f'<meta name="runner-build" content="{build}">\n'
		f'\t\t<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">\n'
	)
	if 'name="runner-build"' not in html:
		html = html.replace("<head>", f"<head>\n\t\t{meta}", 1)

	check_script = f"""
\t\t<script>
(function () {{
\tvar pageBuild = document.querySelector('meta[name="runner-build"]')?.content;
\tif (!pageBuild) return;
\tfetch('version.json?_=' + Date.now(), {{ cache: 'no-store' }})
\t\t.then(function (r) {{ return r.json(); }})
\t\t.then(function (v) {{
\t\t\tif (v.build && v.build !== pageBuild) {{
\t\t\t\tvar key = 'runner_html_reload_' + v.build;
\t\t\t\tif (!sessionStorage.getItem(key)) {{
\t\t\t\t\tsessionStorage.setItem(key, '1');
\t\t\t\t\tlocation.replace(location.pathname + '?b=' + v.build);
\t\t\t\t}}
\t\t\t}}
\t\t}})
\t\t.catch(function () {{}});
}})();
\t\t</script>
"""
	if "runner_html_reload_" not in html:
		html = html.replace("<body>", f"<body>{check_script}", 1)

	html_path.write_text(html, encoding="utf-8")

	(web / "version.json").write_text(
		json.dumps({"build": build, "sim_version": sim_version}, indent=2) + "\n",
		encoding="utf-8",
	)

	# GitHub Pages: skip Jekyll and keep custom domain when deploying the artifact.
	(web / ".nojekyll").write_text("", encoding="utf-8")
	repo_root = Path(__file__).resolve().parent.parent
	cname_src = repo_root / "CNAME"
	if cname_src.is_file():
		shutil.copy2(cname_src, web / "CNAME")

	print(f"post_export_web: build={build} sim_version={sim_version}")
	for ext in (".wasm", ".pck", ".js"):
		p = web / f"{prefix}{ext}"
		if p.is_file():
			print(f"  {p.name} ({p.stat().st_size // 1024} KiB)")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
