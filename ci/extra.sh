#!/bin/bash
XC="$(ls -d /Applications/Xcode_*.app | sort -V | tail -1)"
D="$XC/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/pm/ManifestAPI"
ls -R "$D" 2>&1 | grep -i -E "product|\.swiftinterface|swiftmodule" | head -20
for f in $(find "$D" -iname "*ProductTypes*" 2>/dev/null | head -5); do
  echo "== $f"
  if [ -d "$f" ]; then find "$f" -type f | head; fi
done
for f in $(find "$D" -iname "*.swiftinterface" 2>/dev/null | head -5); do
  echo "== interface $f"
  grep -n "PlaceholderIcon" "$f" | head -5
  awk '/enum PlaceholderIcon|struct PlaceholderIcon/{p=1} p{print} /^    }/{if(p){c++}} c>3{exit}' "$f" | head -80
done
for f in $(find "$D" -iname "*.swiftmodule" -type f 2>/dev/null | head -5); do
  echo "== module $f"
  strings "$f" | grep -i -E "PlaceholderIcon" | head -5
done
