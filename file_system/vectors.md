# Vectors

- Many modern filesystems offer a wide range of operations that can be categorized into a few key **"vectors"** or **groups** of functionality.
- Although filesystems might implement hundreds of individual operations (especially in kernel-level implementations like Linux's VFS layer),
- these operations typically fall into **four main categories (vectors)**:

### 1. **File Operations**

These involve direct interactions with files — reading, writing, opening, closing, etc.

* `open()`
* `read()`
* `write()`
* `close()`
* `fsync()`
* `lseek()`
* `truncate()`

These operations deal with **file contents and file descriptors**.

---

### 2. **Directory Operations**

These are for managing directories and navigating the filesystem structure.

* `mkdir()`
* `rmdir()`
* `readdir()`
* `opendir()`
* `rename()`
* `unlink()` (for files, but affects the directory structure)
* `link()`
* `symlink()`

These help manage **namespaces** and the **hierarchical structure**.

---

### 3. **Inode / Metadata Operations**

These involve reading and updating metadata associated with files or directories.

* `stat()`
* `chmod()`
* `chown()`
* `utimensat()` (set file times)
* `getattr()`
* `setattr()`

These affect file **attributes**, such as permissions, timestamps, and ownership.

---

### 4. **Filesystem Control Operations**

These are more administrative or control-related operations.

* `mount()`
* `umount()`
* `sync()`
* `ioctl()` (general interface for device-specific or filesystem-specific control)
* `statfs()` (retrieve information about a filesystem)
* `quotactl()` (manage disk quotas)

This group is for **mount management**, **configuration**, and **system-level controls**.

---

### Summary Table

| Vector                   | Purpose                         | Examples                                 |
| ------------------------ | ------------------------------- | ---------------------------------------- |
| **File Operations**      | Handle file contents and access | `read()`, `write()`, `open()`, `close()` |
| **Directory Operations** | Manage namespaces and hierarchy | `mkdir()`, `rename()`, `readdir()`       |
| **Metadata Operations**  | Access/modify file metadata     | `stat()`, `chmod()`, `chown()`           |
| **Filesystem Control**   | System-level FS management      | `mount()`, `sync()`, `ioctl()`           |

---
## A breakdown based on Linux VFS, FUSE, or another platform?


Absolutely! Let's dive deeper into how operations are organized in the Linux VFS and in FUSE, both of which categorize filesystem operations into distinct “vectors.” These align with the four big buckets—operations on inodes, files, directories, and filesystem control—but each system defines them through its own callbacks and interfaces.

---

## Linux VFS (Virtual File System)

The Linux VFS splits operations across different structures depending on what layer is being interacted with:

### 1. **inode\_operations**

Handles operations on **objects themselves**—files, directories, links—affecting creation, deletion, metadata, etc. Examples include:

* `create`, `lookup`, `link`, `unlink`, `symlink`
* `mkdir`, `rmdir`, `mknod`, `rename`
* `permission`, `setattr`, `getattr`, `listxattr`
* `update_time`, `atomic_open`, `fileattr_get/set` ([Kernel Documentation][1])

### 2. **file\_operations**

Manages operations on **opened files**—what userspace programs do to files once they’re open:

* `lseek`, `read`, `write`, `read_iter`, `write_iter`
* `poll`, `ioctl`, `mmap`, `open`, `release`, `fsync`, `fasync`
* `splice_read/write`, `fallocate`, `copy_file_range`, `remap_file_range`, `fadvise` ([Kernel Documentation][1], [linux-kernel-labs.github.io][2])

### 3. **super\_operations** (Filesystem-level control)

Covers higher-level management of the filesystem as a whole:

* `sync_fs`, `freeze_fs`, `unfreeze_fs`, `statfs`, `remount_fs`
* `clear_inode`, `umount_begin`, `quota_read/write`, `nr_cached_objects`, `free_cache_objects`, `show_options` ([Kernel Documentation][3])

### 4. **Directory entry cache (dentry) operations**

These are lower-level, internal operations related to the directory cache:

* `d_hash`, `d_compare`, `d_delete`, `d_release`, `d_iput`, `d_automount`, `d_init`, `d_revalidate`, `d_weak_revalidate`, etc. ([Kernel Documentation][1])

---

## FUSE (Filesystem in Userspace)

In FUSE, operations are represented by message opcodes dispatched between the kernel and a user-space daemon. These similarly align with the four major vectors:

### 1. **Inode / Metadata & Namespace (lookup, getattr, setattr, etc.)**

Operations affecting metadata and lookup:

* `LOOKUP`, `GETATTR`, `SETATTR`, `READLINK`, `SYMLINK`, `CREATE` ([filesystems.org][4], [fsl.cs.stonybrook.edu][5])

### 2. **File Data Operations**

Operations related to file content and mode of access:

* `OPEN`, `READ`, `WRITE`, `RELEASE`, `FLUSH`, `FSYNC`, directory-specific ones like `OPENDIR`, `READDIR`, `RELEASEDIR`, `FSYNCDIR` ([fsl.cs.stonybrook.edu][5], [filesystems.org][4])

### 3. **Filesystem Control / Stat Operations**

Control-level and statistics-related ops:

* `STATFS`, `DESTROY`, `BMAP`, `IOCTL`, `POLL`, connection cleanup routines ([filesystems.org][4])

### 4. **Management & Protocol Control**

Handling the lifecycle of the FUSE connection itself:

* `INIT`, `FORGET`, `DESTROY`, `INTERRUPT`, filesystem control filesystem (`fusectl`) operations like abort, status queries, congestion management ([fsl.cs.stonybrook.edu][5], [Kernel.org][6], [Kernel Documentation][7])

---

### Comparison Table

| **Vector**             | **Linux VFS** (struct callbacks)                   | **FUSE** (Opcode / message types)                                   |
| ---------------------- | -------------------------------------------------- | ------------------------------------------------------------------- |
| **Inode/Metadata**     | `inode_operations`: lookup, setattr, getattr, etc. | `LOOKUP`, `GETATTR`, `SETATTR`, `CREATE`, `SYMLINK`, etc.           |
| **File Operations**    | `file_operations`: read, write, mmap, etc.         | `OPEN`, `READ`, `WRITE`, `RELEASE`, `FSYNC`, etc.                   |
| **Directory Entry**    | `dentry_operations`, managing entry cache          | FUSE-specific directory ops (`READDIR`, etc.) under namespace logic |
| **Filesystem Control** | `super_operations`, sync, statfs, mount/unmount    | `INIT`, `DESTROY`, `STATFS`, `IOCTL`, plus control via `fusectl`    |

---

Let me know if you'd like a breakdown of how this maps to a specific use case—like building a FUSE layer or implementing custom operations via Linux VFS—it’s a rich and fascinating system!

[1]: https://docs.kernel.org/filesystems/vfs.html?utm_source=chatgpt.com "Overview of the Linux Virtual File System — The Linux Kernel documentation"
[2]: https://linux-kernel-labs.github.io/refs/pull/289/merge/labs/filesystems_part1.html?utm_source=chatgpt.com "File system drivers (Part 1) — The Linux Kernel documentation"
[3]: https://docs.kernel.org/5.19/filesystems/vfs.html?utm_source=chatgpt.com "Overview of the Linux Virtual File System — The Linux Kernel documentation"
[4]: https://www.filesystems.org/docs/fuse/fuse-article-appendices.html?utm_source=chatgpt.com "FUSE Library Options and APIs"
[5]: https://www.fsl.cs.stonybrook.edu/docs/fuse/fuse-article-appendices.html?utm_source=chatgpt.com "FUSE Library Options and APIs"
[6]: https://www.kernel.org/doc/html/next/filesystems/fuse/fuse.html?utm_source=chatgpt.com "1. FUSE Overview — The Linux Kernel documentation"
[7]: https://docs.kernel.org/5.19/filesystems/fuse.html?utm_source=chatgpt.com "FUSE — The Linux Kernel documentation"
