# Theory into something you can *see* and *tune* on your Podman + 2-socket box.

I’ll break it into:

1. **How to detect serialization**
2. **How to detect “concurrency but no useful parallelism”**
3. **Concrete Podman / cgroup / NUMA tuning patterns for a 2-socket host**

---
## 1. How to *see* serialization

**Serialization = only one execution path is actually doing useful work at a time**, even if you have many containers/threads.

### 1.1. Check per-container threads
Pick a container you suspect is serialized:

```bash
ctr=myctr   # replace with your container name or ID
podman top "$ctr" pid,pcpu,comm
```

* If you only ever see **one PID with high %CPU** and others near 0 → strong hint of serialization.
Get the container’s main PID on the host:

```bash
ctr_pid=$(podman inspect -f '{{.State.Pid}}' "$ctr")
top -H -p "$ctr_pid"
```

Look for:
* One thread at ~90–100% CPU
* All other threads mostly idle

➡️ That’s a serialized CPU path (single worker, global lock, or single-threaded design).

---
### 1.2. Compare to total cores

Check CPU layout:

```bash
lscpu | egrep 'Socket|Core|CPU\(s\)|NUMA node'
```

If you see something like:

* 2 sockets
* 16 cores per socket
* 64 “CPU(s)” (with HT)

Now check overall usage:

```bash
mpstat -P ALL 1 5
```

Signs of serialization:

* One or two **logical CPUs near 100%**, others very low.
* Overall utilization maybe 5–10%, even though your **load feels high**.

That means **one threaded path is your bottleneck**.

---

### 1.3. Check for lock / I/O based serialization

Sometimes you *have* many threads, but only one can pass through a lock or shared resource.

Use `pidstat` on the container PID:

```bash
pidstat -t -p "$ctr_pid" 1
```

Look for:

* Many threads in state **D** (uninterruptible I/O) or **S** (sleeping)
* Only one thread with significant `%CPU`

That’s often:

* Single DB connection or serialized transaction path
* Global mutex
* Single file or device that only one thread uses at a time

**Action once you see this** (high level):

* Scale **inside** the app (more workers, more DB connections, sharding)
* Or scale **horizontally**: multiple containers, each with its own independent backend resource

---

## 2. Concurrency but no useful parallelism

Here we have **many things in progress**, but hardware usage isn’t improving or is even getting worse.

### 2.1. Many containers, low core utilization

Run:

```bash
podman stats --no-stream
mpstat -P ALL 1 5
```

If you see:

* `podman stats`: 10–20 containers showing some CPU %
* `mpstat`: no core really close to 100%, most are lightly loaded
* But system feels slow → likely **I/O or external bottleneck**.

Check I/O:

```bash
iostat -xz 1 5
vmstat 1 5
```

Tell-tale signs:

* `iostat`: single disk or LUN with very high **util% (near 100)** and high await
* `vmstat`: high `%wa` (I/O wait)

That means:

* The containers are *concurrent* (lots “running”),
* But not **parallel** on CPU because they’re all queueing on the same disk / network / DB.

More containers here just gives you:

* More context switches
* Longer queues
* No real throughput gain

---

### 2.2. CPU oversubscription without benefit

If you run many CPU-hungry containers:

```bash
podman stats --no-stream
mpstat -P ALL 1 5
pidstat -w 1 5
```

Patterns of “bad concurrency”:

* Overall CPU usage ~70–80%, but:

  * `pidstat -w` shows **very high context switch rate (cswch/s)**.
  * Latency for each container is bad, even though you still have some headroom.

What’s happening:

* Too many runnable threads per core
* Scheduler thrashes between them
* You pay context switch overhead instead of getting proportional throughput

**Rule of thumb**:

* For pure CPU-bound work, try to keep runnable threads **≈ number of cores**, not 3–5×.

---
## 3. Concrete tuning patterns (Podman / cgroup / NUMA on 2-socket host)

Assume something like:

* 2 sockets
* 16 cores per socket
* 64 logical CPUs total

You can refine with:

```bash
lscpu
numactl --hardware
```

### 3.1. Basic knobs you’ll use
* `--cpuset-cpus=LIST`
  Which cores a container *may* run on.
* `--cpuset-mems=LIST`
  Which NUMA nodes its memory can come from.
* `--cpus=N`
  CPU *quota* (roughly how many cores worth of time it can consume).
* `--cpu-shares`, `--cpus`
  Relative priority / quota under contention.

---
### 3.2. Pattern 1: Avoid accidental serialization by CPU pinning

If you see a heavy container stuck at 100% on a single CPU, and you **want it to scale**:

Instead of:

```bash
podman run --cpuset-cpus=0 ...
```

Try:

```bash
# Let it use 8 cores on socket 0, and memory from NUMA node 0
podman run \
  --cpuset-cpus=0-7 \
  --cpuset-mems=0 \
  --cpus=8 \
  ...
```

This gives:

* Room for parallelism inside the container (if app supports it)
* NUMA locality (CPU + memory on same socket)

You’re saying: “I want up to 8 cores of real CPU time for this container, all on node 0.”

---

### 3.3. Pattern 2: Split heavy containers across sockets

Two big CPU-bound services?

```bash
# Service A → socket 0
podman run \
  --cpuset-cpus=0-15 \
  --cpuset-mems=0 \
  --cpus=16 \
  ... serviceA ...

# Service B → socket 1
podman run \
  --cpuset-cpus=16-31 \
  --cpuset-mems=1 \
  --cpus=16 \
  ... serviceB ...
```

Benefits:

* True **parallelism across sockets**
* Better cache and memory locality
* Less cross-socket traffic

---

### 3.4. Pattern 3: Many I/O-bound containers – control concurrency

If investigation shows:

* I/O device or DB is the bottleneck
* CPU is *fine*, but latency is bad

Then you want **fewer active writers/readers at once**, not more.

Examples:

1. Limit concurrency via job scheduling:

   * Only run N backup/ingest containers at once.
2. Soft-limit CPU so they don’t all go crazy when I/O does become available:

```bash
# Each container is I/O-heavy, but we cap CPU to reduce thrash
podman run \
  --cpuset-cpus=0-31 \
  --cpus=0.5 \
  --cpu-shares=256 \
  ...
```

* `--cpus=0.5` stops any single I/O-heavy container from monopolizing CPU when bursts happen.
* Keep `cpuset-cpus` broad so any free core can run it.

---

### 3.5. Pattern 4: Pack “noisy” background work onto a subset of cores

For noisy batch/background tasks (e.g. compression, reporting) that disturb latency-sensitive workloads:

```bash
# Background batch containers on cores 0–15
podman run --cpuset-cpus=0-15 --cpus=8 ... batchjob1 ...
podman run --cpuset-cpus=0-15 --cpus=4 ... batchjob2 ...

# Critical latency-sensitive services on cores 16–31
podman run --cpuset-cpus=16-31 --cpuset-mems=1 --cpus=16 ... critical ...
```

* You’re **sacrificing** some global flexibility to guarantee performance for critical stuff.
* Still parallel, but now more *predictable*.

---
### 3.6. When you *must* accept serialization

If your analysis shows:

* Single DB that can’t handle more parallel transactions
* Single tape drive / physical appliance
* Licensing / external API rate limits

Then:
* Adding more containers / threads will only increase concurrency, not throughput.
* Your “tuning” is to **keep concurrency at the sweet spot** (enough to hide latency, not enough to overwhelm limiters).
---
## 4. How to use this practically

Next time you’re on the host:

1. Pick a busy container.
2. Run:
   * `podman top <ctr> pid,pcpu,comm`
   * `top -H -p $(podman inspect -f '{{.State.Pid}}' <ctr>)`
   * `mpstat -P ALL 1 5`
3. Ask:
   * Do I see **only one hot thread/core?** → serialization.
   * Do I see **many runnable containers but low per-core use + high %wa or disk util?** → concurrent but I/O-bound.
   * Do I see **all cores hot and context switches very high with no latency improvement?** → oversubscribed, wasted concurrency.
Then apply one of the patterns above:

* **Give more cores & NUMA locality to good parallel workloads.**
* **Limit or isolate noisy or I/O-bound workloads.**
* **Stop trying to parallelize a fundamentally serialized backend.**
---
If you paste a small snippet of `podman stats`, `mpstat -P ALL 1 5`, and `top -H` for one container sometime, 
I can mark each line with “this is serialization”, “this is just concurrency”, and “here is your real parallelism hotspot,” and propose exact `podman run` commands to match.
