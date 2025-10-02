# restcherry_patch.py — robust, indent-aware replacement of ApiApplication.get_conf()
import sys
import ast
from pathlib import Path
import importlib.util

# Locate installed 'salt' package dir without importing its submodules
spec = importlib.util.find_spec("salt")
if spec is None or not spec.submodule_search_locations:
    sys.exit("ERROR: could not locate 'salt' package (is it installed in this image?)")

salt_dir = Path(list(spec.submodule_search_locations)[0])
app_path = salt_dir / "netapi" / "rest_cherrypy" / "app.py"

src = app_path.read_text(encoding="utf-8")

# Idempotent: skip if our marker already present
if "BEGIN: user-configurable CherryPy merges" in src:
    print("Already patched:", app_path)
    sys.exit(0)

# Parse and find def get_conf(self):
tree = ast.parse(src)
target = None
for node in ast.walk(tree):
    if isinstance(node, ast.FunctionDef) and node.name == "get_conf":
        if node.args.args and node.args.args[0].arg == "self":
            target = node
            break

if not target or not hasattr(target, "lineno") or not hasattr(target, "end_lineno"):
    sys.exit(f"ERROR: could not locate get_conf() in {app_path}")

lines = src.splitlines(keepends=True)
start = target.lineno - 1           # 0-based start line index
end = target.end_lineno             # exclusive end index

# Determine the existing indentation for this method (spaces/tabs preserved)
orig_line = lines[start]
leading_ws = orig_line[: len(orig_line) - len(orig_line.lstrip())]

# New function body (no leading indentation here; we'll add it)
new_fn = '''
def get_conf(self):
    """
    Combine the CherryPy configuration with the rest_cherrypy config values
    pulled from the master config and return the CherryPy configuration
    """
    conf = {
        "global": {
            "server.socket_host": self.apiopts.get("host", "0.0.0.0"),
            "server.socket_port": self.apiopts.get("port", 8000),
            "server.thread_pool": self.apiopts.get("thread_pool", 100),
            "server.socket_queue_size": self.apiopts.get("queue_size", 30),
            "max_request_body_size": self.apiopts.get("max_request_body_size", 1048576),
            "debug": self.apiopts.get("debug", False),
            "log.access_file": self.apiopts.get("log_access_file", ""),
            "log.error_file": self.apiopts.get("log_error_file", ""),
        },
        "/": {
            "request.dispatch": cherrypy.dispatch.MethodDispatcher(),
            "tools.trailing_slash.on": True,
            "tools.gzip.on": True,
            "tools.html_override.on": True,
            "tools.cors_tool.on": True,
        },
    }

    # --- BEGIN: user-configurable CherryPy merges ---
    # Allow extra CherryPy *global* keys via: rest_cherrypy: global: {...}
    user_global = self.apiopts.get("global", {})
    if isinstance(user_global, dict):
        conf["global"].update(user_global)

    # Allow extra root ("/") tool/path keys via: rest_cherrypy: root: {...}
    user_root = self.apiopts.get("root", {})
    if isinstance(user_root, dict):
        conf["/"].update(user_root)

    # Convenience: map any top-level rest_cherrypy keys starting with "tools."
    # onto the root ("/") section.
    for k, v in self.apiopts.items():
        if isinstance(k, str) and k.startswith("tools."):
            conf["/"][k] = v
    # --- END: user-configurable CherryPy merges ---

    if salt.utils.versions.version_cmp(cherrypy.__version__, "12.0.0") < 0:
        conf["global"]["engine.timeout_monitor.on"] = self.apiopts.get("expire_responses", True)

    if cpstats and self.apiopts.get("collect_stats", False):
        conf["/"]["tools.cpstats.on"] = True

    if "favicon" in self.apiopts:
        conf["/favicon.ico"] = {
            "tools.staticfile.on": True,
            "tools.staticfile.filename": self.apiopts["favicon"],
        }

    if self.apiopts.get("debug", False) is False:
        conf["global"]["environment"] = "production"

    if "static" in self.apiopts:
        conf[self.apiopts.get("static_path", "/static")] = {
            "tools.staticdir.on": True,
            "tools.staticdir.dir": self.apiopts["static"],
        }

    cherrypy.config.update(conf["global"])
    return conf
'''.lstrip("\n")

# Re-indent the whole replacement to match original method indentation
indented_new_fn = "".join(
    (leading_ws + ln if ln.strip() else ln)  # keep blank lines blank
    for ln in new_fn.splitlines(keepends=True)
)

# Splice and write back
new_src = "".join(lines[:start]) + indented_new_fn + "".join(lines[end:])
app_path.write_text(new_src, encoding="utf-8")
print(f"Patched {app_path} (lines {start+1}-{end}), indent='{leading_ws.replace(chr(9),'\\t')}'")