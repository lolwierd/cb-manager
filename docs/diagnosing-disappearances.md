# Diagnosing a CBManager disappearance

CBManager runs for days at a time with no window, so when it goes away there is
usually nothing to look at. The absence of a crash dialog is itself information:
macOS shows one only for an *uncaught exception or signal inside the process*.
It shows nothing when the app quits normally, and nothing when the kernel kills
it (memory pressure, `kill -9`, a code-signature invalidation).

This is how to tell which of those happened.

## The three cases, and how to tell them apart in one minute

Everything below is a way of deciding which of these happened:

| What you find | What it means |
| --- | --- |
| A `CBManager-*.ips` crash report | The process **trapped**. A Swift runtime failure (a `fatalError`, a force-unwrap of nil, a double-resumed continuation) shows up here as `EXC_BREAKPOINT` / `SIGTRAP` with a Swift runtime message. Background/accessory apps routinely crash with no dialog, so "no dialog" does **not** rule this out. |
| A `JetsamEvent-*.ips` naming CBManager | macOS **killed it for memory**. |
| No report at all, and `exitReason` set in `lifecycle-state.json` | It **quit normally**. Something asked it to terminate: ⌘Q, the status bar Quit item, `pkill`, a logout. |
| No report at all, and `exitReason` null | It was **killed without a signal it could report** — `kill -9`, or a code-signature invalidation (see §6). |

Work the sections below in order; the first two usually settle it.

## 1. Look for a crash report

**This is first because it is the most likely and the most often missed.**

```bash
ls -lt ~/Library/Logs/DiagnosticReports/ | head -30
ls -lt /Library/Logs/DiagnosticReports/ | head -30
```

Anything named `CBManager-<timestamp>.ips` is a crash. Open the newest one and
read the top:

```bash
open -a Console ~/Library/Logs/DiagnosticReports/CBManager-*.ips
# or, for the header only:
head -60 "$(ls -t ~/Library/Logs/DiagnosticReports/CBManager-*.ips | head -1)"
```

What to look for:

- `"exception": {"type":"EXC_BREAKPOINT","signal":"SIGTRAP"}` plus a
  `termination` reason mentioning the Swift runtime → a Swift trap, not a
  memory problem.
- A frame naming `ImageTextRecognizer` or `swift_Concurrency` /
  `_checkedContinuation` → the known continuation hazard in
  `Sources/CBManager/ImageTextRecognizer.swift:10-27`. That code resumes the
  continuation from the Vision completion handler *and* from the `catch`, and
  Vision runs the completion handler even when `perform` throws, so a single
  failed OCR resumes the same continuation twice, which is a hard trap. It runs
  on every image copy.
- A `JetsamEvent-*.ips` instead → skip to §3.

If you find a CBManager crash report, that is the answer; the rest of this
document is for when you do not.

## 2. Read the app's own record

Since the lifecycle diagnostics landed, the app keeps two files:

```
~/Library/Application Support/CBManager/lifecycle-state.json
~/Library/Application Support/CBManager/lifecycle.log
```

**Right after you find the app gone, before relaunching it**, look at the state
file:

```bash
cat ~/Library/Application\ Support/CBManager/lifecycle-state.json
```

- `exitReason` is `"applicationWillTerminate"` → **the app quit normally.**
  ⌘Q while the overlay is focused does exactly this, as does Quit in the status
  bar menu.
- `exitReason` is `null` → **the app did not shut down in an orderly way**: it
  either trapped (§1) or was killed. `lastHeartbeatAt` is then within 30 seconds
  of the moment it died, and `footprintMB`, `threadCount`,
  `openFileDescriptors` and `entryCount` are its resource state at that moment.

Relaunching writes the same verdict into `lifecycle.log` as a one-line summary,
so the history survives:

```bash
tail -40 ~/Library/Application\ Support/CBManager/lifecycle.log
```

Look for `DIED WITHOUT CLEAN EXIT`. Compare `footprintMB` across occurrences: if
every death happens around the same footprint, it is a memory kill. If the
footprint is modest (a few hundred MB) and it dies anyway, it is not.

## 3. Confirm or rule out a memory kill

Memory-pressure kills leave their own report. Grep the jetsam reports for the
app:

```bash
grep -l CBManager ~/Library/Logs/DiagnosticReports/JetsamEvent-*.ips 2>/dev/null
```

A hit names the process and the footprint at kill time. Cross-check that number
against `peakFootprintMB` in `lifecycle.log`.

## 4. Ask the unified log what happened to the process

The unified log keeps roughly a day or two of history. Run this as soon as you
notice, and widen `--last` if you need more:

```bash
# Everything the app itself logged, including its lifecycle verdicts.
log show --last 6h --predicate 'subsystem == "com.cbmanager.app"' --info

# Terminations, signals, and memory-pressure decisions mentioning the app.
log show --last 6h --predicate 'eventMessage CONTAINS "CBManager"' --info | \
  grep -Ei 'exit|term|kill|jetsam|memorystatus|signal|codesign'

# What the process-management daemons said. This is where an OS kill shows up.
log show --last 6h --predicate \
  'process == "kernel" OR process == "runningboardd" OR process == "launchd"' \
  --info | grep -i cbmanager
```

To watch live instead of after the fact:

```bash
log stream --predicate 'eventMessage CONTAINS "CBManager"' --info
```

## 5. Watch it while it runs

If you want the memory trajectory without waiting for the next death:

```bash
# Footprint, thread count, and open files, every 60s, to a file.
while true; do
  pid=$(pgrep -x CBManager) || { echo "$(date -Is) not running"; sleep 60; continue; }
  printf '%s rss_mb=%s threads=%s fds=%s\n' \
    "$(date -Is)" \
    "$(ps -o rss= -p "$pid" | awk '{print $1/1024}')" \
    "$(ps -M -p "$pid" | tail -n +2 | wc -l | tr -d ' ')" \
    "$(lsof -p "$pid" 2>/dev/null | wc -l | tr -d ' ')"
  sleep 60
done >> ~/cbmanager-watch.log
```

Or read the numbers the app already records:

```bash
watch -n 30 "python3 -c \"import json;d=json.load(open('$HOME/Library/Application Support/CBManager/lifecycle-state.json'));print({k:d[k] for k in ('uptimeSeconds','footprintMB','peakFootprintMB','threadCount','openFileDescriptors','entryCount')})\""
```

A footprint that climbs and never comes back down points at retained history. A
thread count that climbs points at blocked subprocess waits. A file-descriptor
count that climbs points at leaked pipes from `qmd` / `pi` invocations.

## 6. Boring causes worth ruling out

- **Are you running the installed bundle or a dev build?** `scripts/reload-dev.sh`
  launches `.build/debug/CBManager` with `nohup`. If you then run `swift build`
  again, the binary file underneath the running process is replaced and macOS
  kills it for an invalid code signature — no dialog, no crash report. Check
  with `ps -o comm= -p $(pgrep -x CBManager)`.
- **⌘Q.** The overlay is a key window and the app installs a ⌘Q menu item. Hitting
  ⌘Q in the overlay quits the app rather than closing the overlay. `exitReason`
  in the state file will say so.
- **`scripts/install.sh`** `pkill`s any running CBManager before installing.
- **Launch at login** (Settings) makes the app come back on its own after a
  restart. If it does not come back after a reboot, that setting is off.
