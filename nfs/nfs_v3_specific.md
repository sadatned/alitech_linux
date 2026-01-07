# Below is a **clear, NFS-v3–specific explanation** of what happens when you mount an NFSv3 share with:

```
nolock,noac,sync
```

and what the **real impact** is on both **client and server**.

---

# Background: NFSv3 Locking Model (Important)

NFSv3 **does not have built-in locking**.
File locking is provided by **NLM (Network Lock Manager)** via:

* `rpc.statd`
* `rpc.lockd`

The mount option **`nolock`** disables this entirely.

---

## What Each Option Controls (Independently)

### 1. `nolock`

* Disables **file locking**
* No advisory locks (`fcntl`, `flock`)
* No lock coordination between clients

### 2. `noac`

* Disables **attribute caching**
* Every `stat()`, `ls -l`, metadata check goes to server
* Does **NOT** affect data caching

### 3. `sync`

* Forces **synchronous writes**
* Write completes only after server commits data to stable storage

---

# Impact Analysis When Used Together

## 1. Data Consistency

### ✅ What you DO get

* Fresh metadata (due to `noac`)
* Safer writes (due to `sync`)
* No delayed writes
* Reduced risk of stale file size / timestamp

### ❌ What you do NOT get

* **No file locking**
* No protection against:

  * Concurrent writers
  * Partial overwrites
  * File corruption at application level

⚠️ **Key point**:
`noac` and `sync` **do NOT replace locking**.

---

## 2. Concurrency & Corruption Risk

With `nolock`:

* Multiple clients can write to the same file **simultaneously**
* Kernel does **not coordinate access**
* Applications that rely on locks will **silently fail**

### Example failure scenario

```
Client A writes to file
Client B writes to same file
No lock → interleaved writes → corrupted data
```

Even with:

```
noac,sync
```

**Corruption is still possible.**

---

## 3. Performance Impact

### Client-side impact

| Option   | Effect                         |
| -------- | ------------------------------ |
| `nolock` | Slightly faster (no lock RPCs) |
| `noac`   | Slower metadata operations     |
| `sync`   | Much slower writes             |

Result:

* Very slow for:

  * `cp`
  * `rsync`
  * builds
  * databases

---

### Server-side impact

* Increased RPC traffic
* Higher disk I/O pressure
* More `WRITE + COMMIT` operations
* Poor scalability with multiple clients

---

## 4. Behavior Summary Table

| Aspect              | Result                        |
| ------------------- | ----------------------------- |
| File locking        | ❌ Disabled                    |
| Metadata freshness  | ✅ Always fresh                |
| Write durability    | ✅ High                        |
| Multi-client safety | ❌ Unsafe                      |
| Performance         | ❌ Poor                        |
| Corruption risk     | ⚠️ High if concurrent writers |

---

## 5. When This Combination Makes Sense

### ✅ Acceptable use cases

* **Single NFS client only**
* Read-mostly workloads
* Log collection (append-only)
* Legacy apps that do not use locking
* Debugging / troubleshooting consistency issues

---

### ❌ Dangerous use cases

* Databases
* Mail servers
* Shared home directories
* Any application using:

  * `flock`
  * `fcntl`
  * file-based locks

---

## 6. Important Misconception (Very Common)

> **Myth**: `noac,sync` ensures safe concurrent access
> **Reality**: Only **locking** ensures coordination.

Without locking:

* Kernel cannot serialize access
* Application-level corruption is possible

---

## 7. Better Alternatives (If Locking Is Broken)

### Option 1: Fix locking (recommended)

Ensure:

```
rpc.statd
rpc.lockd
```

are running on **both client and server**

Mount without `nolock`.

---

### Option 2: If locking truly impossible

* Ensure **single-writer policy**
* Use **application-level locking**
* Consider:

```
actimeo=0
```

instead of `noac` (slightly better performance)

---

## Final Summary (Plain English)

> Mounting NFSv3 with `nolock,noac,sync` gives you **fresh metadata and safe writes**, but **zero protection against concurrent access**.
> It is **not safe for shared writable workloads**, and performance will be poor.


