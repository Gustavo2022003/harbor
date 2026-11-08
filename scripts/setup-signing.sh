#!/bin/bash
# Cria (uma vez) um certificado próprio de assinatura de código "Harbor Dev" e instala nas Chaves.
# Com uma assinatura estável, o macOS mantém as permissões (Acessibilidade, Gravação de Tela,
# Câmera…) entre um build e outro. Uma cópia (.p12) fica em ~/.harbor/signing para o CI.
set -euo pipefail

NAME="Harbor Dev"
DIR="$HOME/.harbor/signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "✅ Certificado \"$NAME\" já está instalado."
  exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
cd "$DIR"

cat > cert.cnf <<CNF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[ dn ]
CN = $NAME
O  = Harbor
[ ext ]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
CNF

# LibreSSL do sistema gera um .p12 compatível com o "security import" do macOS
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout key.pem -out cert.pem -config cert.cnf >/dev/null 2>&1

PASS=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -name "$NAME" \
  -out harbor-dev.p12 -passout "pass:$PASS"
echo -n "$PASS" > p12-password.txt
chmod 600 key.pem harbor-dev.p12 p12-password.txt
rm -f cert.cnf

security import harbor-dev.p12 -k "$KEYCHAIN" -P "$PASS" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "✅ Certificado \"$NAME\" criado e instalado."
echo "   Cópia para o CI: $DIR/harbor-dev.p12 (senha em p12-password.txt)"
