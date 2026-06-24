extends Node

var sound_enabled: bool = true

const USER_ERROR_MSG := "Something went wrong. Try again."


func _ready() -> void:
	if OS.has_feature("web"):
		var saved := BrowserBridge.storage_get("sound_enabled")
		if saved != "":
			sound_enabled = saved == "1"
	apply_sound()


func apply_sound() -> void:
	AudioServer.set_bus_mute(0, not sound_enabled)


func toggle_sound() -> void:
	sound_enabled = not sound_enabled
	if OS.has_feature("web"):
		BrowserBridge.storage_set("sound_enabled", "1" if sound_enabled else "0")
		if sound_enabled:
			BrowserBridge.unlock_web_audio()
	apply_sound()
