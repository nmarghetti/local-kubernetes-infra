# Certificates

## For WSL

You might be behind an enterprise proxy or VPN and need to add some certificates to WSL in order to avoid connection issue. In that case, ask for those certificates, put them under `/usr/local/share/ca-certificates/` folder and run the following command `update-ca-certificates`.

You can check that the following command run well:

```shell
openssl s_client -connect google.com:443 </dev/null
```

It should end up like with something like that:

```text
---
SSL handshake has read 7435 bytes and written 392 bytes
Verification: OK
---
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Server public key is 256 bit
Secure Renegotiation IS NOT supported
Compression: NONE
Expansion: NONE
No ALPN negotiated
Early data was not sent
Verify return code: 0 (ok)
---
DONE
```

## For docker, minikube, kind

```shell
# retrieve the certificates under /usr/local/share/ca-certificates/ and store them under ./certificates
./certificates/retrieve_system_certificates.sh
# create certificates bundle ./certificates/ca-bundle.crt
./certificates/compute_ca_certificate.sh
# copy certificates under $HOME/.minikube/certs/ to be used by minikube
./certificates/copy_certificates_to_minikube.sh
```
