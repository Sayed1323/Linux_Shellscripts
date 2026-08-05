#!/usr/bin/env bash
#############################################
# CPU & RAM Monitor with Email Alerts
#############################################

set -uo pipefail

### ---------- CONFIGURATION ----------
CPU_THRESHOLD=1          # percent
RAM_THRESHOLD=20          # percent
CHECK_INTERVAL=6         # seconds between checks
COOLDOWN=20              # seconds before re-alerting on the same resource

ALERT_EMAIL="sayedsa1323@gmail.com"       # <-- CHANGE THIS: where alerts go
HOSTNAME_LABEL="$(hostname)"

LOG_FILE="/var/log/resource_monitor.log"
STATE_DIR="/tmp/resource_monitor_state"
### ------------------------------------

mkdir -p "$STATE_DIR"
CPU_STATE_FILE="$STATE_DIR/cpu_last_alert"
RAM_STATE_FILE="$STATE_DIR/ram_last_alert"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

get_cpu_usage() {
    local cpu user nice system idle iowait irq softirq steal _rest
    local total1 idle1 total2 idle2 total_diff idle_diff

    read -r cpu user nice system idle iowait irq softirq steal _rest < /proc/stat
    total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
    idle1=$idle

    sleep 1

    read -r cpu user nice system idle iowait irq softirq steal _rest < /proc/stat
    total2=$((user + nice + system + idle + iowait + irq + softirq + steal))
    idle2=$idle

    total_diff=$((total2 - total1))
    idle_diff=$((idle2 - idle1))

    if (( total_diff <= 0 )); then
        echo 0
        return
    fi

    echo $(( (1000 * (total_diff - idle_diff) / total_diff + 5) / 10 ))
}

get_ram_usage() {
    free | awk '/Mem:/ { printf("%.0f", $3/$2 * 100) }'
}

send_alert() {
    local subject="$1"
    local body="$2"
    local msg from_addr
    from_addr=$(msmtp --print-conf -a gmail 2>/dev/null | awk '/^from/ {print $2}')
    msg=$(printf "From: %s\nTo: %s\nSubject: %s\nDate: %s\n\n%s\n" \
        "$from_addr" "$ALERT_EMAIL" "$subject" "$(date -R)" "$body")

    if echo "$msg" | msmtp -a gmail "$ALERT_EMAIL"; then
        log "ALERT SENT: $subject"
    else
        log "FAILED TO SEND ALERT: $subject (check ~/.msmtprc and ~/.msmtp.log)"
    fi
}

should_alert() {
    local state_file="$1"
    [[ ! -f "$state_file" ]] && return 0
    local last_alert now
    last_alert=$(cat "$state_file")
    now=$(date +%s)
    (( now - last_alert >= COOLDOWN ))
}

mark_alerted() {
    date +%s > "$1"
}

log "Resource monitor started. CPU threshold=${CPU_THRESHOLD}%, RAM threshold=${RAM_THRESHOLD}%, interval=${CHECK_INTERVAL}s"

while true; do
    cpu_usage=$(get_cpu_usage)
    ram_usage=$(get_ram_usage)

    log "CPU: ${cpu_usage}% | RAM: ${ram_usage}%"

    if (( cpu_usage >= CPU_THRESHOLD )) && should_alert "$CPU_STATE_FILE"; then
        send_alert "High CPU Usage Alert - ${cpu_usage}%" \
            "CPU usage on ${HOSTNAME_LABEL} reached ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%) at $(date)."
        mark_alerted "$CPU_STATE_FILE"
    fi

    if (( ram_usage >= RAM_THRESHOLD )) && should_alert "$RAM_STATE_FILE"; then
        send_alert "High RAM Usage Alert - ${ram_usage}%" \
            "RAM usage on ${HOSTNAME_LABEL} reached ${ram_usage}% (threshold: ${RAM_THRESHOLD}%) at $(date)."
        mark_alerted "$RAM_STATE_FILE"
    fi

    sleep "$CHECK_INTERVAL"
done
