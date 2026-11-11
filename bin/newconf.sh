#!/bin/bash
# Quick ssh_config extension: newconf.sh <group>/<name> [user@]hostname[:port]
# Appends a Host block that points at keys/<group>/<name> into config.d/<group>.
set -u
# ASCII-only matching: bracket ranges collate non-ASCII in UTF-8 locales.
LC_ALL=C

usage() {
  {
    echo "usage: $(basename "$0") <group>/<name> [user@]hostname[:port] [options]"
    echo "  appends a Host block using keys/<group>/<name> to config.d/<group>"
    echo "options:"
    echo "  -a alias   Host alias (default: the key's <name>)"
    echo "  -f file    config.d destination file (default: the key's <group>)"
    echo "  -T         write into a fresh temporary config dir instead of config.d"
    echo "  -d dir     write into an explicit config dir (reuse a -T dir across runs)"
    echo "  -h         show this help"
    echo "  keys are unaffected by -T/-d: IdentityFile always names ~/.ssh/keys/<group>/<name>"
  } >&2
  exit "${1:-1}"
}

key_rel=""
host_spec=""
alias_name=""
conf_file=""
temp_conf=0
conf_dir_opt=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -a|-f|-d)
      [ "$#" -ge 2 ] || { echo "missing value for $1" >&2; usage; }
      [ -n "$2" ] || { echo "empty value for $1" >&2; exit 1; }
      case "$1" in
        -a) alias_name="$2" ;;
        -f) conf_file="$2" ;;
        -d) conf_dir_opt="$2" ;;
      esac
      shift 2
      ;;
    -T|--temp) temp_conf=1; shift ;;
    -h) usage 0 ;;
    -*) echo "unknown option: $1" >&2; usage ;;
    *)
      if [ -z "$key_rel" ]; then key_rel="$1"
      elif [ -z "$host_spec" ]; then host_spec="$1"
      else echo "unexpected argument: $1" >&2; usage
      fi
      shift
      ;;
  esac
done

if [ "$temp_conf" -eq 1 ] && [ -n "$conf_dir_opt" ]; then
  echo "-T and -d are mutually exclusive (-d reuses a dir, -T makes a new one)" >&2
  exit 1
fi

[ -n "$key_rel" ] || usage
[ -n "$host_spec" ] || { echo "hostname required" >&2; usage; }

if [[ ! "$key_rel" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  echo "invalid key name: '$key_rel' (expected <group>/<name>)" >&2
  exit 1
fi

key_group="${key_rel%%/*}"
key_name="${key_rel##*/}"
[ -n "$alias_name" ] || alias_name="$key_name"
[ -n "$conf_file" ] || conf_file="$key_group"

if [[ ! "$alias_name" =~ ^[A-Za-z0-9._-]+$ ]] || [ "$alias_name" = "." ] || [ "$alias_name" = ".." ]; then
  echo "invalid alias: '$alias_name'" >&2
  exit 1
fi

if [[ ! "$conf_file" =~ ^[A-Za-z0-9._-]+$ ]] || [ "$conf_file" = "." ] || [ "$conf_file" = ".." ]; then
  echo "invalid config file: '$conf_file' (a name under config.d, no path)" >&2
  exit 1
fi

# Split [user@]hostname[:port]; a hostname with two colons is not a port suffix.
host="$host_spec"
user=""
port=""
if [[ "$host" == *@* ]]; then
  user="${host%%@*}"
  host="${host#*@}"
fi
if [[ "$host" == *:* && "$host" != *:*:* ]]; then
  port="${host##*:}"
  host="${host%:*}"
fi

if [[ ! "$host" =~ ^[A-Za-z0-9._-]+$ ]] || [ -z "$host" ]; then
  echo "invalid hostname: '$host'" >&2
  exit 1
fi
if [ -n "$user" ] && [[ ! "$user" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "invalid user: '$user'" >&2
  exit 1
fi
if [ -n "$port" ] && { [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; }; then
  echo "invalid port: '$port' (1-65535)" >&2
  exit 1
fi

bin_dir="$(dirname "$(readlink -f "$0")")"
ssh_root="$(dirname "$bin_dir")"
keys_dir="$ssh_root/keys"
conf_dir="$ssh_root/config.d"

# -T/-d redirect only the config destination; the key check below still reads the
# real keys dir, because IdentityFile is written as a literal ~/.ssh/keys path.
if [ "$temp_conf" -eq 1 ]; then
  conf_dir="$(mktemp -d -t "ssh-config.XXXXXX")" || { echo "could not create temp dir" >&2; exit 1; }
elif [ -n "$conf_dir_opt" ]; then
  conf_dir="$conf_dir_opt"
fi
conf_path="$conf_dir/$conf_file"

if [ ! -f "$keys_dir/$key_rel" ]; then
  echo "warning: no such key yet: $keys_dir/$key_rel (run newkey.sh $key_rel)" >&2
fi

mkdir -p "$conf_dir"
chmod 700 "$conf_dir"
[ -f "$conf_path" ] || : > "$conf_path"
chmod 600 "$conf_path"

# Matches an exact token on a Host line, ignoring patterns already listed there.
has_alias() {
  awk -v want="$alias_name" '
    tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i == want) { found = 1; exit } }
    END { exit !found }
  ' "$1"
}

if has_alias "$conf_path"; then
  echo "'Host $alias_name' already in $conf_path" >&2
  echo "  pick another alias with -a, or edit the existing block" >&2
  exit 1
fi

other=""
for f in "$conf_dir"/*; do
  [ -f "$f" ] || continue
  [ "$f" = "$conf_path" ] && continue
  has_alias "$f" && other="$other$f"$'\n'
done
other="${other%$'\n'}"
if [ -n "$other" ]; then
  echo "warning: 'Host $alias_name' also defined in:" >&2
  echo "$other" | sed 's/^/  /' >&2
  echo "  ssh takes the first matching value, so the duplicate may be ignored" >&2
fi

# Keep blocks separated by exactly one blank line, like the existing config.d files.
[ -s "$conf_path" ] && [ "$(tail -c 1 "$conf_path" | wc -l)" -eq 0 ] && echo >> "$conf_path"
[ -s "$conf_path" ] && echo >> "$conf_path"

block="Host $alias_name
  HostName $host"
[ -n "$user" ] && block="$block
  User $user"
[ -n "$port" ] && block="$block
  Port $port"
block="$block
  IdentityFile ~/.ssh/keys/$key_rel"

printf '%s\n' "$block" >> "$conf_path"

echo "appended to $conf_path:"
printf '%s\n' "$block"

if [ "$temp_conf" -eq 1 ] || [ -n "$conf_dir_opt" ]; then
  echo
  echo "config dir: $conf_dir"
  echo "  next host:  $(basename "$0") <group>/<name> <host> -d '$conf_dir'"
  echo "  check:      ssh -G -F /dev/stdin $alias_name <<< 'Include $conf_dir/*'"
  if [ "$temp_conf" -eq 1 ]; then
    echo "  done:       rm -rf '$conf_dir'"
  fi
fi
