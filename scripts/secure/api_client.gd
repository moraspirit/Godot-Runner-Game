extends Node

signal request_finished(path: String, success: bool, status: int, body: Dictionary)

var _http: HTTPRequest
var _pending: Dictionary = {}


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func post_signed(path: String, body_dict: Dictionary) -> void:
	if not RunSession.has_session():
		request_finished.emit(path, false, 0, {"error": "no_session"})
		return

	var body := JSON.stringify(body_dict)
	var ts := str(int(Time.get_unix_time_from_system() * 1000.0))
	var nonce := _uuid()
	var sig := HmacSign.sign(RunSession.signing_secret, "POST", path, ts, nonce, body)
	var url := _full_url(path)
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"X-Session-Id: " + RunSession.session_id,
		"X-Timestamp: " + ts,
		"X-Nonce: " + nonce,
		"X-Signature: " + sig,
	]
	_pending[path] = true
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_pending.erase(path)
		request_finished.emit(path, false, 0, {"error": "request_failed", "code": err})


func get_json(path: String) -> void:
	var url := _full_url(path)
	_pending[path] = true
	var err := _http.request(url)
	if err != OK:
		_pending.erase(path)
		request_finished.emit(path, false, 0, {"error": "request_failed", "code": err})


func _full_url(path: String) -> String:
	var base := SimConstants.API_BASE.rstrip("/")
	if path.begins_with("/"):
		return base + path
	return base + "/" + path


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
	var path := _take_pending_path()
	var parsed: Dictionary = {}
	if body_bytes.size() > 0:
		var txt := body_bytes.get_string_from_utf8()
		var json := JSON.new()
		if json.parse(txt) == OK and json.data is Dictionary:
			parsed = json.data
		else:
			parsed = {"raw": txt}

	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	request_finished.emit(path, ok, code, parsed)


func _take_pending_path() -> String:
	if _pending.is_empty():
		return ""
	var key: String = _pending.keys()[0]
	_pending.erase(key)
	return key


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
