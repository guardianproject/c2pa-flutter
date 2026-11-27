#!/usr/bin/env bash
# Run one integration test file on the iOS simulator in $DEVICE_ID.
#
# On hosted runners `flutter test` intermittently launches the app and then
# waits forever at "Waiting for VM Service port to be available...": the tool
# never sees the VM service announcement in the simulator log. When the log
# sits on that line for $stall_seconds, the attempt is killed and retried;
# any other failure is final.
#
# Usage: ios-integration-test.sh <test file> <log file>
set -u

test_file=$1
log_file=$2
attempts=3
stall_seconds=180
attempt_seconds=1200
bundle_id=org.guardianproject.c2paExample

for attempt in $(seq 1 "$attempts"); do
  echo "Attempt $attempt of $attempts: $test_file"
  flutter test "$test_file" -d "$DEVICE_ID" --ignore-timeouts -v > "$log_file" 2>&1 &
  test_pid=$!
  started=$(date +%s)
  stalled=false

  while kill -0 "$test_pid" 2>/dev/null; do
    sleep 10
    now=$(date +%s)
    if tail -n 1 "$log_file" | grep -q 'Waiting for VM Service port'; then
      idle=$(( now - $(stat -f %m "$log_file") ))
      if [ "$idle" -ge "$stall_seconds" ]; then
        stalled=true
        kill "$test_pid" 2>/dev/null
        break
      fi
    fi
    if [ $(( now - started )) -ge "$attempt_seconds" ]; then
      echo "Attempt $attempt exceeded ${attempt_seconds}s."
      kill "$test_pid" 2>/dev/null
      break
    fi
  done

  wait "$test_pid"
  status=$?

  if [ "$stalled" = true ]; then
    echo "Attempt $attempt stalled waiting for the VM service; retrying."
    xcrun simctl terminate "$DEVICE_ID" "$bundle_id" 2>/dev/null || true
    continue
  fi

  if [ "$status" -eq 0 ]; then
    grep -E '[0-9]+ tests? passed|All tests passed' "$log_file" | tail -3
    exit 0
  fi

  tail -150 "$log_file"
  exit 1
done

echo "Every attempt stalled waiting for the VM service."
tail -40 "$log_file"
exit 1
