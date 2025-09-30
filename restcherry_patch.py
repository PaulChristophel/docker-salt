# restcherry_patch.py — replace ApiApplication.get_conf to merge user CP config
import io, re, inspect
import salt.netapi.rest_cherrypy.app as appmod

app_path = inspect.getfile(appmod)
src = io.open(app_path, "r", encoding="utf-8").read()

# idempotent
if "BEGIN: user-configurable CherryPy merges" in src:
    print("Already patched:", app_path)
    raise SystemExit(0)

new_fn = r'''
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
    user_global = self.apiopts.get("global", {})
    if isinstance(user_global, dict):
        conf["global"].update(user_global)

    user_root = self.apiopts.get("root", {})
    if isinstance(user_root, dict):
        conf["/"].update(user_root)

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

# replace the existing get_conf(...) block
pattern = re.compile(r'\ndef\s+get_conf\s*\(\s*self\s*\)\s*:\s*.*?\n\s*return\s+conf\s*\n', re.DOTALL)
new_src, n = pattern.subn("\n"+new_fn+"\n", src)
if n != 1:
    raise SystemExit(f"get_conf() replacement failed; matched {n} blocks in {app_path}")
io.open(app_path, "w", encoding="utf-8").write(new_src)
print("Patched:", app_path)
