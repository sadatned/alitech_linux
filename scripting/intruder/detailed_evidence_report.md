# The intrusion detection shell script to produce **a detailed evidence report** with the following columns:

* **Sr** → Serial number of entry
* **User Attempts** → Username(s) tried
* **IP address** → Source IP
* **Host Mapping** → Reverse DNS lookup of IP
* **Time Range** → First and last attempt timestamps

Here’s a script:

```bash
#!/bin/bash
# intrusion_report.sh
# Detect intrusion attempts across multiple Linux distros and print evidence

LOGFILE=""

# Detect Linux distro & select correct log file
if [ -f /etc/debian_version ]; then
    LOGFILE="/var/log/auth.log"
elif [ -f /etc/redhat-release ]; then
    LOGFILE="/var/log/secure"
else
    echo "Unsupported Linux distribution"
    exit 1
fi

if [ ! -f "$LOGFILE" ]; then
    echo "Log file not found: $LOGFILE"
    exit 1
fi

echo "Analyzing intrusion attempts from: $LOGFILE"
echo

# Header
printf "%-4s %-15s %-20s %-30s %-40s\n" "Sr" "User Attempts" "IP Address" "Host Mapping" "Time Range"
echo "------------------------------------------------------------------------------------------------------------------------------------------"

# Extract failed login attempts and group them
grep "Failed password" "$LOGFILE" | awk '{print $(NF-5), $(NF-3), $(NF-2), $1, $2, $3}' | sort | \
awk '
{
    user=$1
    ip=$2
    host=$3
    date=$4" "$5" "$6

    key=user"|"ip"|"host

    if (!(key in first_seen)) {
        first_seen[key]=date
    }
    last_seen[key]=date
    attempts[key]++
}
END {
    i=1
    for (key in attempts) {
        split(key, parts, "|")
        user=parts[1]
        ip=parts[2]
        host=parts[3]

        # reverse DNS lookup
        cmd="getent hosts " ip " | awk \"{print \\$2}\""
        cmd | getline resolved
        close(cmd)
        if (resolved == "") resolved = "N/A"

        time_range=first_seen[key]" -> "last_seen[key]
        printf "%-4d %-15s %-20s %-30s %-40s\n", i, user"("attempts[key]")", ip, resolved, time_range
        i++
    }
}' | sort -k1n
```

---

### 🔍 How It Works

1. **Detects Linux distro** → Chooses `/var/log/auth.log` (Debian/Ubuntu) or `/var/log/secure` (RHEL/CentOS).
2. **Parses failed login attempts** → Extracts username, IP, host (if available), and timestamp.
3. **Groups attempts** → Collects first & last seen times, counts attempts.
4. **Reverse DNS lookup** → Maps IP → hostname (using `getent hosts`).
5. **Prints evidence table** → With Sr, User Attempts, IP, Host Mapping, and Time Range.

---

✅ Example Output:

```
Sr   User Attempts   IP Address          Host Mapping                 Time Range
1    root(5)         192.168.1.100       attacker.example.com         Jan 20 02:15:01 -> Jan 20 02:30:12
2    admin(3)        10.0.0.45           N/A                          Jan 21 14:05:33 -> Jan 21 14:07:41
```

---
