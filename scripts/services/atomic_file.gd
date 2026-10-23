class_name AtomicFile
extends RefCounted
## Crash-safe small-file writes: temp file, then rename over the target.
##
## A process kill mid-write leaves either the old file or the new one, never a
## truncated file (settings files used to be written in place).


## Writes `text` to `path` atomically. Returns true on success.
static func write_text(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	var target := path.get_file()
	# Windows rename refuses an existing destination; remove it first.
	if dir.file_exists(target):
		dir.remove(target)
	return dir.rename(tmp.get_file(), target) == OK
