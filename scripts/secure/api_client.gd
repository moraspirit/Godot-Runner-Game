extends Node

signal request_finished(path: String, success: bool, status: int, body: Dictionary)

var _http: HTTPRequest
var _queue: Array[Dictionary] = []
var _in_flight: Dictionary = {}


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func post_unsigned(path: String, body_dict: Dictionary = {}) -> void:
	post_with_headers(path, body_dict, PackedStringArray(["Content-Type: application/json"]))


func post_with_jwt(path: String, body_dict: Dictionary = {}) -> void:
	if not AuthSession.is_logged_in():
		request_finished.emit(path, false, 0, {"error": "not_logged_in"})
		return
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"Authorization: Bearer " + AuthSession.token,
	]
	post_with_headers(path, body_dict, headers)


func post_with_headers(path: String, body_dict: Dictionary, headers: PackedStringArray) -> void:
	var body := JSON.stringify(body_dict)
	_enqueue(path, HTTPClient.METHOD_POST, headers, body)


func post_signed(path: String, body_dict: Dictionary) -> void:
	if not RunSession.has_session():
		_log("POST %s blocked — no session yet" % path)
		request_finished.emit(path, false, 0, {"error": "no_session"})
		return

	var body := JSON.stringify(body_dict)
	var ts := str(int(Time.get_unix_time_from_system() * 1000.0))
	var nonce := _uuid()
	var sig := HmacSign.sign(RunSession.signing_secret, "POST", path, ts, nonce, body)
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"X-Session-Id: " + RunSession.session_id,
		"X-Timestamp: " + ts,
		"X-Nonce: " + nonce,
		"X-Signature: " + sig,
	]
	_enqueue(path, HTTPClient.METHOD_POST, headers, body)


func get_json(path: String) -> void:
	var headers: PackedStringArray = []
	if AuthSession.is_logged_in():
		headers.append("Authorization: Bearer " + AuthSession.token)
	_enqueue(path, HTTPClient.METHOD_GET, headers, "")


func _enqueue(path: String, method: int, headers: PackedStringArray, body: String) -> void:
	var url := _full_url(path)
	var method_name := "GET" if method == HTTPClient.METHOD_GET else "POST"
	_log("%s %s -> %s" % [method_name, path, url])
	_queue.append({
		"path": path,
		"url": url,
		"method": method,
		"headers": headers,
		"body": body,
	})
	_pump_queue()


func _pump_queue() -> void:
	if not _in_flight.is_empty() or _queue.is_empty():
		return

	_in_flight = _queue.pop_front()
	var err := _http.request(
		_in_flight["url"],
		_in_flight["headers"],
		_in_flight["method"],
		_in_flight["body"],
	)
	if err != OK:
		var path: String = _in_flight.get("path", "")
		_log("%s failed to start (err %d)" % [path, err])
		_in_flight = {}
		request_finished.emit(path, false, 0, {"error": "request_failed", "code": err})
		_pump_queue()


func _full_url(path: String) -> String:
	var base := SimConstants.API_BASE.rstrip("/")
	if path.begins_with("/"):
		return base + path
	return base + "/" + path


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
	var path: String = _in_flight.get("path", "")
	var parsed: Dictionary = {}
	var raw := ""
	if body_bytes.size() > 0:
		raw = body_bytes.get_string_from_utf8()
		var json := JSON.new()
		if json.parse(raw) == OK and json.data is Dictionary:
			parsed = json.data
		else:
			parsed = {"raw": raw}

	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	if SimConstants.DEBUG_API:
		if ok:
			_log("OK %s HTTP %d -> %s" % [path, code, _truncate(raw)])
		else:
			_log("FAIL %s result=%d HTTP %d -> %s" % [path, result, code, _truncate(raw)])

	_in_flight = {}
	request_finished.emit(path, ok, code, parsed)
	_pump_queue()


func _log(msg: String) -> void:
	if SimConstants.DEBUG_API:
		print("[ApiClient] ", msg)


func _truncate(s: String, max_len: int = 240) -> String:
	if s.length() <= max_len:
		return s
	return s.substr(0, max_len) + "…"


func _uuid() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "%08x-%04x-%04x-%04x-%012x" % [
		rng.randi(),
		rng.randi() & 0xFFFF,
		(rng.randi() & 0x0FFF) | 0x4000,
		(rng.randi() & 0x3FFF) | 0x8000,
		rng.randi() & 0xFFFFFFFFFFFF,
	]
