# Authority certificates

You can add all authority certificate (\*.crt) in `certificates` folder, they will be merged into `ca-bundle.crt` and a secret will be created with it and used by flux to avoid self signed certificate issue.

You can check all certificates:

```shell
openssl storeutl -noout -text -certs ./certificates/ca-bundle.crt
```

How to add a CA certificate from a website:

```shell
# Retrieve CA certificate
openssl s_client -showcerts -connect <put domain>:443 </dev/null 2>/dev/null | openssl x509 -outform PEM > /usr/local/share/ca-certificates/certificates/<put domain>.crt
# Output the certificate to check
openssl storeutl -noout -text -certs /usr/local/share/ca-certificates/certificates/<put domain>.crt
# Add the certificate to the system
sudo update-ca-certificates -f

```
