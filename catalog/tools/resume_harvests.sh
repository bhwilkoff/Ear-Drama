#!/bin/sh
# Start any harvester that is not running. Every harvester resumes from its
# cache, so this is safe to run at any time (a container restart kills them).
cd "$(dirname "$0")/.." || exit 1
for t in "harvest_otrr.py:otrr.log" "harvest_grw.py:grw.log" "harvest_radioechoes.py:re.log"; do
  cmd=${t%%:*}; log=${t##*:}
  if ! pgrep -f "python3 tools/$cmd" >/dev/null; then
    nohup python3 "tools/$cmd" >> ".cache/$log" 2>&1 &
    echo "started $cmd"
  fi
done
for d in otrr/programs grw/text radioechoes/series; do echo "$d $(ls .cache/$d | wc -l)"; done
