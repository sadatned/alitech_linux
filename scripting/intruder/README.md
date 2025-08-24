

1. Parse **failed login attempts** from `/var/log/auth.log` (Ubuntu/Debian) or `/var/log/secure` (RHEL/Fedora).
2. Extract:

   * **Username** attempted
   * **IP address** of attacker
   * **Number of attempts**
   * **Time range** (first → last attempt)
   * **Host mapping** (`nslookup` or `host`) for IP → hostname (if resolvable).
3. Print in a **table-like format**.

---

## 🔹 Example Output

```
===================================================
 Intruder Detection Summary - Sun Aug 24 21:00:00 IST 2025
 Source Log File: /var/log/auth.log
===================================================

Sr | User | Attempts | IP Address | Host Mapping | Time Range
-----------------------------------------------------------------------------------
1 | root   | 15 | 203.0.113.55 | example.attacker.net | Aug 24 18:55:12 → Aug 24 19:05:34
2 | admin  | 7  | 203.0.113.55 | example.attacker.net | Aug 24 18:56:01 → Aug 24 19:04:28
3 | test   | 3  | 198.51.100.10 | N/A | Aug 24 20:01:22 → Aug 24 20:02:17
```

---

## 🔹 How to Use

1. Save as `intruder_report.sh`.
2. Make executable:

   ```bash
   chmod +x intruder_report.sh
   ```
3. Run with root:

   ```bash
   sudo ./intruder_report.sh
   ```
4. Check report:

   ```bash
   less /var/log/intruder_summary.log
   ```

---
