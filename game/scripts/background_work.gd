class_name BackgroundWork
extends RefCounted
## Physics work run on a worker thread where the game has threads: the
## strike's flight and roll, a computer golfer's plan and the caddie's read.
## Each is a whole flight and roll or dozens of them (15 to 60 ms apiece),
## which stalled frames when run on the main thread.
##
## The physics is safe to run on several threads at once as long as each
## job has its own ShotModel (ShotModel.fresh): its tables are static vars,
## not consts (Godot 4.4 shares one scratch value between threads when a
## const array or dictionary is indexed, which crashed the game on
## 2026-11-17), and LinksGround guards its one cache with a mutex.
## tests/run_tests.gd plays the same shots on threads and on the main
## thread and checks they end in the same place.
##
## The Web build has no threads, so there it all runs on the main thread,
## stepped a few milliseconds a frame as before.

## Off makes every job run on the main thread (the tests switch it).
static var enabled := true

## task id -> [the Callable, its object]: a Callable doesn't keep its
## object alive, and a planner nobody waits for any more must live until
## its thread is done.
static var _tasks := {}


static func available() -> bool:
	return enabled and OS.has_feature("threads") and not OS.has_feature("web") and OS.get_processor_count() >= 2


## Starts `work` on a worker thread; returns its id for done() and wait().
static func start(work: Callable, label: String) -> int:
	_reap()
	var id := WorkerThreadPool.add_task(work, false, label)
	_tasks[id] = [work, work.get_object()]
	return id


## True once job `id` has ended (and is collected). -1 counts as done.
static func done(id: int) -> bool:
	if id < 0 or not _tasks.has(id):
		return true
	if not WorkerThreadPool.is_task_completed(id):
		return false
	wait(id)
	return true


## Waits for job `id` to end.
static func wait(id: int) -> void:
	if id < 0 or not _tasks.has(id):
		return
	WorkerThreadPool.wait_for_task_completion(id)
	_tasks.erase(id)


## Collects jobs that have ended, including ones nobody waits for any more.
static func _reap() -> void:
	for id: int in _tasks.keys():
		if WorkerThreadPool.is_task_completed(id):
			wait(id)


## Waits for every job still running. Called when the round leaves the
## tree and before the tests quit: a task nobody waits for keeps Godot
## from exiting.
static func wait_all() -> void:
	for id: int in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


static func running() -> int:
	return _tasks.size()
