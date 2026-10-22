#!/bin/sh
# Start any harvester that is not running. Every harvester resumes from its
# cache, so this is safe to run at any time (a container restart kills them).
cd "$(dirname "$0")/.." || exit 1
start() {  # $1 = command after "python3 tools/", $2 = log name
  if ! pgrep -f "^python3 tools/$1" >/dev/null; then
    nohup python3 tools/$1 >> ".cache/$2" 2>&1 &
    echo "started $1"
  fi
}
start "harvest_otrrpedia.py --phase programs" otrrpedia_programs.log
start "harvest_otrrpedia.py --phase people" otrrpedia_people.log
for d in otrr/programs grw/text radioechoes/series; do echo "$d $(ls .cache/$d 2>/dev/null | wc -l)"; done
