#!/bin/sh
# A signing identity for this Mac, so the Keychain sees the same app after every rebuild and asks once per
# secret instead of after every update (DECISIONS local-035, README › Signing).
#
# It is a self-signed certificate made here, on this Mac, and kept in the login keychain. Nothing comes
# from Apple and nothing is sent anywhere: no Apple ID, no account, no email address.
#
#   scripts/identity.sh            make sure there is one, and name it in .sign-identity
#   scripts/identity.sh --check    say what is there; change nothing
#
#   GREAT_GUI_IDENTITY   the certificate's name (the-great-gui dev)
#   GREAT_GUI_KEYCHAIN   the keychain it goes into (the login keychain); a test names a throwaway one
set -e
cd "$(dirname "$0")/.."

NAME="${GREAT_GUI_IDENTITY:-the-great-gui dev}"
KEYCHAIN="${GREAT_GUI_KEYCHAIN:-}"
ok()   { printf '✓ %s\n' "$*"; }
note() { printf '  · %s\n' "$*"; }
fail() { printf '✗ %s\n' "$*" >&2; exit 1; }

# Is there a code-signing identity of this name? codesign signs with a self-signed one named outright,
# trusted or not, so "matching" is the question, not "valid".
have() {
  # shellcheck disable=SC2086
  security find-identity -p codesigning $KEYCHAIN 2>/dev/null | grep -qF "\"$1\""
}

named="$(head -1 .sign-identity 2>/dev/null || true)"

if [ "${1:-}" = "--check" ]; then
  if [ -n "$named" ] && have "$named"; then ok "identity  $named · named in .sign-identity"
  elif [ -n "$named" ]; then note "identity  .sign-identity names $named, which this Mac does not have · builds will fail to sign"
  elif have "$NAME"; then note "identity  $NAME is here but .sign-identity does not name it · scripts/identity.sh writes it"
  else note "identity  none · builds are ad-hoc signed, so the Keychain asks again after every rebuild · scripts/identity.sh makes one"
  fi
  exit 0
fi

if [ -n "$named" ] && have "$named"; then
  ok "identity  $named"
  exit 0
fi
[ -z "$named" ] || note ".sign-identity names $named, which this Mac does not have; using $NAME"

if ! have "$NAME"; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  cat > "$tmp/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF
  # Ten years; the private key never leaves this Mac. The p12 password only covers the hop into the keychain.
  pass="$(/usr/bin/openssl rand -hex 16)"
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.conf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" >/dev/null 2>&1 || fail "could not make the certificate (openssl)"
  /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$NAME" \
    -out "$tmp/id.p12" -passout "pass:$pass" >/dev/null 2>&1 || fail "could not package the certificate (openssl)"
  # shellcheck disable=SC2086
  security import "$tmp/id.p12" ${KEYCHAIN:+-k "$KEYCHAIN"} -P "$pass" -T /usr/bin/codesign >/dev/null 2>&1 \
    || fail "could not add the certificate to the keychain"
  have "$NAME" || fail "made $NAME, but it is not in the keychain as a signing identity · README › Signing has the steps by hand in Keychain Access"
  ok "identity  made $NAME · self-signed, on this Mac only, nothing from Apple"
  note "the first build signed with it asks for your login password, once, to let codesign use the key: choose Always Allow"
fi

printf '%s\n' "$NAME" > .sign-identity
ok "identity  $NAME · named in .sign-identity (git-ignored)"
