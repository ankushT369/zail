# zail

**zail is a high-performance telemetry agent built in Zig.**
It watches directories recursively, tracks file mutations in real time, and streams out newly written log data with minimal overhead.
Designed for modern Linux systems and built on inotify + epoll for efficient event-driven processing.



## Features

* **Recursive directory watching**
  Automatically monitors a root directory and all subdirectories. Newly created directories are added on-the-fly.

* **High-performance event loop**
  Uses `epoll` to efficiently handle file system events at scale.

* **Append-only file tracking**
  Reads only newly appended data from files (similar to `tail -F`, but more robust).

* **Stable file identity**
  Tracks files using `(dev_id, inode)` so renames, symlinks, and moves do not break monitoring.

* **Zero polling**
  Pure event-driven architecture using Linux kernel primitives.

* **Allocator-aware memory handling**
  Explicit ownership and deterministic cleanup using Zig’s allocator model.



## How It Works

### 1. Directory Watcher (`Watcher`)

The watcher sets up an inotify instance, recursively walks the directory tree, and installs watches on every directory.
Each watch descriptor is mapped to its full directory path.

### 2. Event Loop (Epoll)

`epoll_wait` blocks until the inotify file descriptor has events ready.
This avoids busy-waiting or repeated scanning.

### 3. File Tracker (`FileTracker`)

When zail detects that a file has changed, it tracks the file by its `(inode, dev_id)` pair.
A `FilePos` structure remembers:

* last read offset
* current file size
* device ID
* inode
* file path
* open file handle

This ensures zail reads only **new content** without re-reading old data.

### 4. Data Extraction

Whenever a file grows, zail reads only the new bytes and passes them to the output pipeline (currently debug print; future: sinks).


## Requirements

* Linux system with inotify (available on all modern distros)
* Zig **0.15.1**
* `glibc` development headers (for `sys/stat.h`)


## Build and Run

```sh
zig build
./zig-out/bin/zail
```

Your configuration constants (directory to watch, masks, buffer sizes) are defined inside `constants.zig`.


## Code Structure

```
zail/
├── src/
│   ├── main.zig           # entrypoint, epoll loop
│   ├── watch.zig          # inotify watcher (recursive)
│   ├── filetracker.zig    # per-file offset tracking
│   ├── constants.zig      # configurable constants
└── build.zig
```


## Current Output

Right now, zail prints newly appended file content:

```
val: <new bytes here>
```

This is a placeholder stage for future sinks.


## Planned Features

* Log rotation handling (`mv file file.1 && touch file`)
* Multiple output sinks:

  * stdout
  * file
  * TCP/UDP
  * HTTP/JSON
  * Kafka, NATS, or Redis streams
* Structured parsing (JSON logs, CRI, journald-like)
* Backpressure-aware pipelines
* Compression-aware tailing (gz, zstd)
* Async worker pool for processing events

## Why Zig?

* Manual memory control without C fragility
* Zero hidden allocations
* Native access to Linux syscalls
* Fast, predictable performance
* Build system and cross-compilation baked-in

zail aims to be a simple, reliable, low-CPU telemetry agent — Zig fits that perfectly.

## License

MIT License.


## Contributing

Contributions, suggestions, and issues are welcome.
Reach out or open a PR.


If you want:

* badges (build, version, license)
* examples / screenshots
* architecture diagrams
* ASCII flowcharts
* or a shorter README variant

Just tell me — I can extend or tailor this exactly how you want.
