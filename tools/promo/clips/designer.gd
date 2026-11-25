extends RefCounted
## The course designer as it opens, for the README tile. Run with
## scene=res://scenes/course_designer.tscn. Args: frames.


func run(c, _node: Node) -> void:
	await c.frames(int(c.arg("wait", "60")))
	await c.take()
	await c.frames(int(c.arg("frames", "3")))
