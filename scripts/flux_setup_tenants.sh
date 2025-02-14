#! /bin/bash

default_cluster_role="cluster-list-namespace"

usage() {
  cat <<EOM >&2
Usage: $0 <tenants.json file path> [options]

Options:
  -c, --cluster-role <cluster-role>       : cluster role to bind to each tenant to list namespace (default: $default_cluster_role)
  -d, --debug                             : debug mode (default)
      --debug-full                        : debug bash
  -h                                      : display this help

EOM
}

[ ! -f "$1" ] && {
  echo "Error: '$1' is not a file." >&2
  usage
  exit 1
}

tenant_file="$(readlink -f "$1")"
shift
cd "$(dirname "$tenant_file")" || {
  echo "Unable to go to parent folder of $tenant_file" >&2
  exit 1
}
tenant_file="$(basename "$tenant_file")"

cluster_role="$default_cluster_role"

# reset getopts - check https://man.cx/getopts(1)
OPTIND=1
while getopts "hc:d-:" opt; do
  case "$opt" in
    c) cluster_role="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    -)
      case "$OPTARG" in
        debug-full)
          set -eoxu pipefail
          export FULL_DEBUG=1
          ;;
        cluster-role)
          cluster_role="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          ;;
        help)
          usage
          exit 0
          ;;
        *)
          echo "Unknow option $OPTARG"
          usage
          exit 1
          ;;
      esac
      ;;
    \? | *)
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))
[ $# -ne 0 ] && {
  echo "Error: No argument accepted." >&2
  usage
  exit 1
}

create_cluster_role() {
  local tenant_name=$1
  local namespace=$2
  cat <<EOM
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${namespace}-view-list-ns-cluster-rolebinding
subjects:
  - kind: Group
    apiGroup: rbac.authorization.k8s.io
    name: ${tenant_name}-member-view
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $cluster_role
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${namespace}-read-list-ns-cluster-rolebinding
subjects:
  - kind: Group
    apiGroup: rbac.authorization.k8s.io
    name: ${tenant_name}-member-read
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $cluster_role
EOM
}

create_group_role() {
  local tenant_name=$1
  local namespace=$2
  cat <<EOM
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${namespace}-view
  namespace: $namespace
rules:
  - verbs:
      - get
      - list
      - watch
    apiGroups:
      - ''
    resources:
      - pods
      - services
      - configmaps
      - namespaces
      - pods/log
  - verbs:
      - get
      - list
      - watch
    apiGroups:
      - apps
    resources:
      - deployments
  - verbs:
      - create
    apiGroups:
      - ''
    resources:
      - pods/portforward
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${namespace}-view-rolebinding
  namespace: ${namespace}
subjects:
  - kind: Group
    apiGroup: rbac.authorization.k8s.io
    name: ${tenant_name}-member-view
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${namespace}-view
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${namespace}-view-secret
  namespace: $namespace
rules:
  - verbs:
      - get
      - list
      - watch
    apiGroups:
      - ''
    resources:
      - secrets
  - verbs:
      - create
    apiGroups:
      - ''
    resources:
      - pods/exec
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${namespace}-view-secret-rolebinding
  namespace: ${namespace}
subjects:
  - kind: Group
    apiGroup: rbac.authorization.k8s.io
    name: ${tenant_name}-member-view-secret
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${namespace}-view-secret
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${namespace}-read
  namespace: $namespace
rules:
  - verbs:
      - get
      - list
      - watch
    apiGroups:
      - ''
    resources:
      - bindings
      - componentstatuses
      - configmaps
      - endpoints
      - events
      - limitranges
      - namespaces
      - nodes
      - persistentvolumeclaims
      - persistentvolumes
      - pods
      - podtemplates
      - replicationcontrollers
      - resourcequotas
      - serviceaccounts
      - services
  - verbs:
      - get
      - list
      - watch
    apiGroups:
      - helm.sh
      - apps
      - batch
      - external-secrets.io
      - extensions
      - networking.k8s.io
      - policy
      - storage.k8s.io
      - traefik.io
      - helm.toolkit.fluxcd.io
    resources:
      - '*'
  - verbs:
      - create
    apiGroups:
      - ''
    resources:
      - pods/portforward
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${namespace}-read-rolebinding
  namespace: ${namespace}
subjects:
  - kind: Group
    apiGroup: rbac.authorization.k8s.io
    name: ${tenant_name}-member-read
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${namespace}-read
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${namespace}-admin
  namespace: $namespace
rules:
  - verbs:
      - '*'
    apiGroups:
      - '*'
    resources:
      - '*'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${namespace}-admin-rolebinding
  namespace: ${namespace}
subjects:
  - kind: Group
    apiGroup: rbac.authorization.k8s.io
    name: ${tenant_name}-member-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${namespace}-admin
EOM
}

tenants_base_path=$(jq -r '.tenant_base_path' <"$tenant_file")
clusters_tenant_folder=$(jq -r '.tenant_cluster_folder // "tenant"' <"$tenant_file")
cluster_config=$(jq -r '.cluster_config // ""' <"$tenant_file")
cluster_config_optional=$(jq -r '.cluster_config_optional // "true"' <"$tenant_file")

# Remove all tenants to regenerate them
rm -rf "$tenants_base_path"
for cluster_index in $(seq 0 1 $(($(jq '.clusters | length' <"$tenant_file") - 1))); do
  cluster_info=$(jq '.clusters['"$cluster_index"']' <"$tenant_file")
  cluster_path="$(echo "$cluster_info" | jq -r '.path')"
  rm -rf "${cluster_path:?Error: 'cluster_path' variable is empty}/${clusters_tenant_folder:?Error: 'clusters_tenant_folder' variable is empty}"
done

for tenant_index in $(seq 0 1 $(($(jq '.tenants | length' <"$tenant_file") - 1))); do
  tenant_info=$(jq '.tenants['"$tenant_index"']' <"$tenant_file")
  tenant_name="$(echo "$tenant_info" | jq -r '.name')"
  tenant_namespace="$(echo "$tenant_info" | jq -r '.namespace')"
  tenant_namespace_labels="$(echo "$tenant_info" | jq -r '.namespace_labels // [] | .[]')"
  tenant_git_url="$(echo "$tenant_info" | jq -r '.git_url')"
  tenant_git_path="$(echo "$tenant_info" | jq -r '.git_path')"
  tenant_namespaces="$(echo "$tenant_info" | jq -r '.extra_namespaces[]')"

  echo "Treating tenant $tenant_name..."

  tenant_base_path="$tenants_base_path/$tenant_namespace"
  echo "  - Adding definition to $tenant_base_path"
  mkdir -p "$tenant_base_path"
  echo "# Automatically generated by $0" >"$tenant_base_path"/sync.yaml
  flux create source git --secret-ref flux-system "$tenant_name" --namespace="$tenant_namespace" --url="$tenant_git_url" --branch=main --export | yq >>"$tenant_base_path"/sync.yaml
  flux create kustomization --prune --path to-override "$tenant_name" --namespace="$tenant_namespace" --service-account="$tenant_name" --source=GitRepository/"$tenant_name" --export | yq >>"$tenant_base_path"/sync.yaml
  if [ -n "$cluster_config" ]; then
    cat <<EOM >>"$tenant_base_path"/sync.yaml
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: $cluster_config
        optional: $cluster_config_optional
EOM
  fi
  cat <<EOM >>"$tenant_base_path"/sync.yaml
  healthChecks:
    - apiVersion: source.toolkit.fluxcd.io/v1
      kind: GitRepository
      name: $tenant_name
      namespace: $tenant_namespace
EOM
  echo "# Automatically generated by $0" >"$tenant_base_path"/rbac.yaml
  flux create tenant "$tenant_name" --with-namespace="$tenant_namespace" --export | yq >>"$tenant_base_path"/rbac.yaml
  cat <<EOM >"$tenant_base_path"/kustomization.yaml
# Automatically generated by $0
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: $tenant_namespace
resources:
  - rbac.yaml
  - sync.yaml
EOM
  if [ -n "$tenant_namespace_labels" ]; then
    cat <<EOM >>"$tenant_base_path"/kustomization.yaml
patches:
  - patch: |-
      apiVersion: v1
      kind: Namespace
      metadata:
        name: $tenant_namespace
        labels:
$(echo "$tenant_namespace_labels" | sed 's/^/          /')
EOM
  fi

  for cluster_index in $(seq 0 1 $(($(jq '.clusters | length' <"$tenant_file") - 1))); do
    cluster_info=$(jq '.clusters['"$cluster_index"']' <"$tenant_file")
    cluster_name="$(echo "$cluster_info" | jq -r '.name')"
    cluster_path="$(echo "$cluster_info" | jq -r '.path')"
    cluster_git_branch="$(echo "$cluster_info" | jq -r '.git_branch // "main"')"
    cluster_tenant_git_url="$(echo "$cluster_info" | jq -r '.git_url // "'"$tenant_git_url"'"')"
    tenant_namespaces="$(echo "$tenant_info" | jq -r '[ .extra_namespaces, .extra_cluster_namespaces.["'"$cluster_name"'"] ] | flatten | reduce .[] as $a ([]; if ($a != null) then . += [$a] else . end) | .[]')"
    tenant_cluster_path="${cluster_path}/${clusters_tenant_folder}/${tenant_namespace}"
    echo "  - Adding it to cluster $cluster_name at $tenant_cluster_path..."
    mkdir -p "$tenant_cluster_path"

    # Generate cluster role binding
    mkdir -p "${tenant_cluster_path}-cluster-role"
    cat <<EOM >"${tenant_cluster_path}-cluster-role"/kustomization.yaml
# Automatically generated by $0
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - role.yaml
EOM
    [ ! -f "${tenant_cluster_path}-cluster-role"/role.yaml ] && echo "# Automatically generated by $0" >"${tenant_cluster_path}-cluster-role"/role.yaml
    for namespace in $tenant_namespace $tenant_namespaces; do
      create_cluster_role "$tenant_name" "$namespace" >>"${tenant_cluster_path}-cluster-role"/role.yaml
    done

    kustomization_relative_path="$(realpath --relative-to="$tenant_cluster_path" "$tenant_base_path")"
    kustomization_git_path="$(export cluster_name="${cluster_name}" && echo "$tenant_git_path" | envsubst '\${cluster_name}')"
    cat <<EOM >"$tenant_cluster_path"/kustomization.yaml
# Automatically generated by $0
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - $kustomization_relative_path
  - role.yaml
patches:
  - target:
      group: kustomize.toolkit.fluxcd.io
      version: v1
      kind: Kustomization
      name: $tenant_name
    patch: |-
      - op: add
        path: /spec/path
        value: $kustomization_git_path
  - target:
      group: source.toolkit.fluxcd.io
      version: v1
      kind: GitRepository
      name: $tenant_name
    patch: |-
      - op: replace
        path: /spec/url
        value: $cluster_tenant_git_url
      - op: replace
        path: /spec/ref/branch
        value: $cluster_git_branch
EOM
    echo "# Automatically generated by $0" >"$tenant_cluster_path"/role.yaml
    create_group_role "$tenant_name" "$tenant_namespace" >>"$tenant_cluster_path"/role.yaml
    if [ -n "$tenant_namespaces" ]; then
      mkdir -p "${tenant_cluster_path}-namespaces"
      cat <<EOM >"${tenant_cluster_path}-namespaces"/kustomization.yaml
# Automatically generated by $0
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - rbac.yaml
  - role.yaml
patches:
  # You need to give access to the tenant for each of its namespace
EOM
      echo "# Automatically generated by $0" >"${tenant_cluster_path}-namespaces"/rbac.yaml
      echo "# Automatically generated by $0" >"${tenant_cluster_path}-namespaces"/role.yaml
      for namespace in $tenant_namespaces; do
        cat <<EOM >>"${tenant_cluster_path}-namespaces"/kustomization.yaml
  - target:
      kind: RoleBinding
      name: ${tenant_name}-reconciler
      namespace: $namespace
    patch: |-
      - op: add
        path: /subjects/-
        value:
          kind: ServiceAccount
          name: $tenant_name
          namespace: $tenant_namespace
EOM
        if [ -n "$tenant_namespace_labels" ]; then
          cat <<EOM >>"${tenant_cluster_path}-namespaces"/kustomization.yaml
  - patch: |-
      apiVersion: v1
      kind: Namespace
      metadata:
        name: $namespace
        labels:
$(echo "$tenant_namespace_labels" | sed 's/^/          /')
EOM
        fi
        flux create tenant "$tenant_name" --with-namespace="$namespace" --export | yq >>"${tenant_cluster_path}-namespaces"/rbac.yaml
        create_group_role "$tenant_name" "$namespace" >>"${tenant_cluster_path}-namespaces"/role.yaml
      done
    fi
  done
done
