package main

import rego.v1

# ------------------------------------------------------------
# Configuration (à adapter à votre contexte)
# ------------------------------------------------------------

allowed_service_types := {"ClusterIP", "NodePort"}

# Capabilities ajoutables autorisées
allowed_added_capabilities := {"NET_BIND_SERVICE"}

# Registres d'images autorisés (laisser vide pour désactiver la règle)
allowed_registries := set()
# exemple : allowed_registries := {"registry.mycorp.com/", "gcr.io/my-project/"}

workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"}

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

res_name := object.get(input, ["metadata", "name"], "<sans-nom>")

label := sprintf("%s/%s", [input.kind, res_name])

# Récupération du PodSpec selon le type de ressource
pod_spec := input.spec if input.kind == "Pod"

pod_spec := input.spec.template.spec if input.kind in workload_kinds

pod_spec := input.spec.jobTemplate.spec.template.spec if input.kind == "CronJob"

# Tous les conteneurs (containers + initContainers)
all_containers contains c if some c in pod_spec.containers

all_containers contains c if some c in pod_spec.initContainers

# Valeur de securityContext : le conteneur prime sur le pod
sc_value(c, key) := v if {
	v := c.securityContext[key]
} else := v if {
	v := pod_spec.securityContext[key]
}

# Image avec tag fixe ou digest (pas de :latest ni d'absence de tag)
image_is_pinned(img) if contains(img, "@")

image_is_pinned(img) if {
	parts := split(img, "/")
	last := parts[count(parts) - 1]
	contains(last, ":")
	not endswith(last, ":latest")
}

# ------------------------------------------------------------
# SERVICE
# ------------------------------------------------------------

deny contains msg if {
	input.kind == "Service"
	t := object.get(input.spec, "type", "ClusterIP")
	not t in allowed_service_types
	msg := sprintf("%s: le type de Service '%s' n'est pas autorisé (autorisés : %v)", [label, t, allowed_service_types])
}

deny contains msg if {
	input.kind == "Service"
	count(object.get(input.spec, "externalIPs", [])) > 0
	msg := sprintf("%s: spec.externalIPs est interdit (risque de détournement de trafic)", [label])
}

# ------------------------------------------------------------
# INGRESS
# ------------------------------------------------------------

warn contains msg if {
	input.kind == "Ingress"
	not input.spec.tls
	msg := sprintf("%s: aucun bloc TLS défini, le trafic sera en clair", [label])
}

# ------------------------------------------------------------
# POD-LEVEL (Pod, Deployment, StatefulSet, DaemonSet, Job, CronJob...)
# ------------------------------------------------------------

deny contains msg if {
	pod_spec.hostNetwork == true
	msg := sprintf("%s: hostNetwork est interdit", [label])
}

deny contains msg if {
	pod_spec.hostPID == true
	msg := sprintf("%s: hostPID est interdit", [label])
}

deny contains msg if {
	pod_spec.hostIPC == true
	msg := sprintf("%s: hostIPC est interdit", [label])
}

deny contains msg if {
	some v in pod_spec.volumes
	v.hostPath
	msg := sprintf("%s: le volume hostPath '%s' est interdit", [label, v.name])
}

warn contains msg if {
	pod_spec.automountServiceAccountToken != false
	msg := sprintf("%s: pensez à mettre automountServiceAccountToken: false si l'API Kubernetes n'est pas utilisée", [label])
}

warn contains msg if {
	not pod_spec.securityContext.seccompProfile
	msg := sprintf("%s: aucun seccompProfile défini (recommandé : RuntimeDefault)", [label])
}

# ------------------------------------------------------------
# CONTAINER-LEVEL (containers + initContainers)
# ------------------------------------------------------------

# Ne pas tourner en root
deny contains msg if {
	some c in all_containers
	sc_value(c, "runAsNonRoot") != true
	msg := sprintf("%s: le conteneur '%s' doit définir runAsNonRoot: true (au niveau pod ou conteneur)", [label, c.name])
}

deny contains msg if {
	some c in all_containers
	sc_value(c, "runAsUser") == 0
	msg := sprintf("%s: le conteneur '%s' ne doit pas utiliser runAsUser: 0", [label, c.name])
}

# Pas de conteneur privilégié
deny contains msg if {
	some c in all_containers
	c.securityContext.privileged == true
	msg := sprintf("%s: le conteneur '%s' ne doit pas être privileged", [label, c.name])
}

# Pas d'escalade de privilèges
deny contains msg if {
	some c in all_containers
	object.get(c, ["securityContext", "allowPrivilegeEscalation"], true) != false
	msg := sprintf("%s: le conteneur '%s' doit définir allowPrivilegeEscalation: false", [label, c.name])
}

# Système de fichiers en lecture seule
deny contains msg if {
	some c in all_containers
	object.get(c, ["securityContext", "readOnlyRootFilesystem"], false) != true
	msg := sprintf("%s: le conteneur '%s' doit définir readOnlyRootFilesystem: true", [label, c.name])
}

# Capabilities : drop ALL obligatoire
deny contains msg if {
	some c in all_containers
	drops := object.get(c, ["securityContext", "capabilities", "drop"], [])
	not "ALL" in drops
	msg := sprintf("%s: le conteneur '%s' doit supprimer toutes les capabilities (drop: [\"ALL\"])", [label, c.name])
}

# Capabilities ajoutées non autorisées
deny contains msg if {
	some c in all_containers
	some cap in object.get(c, ["securityContext", "capabilities", "add"], [])
	not cap in allowed_added_capabilities
	msg := sprintf("%s: le conteneur '%s' ajoute la capability interdite '%s'", [label, c.name, cap])
}

# hostPort interdit
deny contains msg if {
	some c in all_containers
	some p in c.ports
	p.hostPort
	msg := sprintf("%s: le conteneur '%s' utilise hostPort %v (interdit)", [label, c.name, p.hostPort])
}

# Image : tag fixe obligatoire (pas de :latest)
deny contains msg if {
	some c in all_containers
	not image_is_pinned(c.image)
	msg := sprintf("%s: l'image '%s' du conteneur '%s' doit avoir un tag fixe ou un digest (pas de :latest)", [label, c.image, c.name])
}

# Image : registre autorisé
deny contains msg if {
	count(allowed_registries) > 0
	some c in all_containers
	not any_registry_matches(c.image)
	msg := sprintf("%s: l'image '%s' ne provient pas d'un registre autorisé", [label, c.image])
}

any_registry_matches(img) if {
	some reg in allowed_registries
	startswith(img, reg)
}

# Resources : requests et limits obligatoires
deny contains msg if {
	some c in all_containers
	not c.resources.limits.cpu
	msg := sprintf("%s: le conteneur '%s' doit définir resources.limits.cpu", [label, c.name])
}

deny contains msg if {
	some c in all_containers
	not c.resources.limits.memory
	msg := sprintf("%s: le conteneur '%s' doit définir resources.limits.memory", [label, c.name])
}

deny contains msg if {
	some c in all_containers
	not c.resources.requests.cpu
	msg := sprintf("%s: le conteneur '%s' doit définir resources.requests.cpu", [label, c.name])
}

deny contains msg if {
	some c in all_containers
	not c.resources.requests.memory
	msg := sprintf("%s: le conteneur '%s' doit définir resources.requests.memory", [label, c.name])
}

# Probes (uniquement sur les vrais conteneurs, pas les initContainers ni les Jobs)
warn contains msg if {
	input.kind in {"Deployment", "StatefulSet", "DaemonSet"}
	some c in pod_spec.containers
	not c.livenessProbe
	msg := sprintf("%s: le conteneur '%s' n'a pas de livenessProbe", [label, c.name])
}

warn contains msg if {
	input.kind in {"Deployment", "StatefulSet", "DaemonSet"}
	some c in pod_spec.containers
	not c.readinessProbe
	msg := sprintf("%s: le conteneur '%s' n'a pas de readinessProbe", [label, c.name])
}

# Secrets en clair dans les variables d'environnement
warn contains msg if {
	some c in all_containers
	some e in c.env
	e.value
	regex.match(`(?i)(password|passwd|secret|token|api[_-]?key)`, e.name)
	msg := sprintf("%s: la variable '%s' du conteneur '%s' semble contenir un secret en clair (utilisez secretKeyRef)", [label, e.name, c.name])
}

# ------------------------------------------------------------
# WORKLOADS : bonnes pratiques
# ------------------------------------------------------------

warn contains msg if {
	input.kind == "Deployment"
	object.get(input.spec, "replicas", 1) < 2
	msg := sprintf("%s: moins de 2 replicas, pas de haute disponibilité", [label])
}

# ------------------------------------------------------------
# --- METADATA (toutes ressources) 
# ------------------------------------------------------------

deny contains msg if {
	input.kind in (workload_kinds | {"Pod", "CronJob", "Service", "Ingress"})
	object.get(input.metadata, "namespace", "default") == "default"
	msg := sprintf("%s: le namespace 'default' ne doit pas être utilisé", [label])
}

warn contains msg if {
	input.kind in (workload_kinds | {"Pod", "CronJob", "Service"})
	not input.metadata.labels["app.kubernetes.io/name"]
	msg := sprintf("%s: label 'app.kubernetes.io/name' manquant", [label])
}

# ------------------------------------------------------------
# RBAC
# ------------------------------------------------------------

deny contains msg if {
	input.kind in {"ClusterRoleBinding", "RoleBinding"}
	input.roleRef.name == "cluster-admin"
	msg := sprintf("%s: liaison au rôle cluster-admin interdite", [label])
}

deny contains msg if {
	input.kind in {"Role", "ClusterRole"}
	some rule in input.rules
	"*" in rule.verbs
	msg := sprintf("%s: verbe wildcard '*' interdit dans les règles RBAC", [label])
}

deny contains msg if {
	input.kind in {"Role", "ClusterRole"}
	some rule in input.rules
	"*" in rule.resources
	msg := sprintf("%s: ressource wildcard '*' interdite dans les règles RBAC", [label])
}