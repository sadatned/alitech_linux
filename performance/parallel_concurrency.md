# Around **your Podman containers on a 2-socket CPU machine** and keep the theory tied to reality.
---
## 1. Quick mental model

* **Serialization**
  Only **one thing runs at a time** in a given pipeline. Everyone else waits in line.
* **Concurrency**
  **Many things are *in progress*** at the same time, but not necessarily running *at the exact same CPU cycle*. The OS can time-slice: run task A for a bit, pause it, run task B for a bit, etc.
* **Parallelism**
  **Many things are literally running at the same instant**, e.g. container A on core 0 and container B on core 1.
Think of:
* Serialization: *1 cashier, 1 customer being served.*
* Concurrency: *1 cashier switching between customers every few seconds.*
* Parallelism: *2 cashiers serving 2 customers at the same time.*
---
## 2. How this maps to Podman on Linux
Remember: **Podman just starts containers; the Linux kernel actually schedules the processes on CPUs.**
### Serialization with Podman
Things are effectively **serialized** when:
1. You only have **one runnable thread**:

   * A single-threaded process inside a container.
   * Or work in your app forced into *one* worker (e.g. a global lock, single queue consumer).
2. You **limit CPUs so far** that only one logical CPU can run it:
   * `podman run --cpuset-cpus=0 ...` (bind container to just 1 CPU).
   * `podman run --cpus=1 ...` or a strong CPU quota that makes it behave like 1 CPU.
3. You serialize at a higher level:
   * A job scheduler / script that runs containers **one after another** instead of together.
   * A DB lock or file lock that forces only one request to make progress at a time, even though you have many containers.
**Result**: Even on a 2-socket, 64-core beast, you’re essentially using it like a **single-core** box for that workload.
---
### Concurrency with Podman
You get **concurrency** when:
* You run **multiple containers at once**, but:

  * some are sleeping / waiting on I/O (disk, network, locks), or
  * the number of runnable threads > number of cores, so the OS time-slices.

Example:

* 20 podman containers doing REST calls + DB I/O.
* Box has 2 sockets × 16 cores = 32 cores.
* Often, only 3–5 containers are actively on CPU; others are blocked on network/disk.

Here, you have **concurrent** workloads: lots of tasks “in flight”, but only a subset actually using CPU in any given microsecond. Linux scheduler:

* Chooses which runnable threads from all containers get CPU time.
* Time-slices if runnable threads > cores.

---

### Parallelism with Podman
You get **parallelism** when **multiple container processes are actively on different cores at the same time**.
On a 2-socket machine:

* Suppose:
  * Socket 0 = cores 0–15
  * Socket 1 = cores 16–31
* You run:

```bash
podman run --cpuset-cpus=0-7   ... containerA
podman run --cpuset-cpus=16-23 ... containerB
```

If both containers are CPU-bound, you now have **true parallelism**: 8 cores on socket 0 + 8 cores on socket 1 doing useful work **at the same instant**.

Without any CPU pinning, Linux will still try to use **all cores** for runnable threads. The difference is just how “spread” the tasks are across sockets/NUMA nodes.

---

## 3. What the 2-socket CPU really changes

Two sockets typically means:
* **More physical cores** → more potential parallelism.
* **NUMA (Non-Uniform Memory Access)**:
  * Each socket has its own local memory.
  * Accessing remote socket memory is slower.

In Podman terms:

* If you don’t set `--cpuset-cpus` / `--cpus`, the kernel will:
  * Spread runnable threads across all cores in both sockets.
  * Handle concurrency and parallelism for you.

* If you care about NUMA locality or tuning:
  * You might pin a container to one socket:

    ```bash
    podman run --cpuset-cpus=0-15 ...
    ```
  * Or run your app with `numactl` **inside** the container to prefer local memory.

The **key point**:
A 2-socket CPU gives you the *capacity* for more **parallelism**; it doesn’t guarantee it. You still need:

* App with multiple runnable threads or multiple containers
* No artificial serialization (locks, single worker, single CPU pinning)
* Correct CPU/NUMA tuning if you’re really pushing performance

---

## 4. Concrete scenarios (Podman angle)

### Scenario A – Serialized workload on a big box
* Single Podman container
* Single-threaded app, I/O-light, pure CPU
* `podman run --cpuset-cpus=0 ...`

Even on 2 sockets with 32 cores, your max CPU usage is ~100% of **one core** (~3% of the box).
**Serialized**, not concurrent, not parallel.
---
### Scenario B – Concurrent but not really parallel (CPU-bound oversubscription)

* 1 socket equivalent: 8 cores
* 20 CPU-bound containers, each with 1 busy thread
* All containers share all cores (no pinning)

You have:
* **Concurrency**: 20 tasks “in progress”.
* **Parallelism**: At most 8 at the same time (limited by cores).
* The others are just time-sliced: each container gets bursts of CPU.

From `top`/`podman stats`, you see CPU near 800% (8 cores) but not 2000% (20 cores).
---

### Scenario C – Real parallelism across sockets

* Box: 2 sockets × 16 cores = 32 cores
* 4 CPU-bound containers:
  * `containerA` → `--cpuset-cpus=0-7`
  * `containerB` → `--cpuset-cpus=8-15`
  * `containerC` → `--cpuset-cpus=16-23`
  * `containerD` → `--cpuset-cpus=24-31`

All 4 containers are busy, all cores are active.
You have **concurrency** (4 workloads in progress) and **parallelism** (32 logical CPUs doing work simultaneously).

---

## 5. How to *think* about your setup

When you look at Podman on your 2-socket host, ask:

1. **At the application level**

   * Are requests / jobs processed in parallel or forced through a single serialized path (lock, queue, single worker)?

2. **At the container level**

   * How many containers are running at once?
   * Are they mostly CPU-bound or I/O-bound?
   * Are you restricting CPUs with `--cpuset-cpus` or `--cpus`?

3. **At the host/CPU level**

   * How many cores per socket?
   * Do you care about NUMA locality or just raw throughput?
   * Is CPU saturation due to true parallelism or just oversubscribed concurrency?

---
Next we can take **your actual podman stats/top output** and I can:

* Mark where you’re seeing serialization,
* Where you have concurrency but no useful parallelism,
* And suggest concrete `podman run` / cgroup / NUMA tuning changes for your 2-socket machine.
