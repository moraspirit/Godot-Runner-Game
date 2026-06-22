extends Node

## Compares client SIM_VERSION with server /v1/meta before play.

signal version_ok
signal update_required(message: String)

var _pending: bool = false


func check() -> void:
	if SimConstants.API_BASE.is_empty():
		version_ok.emit()
		return
	if _pending:
		return
	_pending = true
	if not ApiClient.request_finished.is_connected(_on_api_response):
		ApiClient.request_finished.connect(_on_api_response)
	ApiClient.get_json("/v1/meta")


func _on_api_response(path: String, success: bool, _status: int, body: Dictionary) -> void:
	if path != "/v1/meta":
		return
	_pending = false
	if not success:
		version_ok.emit()
		return
	var min_v := int(body.get("min_sim_version", body.get("sim_version", 0)))
	if min_v > 0 and SimConstants.SIM_VERSION < min_v:
		update_required.emit(
			"This game was updated.\n\nPlease refresh the page to load the new version."
		)
		return
	version_ok.emit()
