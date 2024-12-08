# Find the directory containing the file SPECIAL_LOCATOR with a max depth of 2
target_dir=$(find ../ -maxdepth 2 -type f -name "SPECIAL_LOCATOR" -exec dirname {} \; -quit)

# Check if the directory was found
if [ -n "$target_dir" ]; then
  # Change to the target directory
  cd "$target_dir" || exit
  # Print the current working directory
  pwd
  cd keys
  ssh-keygen -t ed25519 -f "$1"
else
  echo "SPECIAL_LOCATOR not found."
fi
