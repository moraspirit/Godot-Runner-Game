extends Node

## Web localStorage + fullscreen helpers. Safe no-ops on desktop/native.


func storage_set(key: String, value: String) -> void:
	if OS.has_feature("web"):
		var escaped_key := _js_string(key)
		var escaped_val := _js_string(value)
		JavaScriptBridge.eval("localStorage.setItem(%s, %s)" % [escaped_key, escaped_val], true)
		return
	var cfg := ConfigFile.new()
	var path := "user://browser_storage.cfg"
	if cfg.load(path) != OK:
		pass
	cfg.set_value("storage", key, value)
	cfg.save(path)


func storage_get(key: String) -> String:
	if OS.has_feature("web"):
		var escaped_key := _js_string(key)
		var result = JavaScriptBridge.eval("localStorage.getItem(%s)" % escaped_key, true)
		if result == null:
			return ""
		return str(result)
	var cfg := ConfigFile.new()
	var path := "user://browser_storage.cfg"
	if cfg.load(path) != OK:
		return ""
	return str(cfg.get_value("storage", key, ""))


func storage_remove(key: String) -> void:
	if OS.has_feature("web"):
		var escaped_key := _js_string(key)
		JavaScriptBridge.eval("localStorage.removeItem(%s)" % escaped_key, true)
		return
	var cfg := ConfigFile.new()
	var path := "user://browser_storage.cfg"
	if cfg.load(path) != OK:
		return
	cfg.set_value("storage", key, null)
	cfg.save(path)


func request_fullscreen() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
(function () {
  var el = document.getElementById('canvas') || document.documentElement;
  var req = el.requestFullscreen || el.webkitRequestFullscreen || el.webkitEnterFullscreen || el.mozRequestFullScreen || el.msRequestFullscreen;
  if (req) {
    try { req.call(el); } catch (e) {}
  }
})();
""", true)
	elif OS.get_name() in ["Windows", "macOS", "Linux", "Android", "iOS"]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func is_mobile_viewport() -> bool:
	var os := OS.get_name()
	if os == "Android" or os == "iOS":
		return true
	if OS.has_feature("web"):
		var w: int = int(get_viewport().get_visible_rect().size.x)
		return w < 900
	return false


func _js_string(s: String) -> String:
	return JSON.stringify(s)
