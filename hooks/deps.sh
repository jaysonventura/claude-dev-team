#!/usr/bin/env bash
# cdt-deps — check (and optionally install) the SYSTEM prerequisites claude-dev-team uses.
#
# Note: companion PLUGINS (superpowers, code-review, frontend-design, context7) auto-install via the
# plugin manifest's `dependencies`. The scripts use only python3 STDLIB — there are NO pip packages.
# So this only covers system tools.
#
#   cdt-deps            check each prerequisite + print the install command for your OS
#   cdt-deps --install  install the missing required/recommended ones via your package manager
set +e

OS="$(uname 2>/dev/null)"
case "$OS" in
  Darwin) PLAT=macOS ;;
  Linux)  PLAT=Linux ;;
  MINGW*|MSYS*|CYGWIN*) PLAT=Windows ;;
  *) PLAT=unknown ;;
esac

PM=""; PMI=""
if   command -v brew    >/dev/null 2>&1; then PM=brew;   PMI="brew install"
elif command -v apt-get >/dev/null 2>&1; then PM=apt;    PMI="sudo apt-get install -y"
elif command -v dnf     >/dev/null 2>&1; then PM=dnf;    PMI="sudo dnf install -y"
elif command -v pacman  >/dev/null 2>&1; then PM=pacman; PMI="sudo pacman -S --noconfirm"
elif command -v zypper  >/dev/null 2>&1; then PM=zypper; PMI="sudo zypper install -y"
elif command -v winget  >/dev/null 2>&1; then PM=winget; PMI="winget install -e --id"
elif command -v choco   >/dev/null 2>&1; then PM=choco;  PMI="choco install -y"
elif command -v scoop   >/dev/null 2>&1; then PM=scoop;  PMI="scoop install"
fi

pkg() {  # package name for the detected manager
  case "$PM:$1" in
    *:python3) case "$PM" in winget) echo Python.Python.3.12 ;; *) echo python3 ;; esac ;;
    *:git)     case "$PM" in winget) echo Git.Git ;; *) echo git ;; esac ;;
    *:gh)      case "$PM" in winget) echo GitHub.cli ;; *) echo gh ;; esac ;;
    *:sqlite3) case "$PM" in winget) echo SQLite.SQLite ;; brew|pacman) echo sqlite ;; *) echo sqlite3 ;; esac ;;
    *) echo "$1" ;;
  esac
}

DEPS=(
  "python3|required|recall, advise, config, analytics"
  "git|required|version operations"
  "sqlite3|optional|analytics CLI (python3 fallback exists)"
  "gh|optional|PR autopilot"
)

echo "claude-dev-team — prerequisites  (OS: $PLAT · package manager: ${PM:-none})"
missing=""
for entry in "${DEPS[@]}"; do
  IFS='|' read -r tool need desc <<< "$entry"
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  [ok]      $tool"
  else
    echo "  [missing] $tool ($need) — $desc   →   ${PMI:-install} $(pkg "$tool")"
    [ "$need" != "optional" ] && missing="$missing $(pkg "$tool")"
  fi
done

if [ "${1:-}" = "--install" ]; then
  echo
  if [ -z "$missing" ]; then echo "All required/recommended prerequisites are present — nothing to install."; exit 0; fi
  if [ -z "$PM" ]; then
    echo "No supported package manager found. Install manually:"
    [ "$PLAT" = Windows ] && echo "  Python 3 → python.org · Git for Windows → gitforwindows.org"
    [ "$PLAT" = macOS ]   && echo "  Install Homebrew (brew.sh) then re-run, or get Python 3 from python.org."
    exit 0
  fi
  echo "Installing via $PM:$missing"
  for p in $missing; do echo "  → $PMI $p"; $PMI $p; done
  echo "Done. Re-run 'cdt-deps' to verify, then /cdt:doctor."
else
  echo
  echo "Run 'cdt-deps --install' to install the missing required/recommended tools."
  echo "(Companion plugins auto-install with claude-dev-team; scripts use python3 stdlib only — no pip packages.)"
fi
exit 0
