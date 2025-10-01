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

# Always (re)patch get_conf so we can fix prior bad inserts
# (We do not early-exit if the marker is present.)

# Parse and find class API.get_conf(self) or ApiApplication.get_conf(self)
tree = ast.parse(src)
cls_node = None
for node in ast.walk(tree):
    if isinstance(node, ast.ClassDef) and node.name in ("API", "ApiApplication"):
        cls_node = node
        break

if cls_node is None:
    sys.exit(f"ERROR: could not locate class API/ApiApplication in {app_path}")

method_node = None
for node in cls_node.body:
    if isinstance(node, ast.FunctionDef) and node.name == "get_conf":
        if node.args.args and node.args.args[0].arg == "self":
            method_node = node
            break

if method_node is None:
    # Fallback: insert a fresh get_conf(self) at the end of the class body
    lines = src.splitlines(keepends=True)
    # Compute class block start and find its indentation
    cls_start = cls_node.lineno - 1
    cls_line = lines[cls_start]
    cls_indent = cls_line[: len(cls_line) - len(cls_line.lstrip())]

    # Determine one-indent step used inside the class (fallback to 4 spaces)
    inner_indent = "    "
    # Try to infer from first method in class
    for n in cls_node.body:
        if isinstance(n, ast.FunctionDef):
            meth_line = lines[n.lineno - 1]
            inner_indent = meth_line[: len(meth_line) - len(meth_line.lstrip())]
            break

    # Our new method (unindented here); we'll indent with inner_indent
    new_method_src = '''

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
            "max_request_body_size": self.apiopts.get(
                "max_request_body_size", 1048576
            ),
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
        conf["global"]["engine.timeout_monitor.on"] = self.apiopts.get(
            "expire_responses", True
        )

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

    cherrypy.config.update(conf["global"])  # Add to global config
    return conf
'''

    # Indent method to be inside the class
    method_lines = []
    for ln in new_method_src.splitlines(keepends=True):
        if ln.strip():
            method_lines.append(inner_indent + ln)
        else:
            method_lines.append(ln)
    insert_text = "".join(method_lines)

    # Insert before the line where the class block ends
    # Find the end of class by using the last node end_lineno (fallback to next class or module end)
    end_line = max((getattr(n, 'end_lineno', 0) for n in cls_node.body), default=cls_node.lineno)
    insert_at = end_line
    new_src = "".join(lines[:insert_at]) + insert_text + "".join(lines[insert_at:])
    app_path.write_text(new_src, encoding="utf-8")
    print(f"Inserted fresh API.get_conf at lines {insert_at+1}-{insert_at+len(method_lines)}")
    sys.exit(0)

lines = src.splitlines(keepends=True)
start = method_node.lineno - 1  # 0-based start line index
end = method_node.end_lineno    # exclusive end index

# Determine the indentation of the method within the class
# Take the whitespace of the original 'def get_conf' line
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
                "max_request_body_size": self.apiopts.get(
                    "max_request_body_size", 1048576
                ),
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
            # CherryPy >= 12.0 no longer supports "timeout_monitor", only set
            # this config option when using an older version of CherryPy.
            # See Issue #44601 for more information.
            conf["global"]["engine.timeout_monitor.on"] = self.apiopts.get(
                "expire_responses", True
            )

        if cpstats and self.apiopts.get("collect_stats", False):
            conf["/"]["tools.cpstats.on"] = True

        if "favicon" in self.apiopts:
            conf["/favicon.ico"] = {
                "tools.staticfile.on": True,
                "tools.staticfile.filename": self.apiopts["favicon"],
            }

        if self.apiopts.get("debug", False) is False:
            conf["global"]["environment"] = "production"

        # Serve static media if the directory has been set in the configuration
        if "static" in self.apiopts:
            conf[self.apiopts.get("static_path", "/static")] = {
                "tools.staticdir.on": True,
                "tools.staticdir.dir": self.apiopts["static"],
            }

        # Add to global config
        cherrypy.config.update(conf["global"])

        return conf

'''.lstrip(
    "\n"
)

# Re-indent the whole replacement to match original method indentation
indented_new_fn = "".join(
    (leading_ws + ln if ln.strip() else ln) for ln in new_fn.splitlines(keepends=True)
)

# Splice and write back
new_src = "".join(lines[:start]) + indented_new_fn + "".join(lines[end:])
app_path.write_text(new_src, encoding="utf-8")

print(
    f"Patched {app_path} (lines {start+1}-{end}) with indent of length {len(leading_ws)}"
)
