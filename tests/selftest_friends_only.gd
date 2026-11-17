extends SceneTree
## Corre solo la parte de la autoprueba sobre juntar, mochila y amistad:
##   godot --headless --path <proyecto> --script res://tests/selftest_friends_only.gd

const FriendTests := preload("res://tests/selftest_friends.gd")


func _initialize() -> void:
	var tests := FriendTests.new()
	tests.run(self)
	print("")
	if tests.failures == 0:
		print("AMISTAD OK: %d comprobaciones." % tests.checks)
	else:
		print("AMISTAD FALLIDA: %d de %d comprobaciones fallaron." % [tests.failures, tests.checks])
	quit(0 if tests.failures == 0 else 1)
