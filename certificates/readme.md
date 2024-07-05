# Authority certificates

You can add all authority certificate (\*.crt) in `certificates` folder, they will be merged into `ca-bundle.crt` and a secret will be created with it and used by flux to avoid self signed certificate issue.

You can check all certificates:

```shell
openssl storeutl -noout -text -certs ./certificates/ca-bundle.crt
```
