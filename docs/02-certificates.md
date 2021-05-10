# Generate and distribute the required certificates

[../scripts/02-certificates.sh](../scripts/02-certificates.sh)

```bash
# override if needed with env vars:
_COUNTRY="${CERT_COUNTRY:-US}"
_CITY="${CERT_CITY:-Portland}"
_STATE="${CERT_STATE:-Oregon}"
_EXPIRY="${CERT_EXPIRY:-8760h}"
_ORG="${CERT_ORG:-Kubernetes}"
_CA_ORG_UNIT="${CA_CERT_ORG_UNIT:-CA}"
_CERT_ORG_UNIT="${CERT_ORG_UNIT:-"Kubernetes the hard way"}"
_CN="${FQDN:-Kubernetes}"

# ca only
function make_ca() {
  cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "${_EXPIRY}"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "${_EXPIRY}"
      }
    }
  }
}
EOF

  cat > ca-csr.json <<EOF
{
  "CN": "${_CN}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "${_COUNTRY}",
      "L": "${_CITY}",
      "O": "${_ORG}",
      "OU": "${_CA_ORG_UNIT}",
      "ST": "${_STATE}"
    }
  ]
}
EOF
  cfssl gencert -initca ca-csr.json | cfssljson -bare ca
}

# generic
function make_cert() {
  _name="${1}"
  _cn="${2}"
  _o="${3}"
  _hostnames="${4:-}"
  cat > "${_name}-csr.json" <<EOF
{
  "CN": "${_cn}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "${_COUNTRY}",
      "L": "${_CITY}",
      "O": "${_o}",
      "OU": "${_CERT_ORG_UNIT}",
      "ST": "${_STATE}"
    }
  ]
}
EOF

if [ ! "${_hostnames}" = "" ];then
  cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  -hostname="${_hostnames}" \
  "${_name}-csr.json" | cfssljson -bare "${_name}"
else
  cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  "${_name}-csr.json" | cfssljson -bare "${_name}"
fi
}
...
```
