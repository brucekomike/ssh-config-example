#!/bin/bash
# Quick ed25519 key creation: newkey.sh <group>/<name> -> keys/<group>/<name>[.pub]
set -u
# ASCII-only name matching: bracket ranges collate non-ASCII in UTF-8 locales.
LC_ALL=C

usage() {
  echo "usage: $(basename "$0") <group>/<name>" >&2
  echo "  creates keys/<group>/<name> (ed25519) relative to this repo/root ssh dir" >&2
  exit 1
}

[ "$#" -eq 1 ] || usage

key_rel="$1"

if [[ ! "$key_rel" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  echo "invalid key name: '$key_rel' (expected <group>/<name>)" >&2
  usage
fi

for component in "${key_rel%%/*}" "${key_rel##*/}"; do
  if [ "$component" = "." ] || [ "$component" = ".." ]; then
    echo "invalid key name: '$key_rel' (no '.' or '..' components)" >&2
    exit 1
  fi
done

# Resolve the ssh root from the script location, so cwd does not matter.
bin_dir="$(dirname "$(readlink -f "$0")")"
ssh_root="$(dirname "$bin_dir")"
keys_dir="$ssh_root/keys"
key_path="$keys_dir/$key_rel"
group_dir="$(dirname "$key_path")"

if [ -e "$key_path" ] || [ -e "$key_path.pub" ]; then
  echo "key already exists: $key_path" >&2
  exit 1
fi

group_existed=1
[ -d "$group_dir" ] || group_existed=0
mkdir -p "$group_dir"
chmod 700 "$keys_dir" "$group_dir"

if ! ssh-keygen -t ed25519 -f "$key_path"; then
  rm -f "$key_path" "$key_path.pub"
  [ "$group_existed" -eq 0 ] && rmdir "$group_dir" 2>/dev/null
  exit 1
fi

chmod 600 "$key_path" "$key_path.pub"

echo
echo "$key_path"
cat "$key_path.pub"
