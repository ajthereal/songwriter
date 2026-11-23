#!/bin/bash
XC="$(ls -d /Applications/Xcode_*.app | sort -V | tail -1)"
echo "== searching manifest API dirs"
ls "$XC/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/pm" 2>&1 | head
D="$XC/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/pm"
for f in $(grep -rl "PlaceholderIcon" "$D" 2>/dev/null | head -5); do
  echo "-- $f"
  strings "$f" | grep -E "^(placeholder|icon)|PlaceholderIcon" | head -5
done
for f in $(find "$D" -name "*AppleProductTypes*" 2>/dev/null | head -10); do echo "found $f"; done
for f in $(find "$D" -name "AppleProductTypes*.swiftinterface" 2>/dev/null | head -2); do
  grep -n -B2 -A50 "PlaceholderIcon" "$f" | head -100
done
