extends SceneTree


func _init() -> void:
	_verify.call_deferred()


func _verify() -> void:
	if not SentrySDK.is_enabled():
		push_error("FAIL: Sentry SDK did not initialize")
		quit(1)
		return

	var breadcrumb := SentryBreadcrumb.create("Just about to welcome the World.")
	breadcrumb.category = "integration.smoke_test"
	SentrySDK.add_breadcrumb(breadcrumb)
	var event_id: String = SentrySDK.capture_message("Hello, World!")
	if event_id.is_empty():
		push_error("FAIL: Sentry returned an empty event ID")
		quit(1)
		return

	print("PASS: Sentry captured Hello, World! with event ID ", event_id)
	quit(0)
