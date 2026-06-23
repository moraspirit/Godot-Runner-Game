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


func unlock_web_audio() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("""
(function () {
  try {
    var ctx = window.__godot_audio_ctx;
    if (ctx && ctx.state === 'suspended') ctx.resume();
  } catch (e) {}
})();
""", true)


func focus_canvas() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("""
(function () {
  var c = document.getElementById('canvas');
  if (c && c.focus) c.focus();
})();
""", true)


func dismiss_virtual_keyboard() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("""
(function () {
  try {
    var ae = document.activeElement;
    if (ae && (ae.tagName === 'INPUT' || ae.tagName === 'TEXTAREA')) ae.blur();
    document.querySelectorAll('input, textarea').forEach(function (el) {
      if (el && el.style && el.style.position === 'fixed') el.blur();
    });
  } catch (e) {}
})();
""", true)


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


func popup_edge_margin() -> float:
	return 10.0 if is_mobile_viewport() else 18.0


func popup_vertical_margin() -> float:
	return 28.0 if is_mobile_viewport() else 40.0


## Wide popup: nearly full screen width, moderate height (not full screen).
func apply_wide_popup(panel: Control, height_ratio: float = 0.58) -> void:
	var edge := popup_edge_margin()
	var vp := get_viewport().get_visible_rect().size
	var min_h := 260.0 if is_mobile_viewport() else 300.0
	var ratio := clampf(height_ratio, 0.32, 0.78)
	var h := maxf(min_h, vp.y * ratio)
	var max_h := vp.y - popup_vertical_margin() * 2.0
	h = minf(h, max_h)

	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_left = edge
	panel.offset_right = -edge
	panel.offset_top = -h * 0.5
	panel.offset_bottom = h * 0.5


## Auth/login popup pinned to top — keeps buttons clear of the mobile virtual keyboard.
func apply_top_auth_popup(panel: Control) -> void:
	var edge := popup_edge_margin()
	var vp := get_viewport().get_visible_rect().size
	var top := popup_vertical_margin() * 0.35
	var h := vp.y * (0.52 if is_mobile_viewport() else 0.56)
	h = clampf(h, 300.0, vp.y - top - 80.0)
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_left = edge
	panel.offset_right = -edge
	panel.offset_top = top
	panel.offset_bottom = top + h


func popup_title_font() -> int:
	return 54 if is_mobile_viewport() else 58


func popup_body_font() -> int:
	return 34 if is_mobile_viewport() else 36


func popup_button_height() -> int:
	return 88 if is_mobile_viewport() else 92


func menu_title_font() -> int:
	return 76 if is_mobile_viewport() else 92


func menu_subtitle_font() -> int:
	return 42 if is_mobile_viewport() else 46


func menu_caption_font() -> int:
	return 28 if is_mobile_viewport() else 30


func menu_button_font() -> int:
	return 38 if is_mobile_viewport() else 42


func menu_button_height() -> int:
	return 88 if is_mobile_viewport() else 96


func hud_font() -> int:
	return 38 if is_mobile_viewport() else 40


func hud_hint_font() -> int:
	return 30 if is_mobile_viewport() else 32


func _js_string(s: String) -> String:
	return JSON.stringify(s)
