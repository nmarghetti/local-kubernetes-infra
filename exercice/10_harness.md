# Harness

1. Harness delegate

   You can start a harness delegate through minikube as follow.

   ```shell
   HARNESS_ACCOUNT_ID='<PUT YOUR HARNESS ACCOUNT ID>'
   HARNESS_DELEGATE_TOKEN='<PUT YOUR HARNESS DELEGATE TOKEN>'
   export HARNESS_ACCOUNT_ID && export  HARNESS_DELEGATE_TOKEN && ./start.sh --minikube --harness-account-id "$HARNESS_ACCOUNT_ID" --harness-delegate-token "$HARNESS_DELEGATE_TOKEN" --harness-docker-runner-port 3250
   ```
