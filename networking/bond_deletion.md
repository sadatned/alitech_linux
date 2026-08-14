# Delete bond0 on RHEL 8.10 using nmcli

## 1. Identify the bond connection

```bash
nmcli con show
```

Example:

```text
NAME     UUID                                  TYPE      DEVICE
bond0    xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  bond      bond0
ens1f0   xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  ethernet  ens1f0
ens1f1   xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  ethernet  ens1f1
```

---

## 2. Bring down the bond interface

```bash
nmcli con down bond0
```

---

## 3. Delete the bond connection

```bash
nmcli con delete bond0
```

---

## 4. Delete bond slave connections (if present)

List bond slave connections:

```bash
nmcli con show | grep bond-slave
```

Delete the slave profiles:

```bash
nmcli con delete ens1f0
nmcli con delete ens1f1
```

> Replace `ens1f0` and `ens1f1` with the actual slave connection names from your system.

---

## 5. Verify bond removal

```bash
nmcli con show
ip link show bond0
cat /proc/net/bonding/bond0
```

Expected results:

- `bond0` is no longer listed in `nmcli con show`
- `ip link show bond0` returns `Device not found`
- `/proc/net/bonding/bond0` no longer exists

---

## 6. If bond0 still exists in the kernel

Delete the bond device manually:

```bash
ip link set bond0 down
ip link delete bond0
```

Or remove it from the bonding driver:

```bash
echo "-bond0" > /sys/class/net/bonding_masters
```

---

## Quick One-Liner

```bash
nmcli con down bond0 && nmcli con delete bond0
```

---

## Useful Troubleshooting Commands

```bash
nmcli con show
nmcli device status
cat /proc/net/bonding/bond0
ip addr show bond0
```
