#!/bin/bash
# 一次性运行：在本地钥匙串里创建 Keybot 专用代码签名证书
set -e

CERT_NAME="Keybot Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning -v 2>/dev/null | grep -q "\"$CERT_NAME\""; then
    echo "✅ 证书「$CERT_NAME」已存在"
    exit 0
fi

echo "▶ 生成密钥和证书..."
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

openssl genrsa -out "$TMP/key.pem" 2048 2>/dev/null

cat > "$TMP/ext.cnf" << 'EOF'
[req]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[dn]
CN = Keybot Dev
[ext]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = codeSigning
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
EOF

openssl req -new -x509 -days 3650 \
    -key "$TMP/key.pem" -config "$TMP/ext.cnf" \
    -out "$TMP/cert.pem" 2>/dev/null

openssl pkcs12 -export \
    -in "$TMP/cert.pem" -inkey "$TMP/key.pem" \
    -out "$TMP/cert.p12" -name "$CERT_NAME" \
    -passout pass: 2>/dev/null

echo "▶ 导入到钥匙串（会弹窗要求输入登录密码）..."
security import "$TMP/cert.p12" \
    -k "$KEYCHAIN" -P "" \
    -T /usr/bin/codesign -T /usr/bin/security

echo ""
echo "▶ 设置信任..."
# 需要输入密码授权
security add-trusted-cert -r trustAsRoot -p codeSign \
    -k "$KEYCHAIN" "$TMP/cert.pem" 2>/dev/null || {
    echo ""
    echo "⚠️  自动设置信任失败，请手动完成（只需一次）："
    echo "   1. 打开「钥匙串访问」"
    echo "   2. 找到「Keybot Dev」证书，双击"
    echo "   3. 展开「信任」→「代码签名」→ 改为「始终信任」"
    echo "   4. 关闭窗口，输入密码确认"
    open /System/Applications/Utilities/Keychain\ Access.app
}

echo ""
echo "✅ 完成！之后 build.sh 会自动用此证书签名，不再需要重复授权辅助功能。"
