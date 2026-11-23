#!/bin/bash
# Debug helper: lists the placeholder icons available to AppleProductTypes manifests.
XC="$(ls -d /Applications/Xcode_*.app | sort -V | tail -1)"
echo "== searching AppleProductTypes in $XC"
F="$(find "$XC" -iname "*AppleProductTypes*" 2>/dev/null | head -20)"
echo "$F"
for f in $F; do
  if [ -f "$f" ]; then echo "-- $f"; strings "$f" | grep -i -E "placeholder|PlaceholderIcon" | head -20; fi
  if [ -d "$f" ]; then find "$f" -type f | head -5; fi
done
for f in $(find "$XC" -iname "*AppleProductTypes*.swiftinterface" 2>/dev/null | head -3); do
  echo "-- interface $f"; grep -n -A60 "PlaceholderIcon" "$f" | head -120
done
