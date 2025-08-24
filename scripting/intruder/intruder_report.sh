## 🔹 Script: `intruder_report.sh`

```bash
#!/bin/bash
#
# intruder_report.sh
# Summarizes failed SSH login attempts with user, IP, time range, and hostname mapping

# --- Detect log file based on distro ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|debian)
            AUTH_LOG="/var/log/auth.log"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            AUTH_LOG="/var/log/secure"
            ;;
        *)
            AUTH_LOG="/var/log/auth.log"
            ;;
    esac
else
    AUTH_LOG="/var/log/auth.log"
fi

REPORT="/var/log/intruder_summary.log"
TMPFILE=$(mktemp)

echo "===================================================" > "$REPORT"
echo " Intruder Detection Summary - $(date)" >> "$REPORT"
echo " Source Log File: $AUTH_LOG" >> "$REPORT"
echo "===================================================" >> "$REPORT"
echo -e "\nSr | User | Attempts | IP Address | Host Mapping | Time Range" >> "$REPORT"
echo "-----------------------------------------------------------------------------------" >> "$REPORT"

# --- Extract failed attempts ---
grep "Failed password" "$AUTH_LOG" | awk '{print $1,$2,$3,$9,$11}' > "$TMPFILE"

# --- Group by User+IP ---
sr=1
for ip in $(awk '{print $5}' "$TMPFILE" | sort | uniq); do
    for user in $(awk -v ip="$ip" '$5==ip {print $4}' "$TMPFILE" | sort | uniq); do
        attempts=$(awk -v ip="$ip" -v user="$user" '$5==ip && $4==user {print}' "$TMPFILE" | wc -l)
        first_time=$(awk -v ip="$ip" -v user="$user" '$5==ip && $4==user {print $1" "$2" "$3}' "$TMPFILE" | head -1)
        last_time=$(awk -v ip="$ip" -v user="$user" '$5==ip && $4==user {print $1" "$2" "$3}' "$TMPFILE" | tail -1)
        host=$(getent hosts "$ip" | awk '{print $2}')
        if [ -z "$host" ]; then host="N/A"; fi
        echo "$sr | $user | $attempts | $ip | $host | $first_time → $last_time" >> "$REPORT"
        sr=$((sr+1))
    done
done

rm -f "$TMPFILE"

echo -e "\nSummary saved to $REPORT"
```
