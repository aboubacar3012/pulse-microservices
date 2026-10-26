package main

import rego.v1

# ---------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------

# Numéro de ligne (StartLine si le parseur le fournit, sinon l'index)
line(i) := input[i].StartLine if input[i].StartLine
line(i) := i if not input[i].StartLine

# Toutes les commandes RUN, en minuscules : index -> commande
runs[i] := cmd if {
	some i, instr in input
	instr.Cmd == "run"
	cmd := lower(concat(" ", instr.Value))
}

# Alias des étages multi-stage (FROM x AS builder)
stage_aliases contains alias if {
	some instr in input
	instr.Cmd == "from"
	count(instr.Value) == 3
	lower(instr.Value[1]) == "as"
	alias := lower(instr.Value[2])
}

# ---------------------------------------------------------------
# Pas de secrets dans ENV / ARG
# ---------------------------------------------------------------

# Mots sans ambiguïté : recherche par sous-chaîne
secret_substrings := {"passwd", "password", "secret", "token", "apikey", "api_key", "accesskey", "credential", "private_key"}

# Mots courts : recherche par segment (PASS_FILE oui, PASSENGER non)
secret_tokens := {"pass", "pwd", "key", "tkn"}

is_secret(name) if {
	k := lower(name)
	some w in secret_substrings
	contains(k, w)
}

is_secret(name) if {
	some t in regex.split(`[_.\-]`, lower(name))
	t in secret_tokens
}

# ENV A=1 B=2 -> Value = [A, 1, B, 2] : les clés sont aux indices pairs
deny contains msg if {
	some i, instr in input
	instr.Cmd == "env"
	some j, key in instr.Value
	j % 2 == 0
	is_secret(key)
	msg := sprintf("Line %d: Potential secret in ENV key found: %s", [line(i), key])
}

# Les ARG sont visibles dans `docker history`
deny contains msg if {
	some i, instr in input
	instr.Cmd == "arg"
	name := split(instr.Value[0], "=")[0]
	is_secret(name)
	msg := sprintf("Line %d: Potential secret in ARG found: %s", [line(i), name])
}

# ---------------------------------------------------------------
# Images de base : pas de :latest, pas d'image sans tag
# ---------------------------------------------------------------

# Tag d'une image (undefined s'il n'y en a pas) ; gère registry:5000/img:tag
image_tag(ref) := tag if {
	parts := split(ref, "/")
	last := parts[count(parts) - 1]
	tp := split(last, ":")
	count(tp) == 2
	tag := tp[1]
}

# Références "réelles" (ni scratch, ni alias d'étage, ni digest épinglé)
checked_from(instr) := ref if {
	instr.Cmd == "from"
	ref := lower(instr.Value[0])
	ref != "scratch"
	not ref in stage_aliases
	not contains(ref, "@")
}

deny contains msg if {
	some i, instr in input
	ref := checked_from(instr)
	image_tag(ref) == "latest"
	msg := sprintf("Line %d: do not use 'latest' tag for base images", [line(i)])
}

# Sans tag = latest implicite
deny contains msg if {
	some i, instr in input
	ref := checked_from(instr)
	not contains(ref, "$") # FROM ${BASE_IMAGE} : non vérifiable
	not image_tag(ref)
	msg := sprintf("Line %d: base image '%s' has no tag (implicit 'latest')", [line(i), ref])
}

# ---------------------------------------------------------------
# Pas de "curl | bash"
# ---------------------------------------------------------------

interpreters := `((ba|da|z|k)?sh|python[0-9.]*|perl|ruby|node)`

deny contains msg if {
	some i, cmd in runs
	regex.match(sprintf(`\b(curl|wget)\b[^;&]*\|\s*(sudo\s+)?%s\b`, [interpreters]), cmd)
	msg := sprintf("Line %d: Avoid curl bashing (download piped to an interpreter)", [line(i)])
}

# sh -c "$(curl ...)" et bash <(curl ...)
deny contains msg if {
	some i, cmd in runs
	regex.match(sprintf(`\b%s\b[^|;&]*(\$\(|<\()\s*(curl|wget)\b`, [interpreters]), cmd)
	msg := sprintf("Line %d: Avoid curl bashing (command substitution)", [line(i)])
}

# ---------------------------------------------------------------
# Pas de mise à jour globale du système
# ---------------------------------------------------------------

upgrade_patterns := {
	`\b(apt|apt-get)\s+([^;&|]*\s)?(upgrade|dist-upgrade|full-upgrade)\b`,
	`\bapk\s+([^;&|]*\s)?upgrade\b`,
	`\b(yum|dnf|microdnf)\s+([^;&|]*\s)?(upgrade|update)\b`,
}

deny contains msg if {
	some i, cmd in runs
	some p in upgrade_patterns
	regex.match(p, cmd)
	msg := sprintf("Line %d: Do not upgrade your system packages", [line(i)])
}

# ---------------------------------------------------------------
# ADD -> COPY
# ---------------------------------------------------------------

warn contains msg if {
	some i, instr in input
	instr.Cmd == "add"
	msg := sprintf("Line %d: Use COPY instead of ADD", [line(i)])
}

# ---------------------------------------------------------------
# Utilisateur : un USER non-root dans l'étage FINAL
# ---------------------------------------------------------------

root_users := {"root", "toor", "0"}

last_from := max({i | some i, instr in input; instr.Cmd == "from"})

final_user_idx := max({i | some i, instr in input; instr.Cmd == "user"; i > last_from})

deny contains msg if {
	last_from >= 0
	not final_user_idx
	msg := "Do not run as root, use USER instead (no USER in the final stage)"
}

# Comparaison exacte sur la partie user de "user:group"
deny contains msg if {
	user := lower(split(input[final_user_idx].Value[0], ":")[0])
	user in root_users
	msg := sprintf("Line %d: Do not run as root: %s", [line(final_user_idx), user])
}

# ---------------------------------------------------------------
# sudo
# ---------------------------------------------------------------

deny contains msg if {
	some i, cmd in runs
	regex.match(`(^|[\s;&|(])sudo(\s|$)`, cmd)
	msg := sprintf("Line %d: Do not use 'sudo' command", [line(i)])
}

# ---------------------------------------------------------------
# Bonnes pratiques supplémentaires
# ---------------------------------------------------------------

deny contains msg if {
	some i, cmd in runs
	regex.match(`\bchmod\s+([^;&|]*\s)?(-r\s+)?(0?777|a\+rwx)\b`, cmd)
	msg := sprintf("Line %d: Avoid world-writable permissions (chmod 777)", [line(i)])
}

deny contains msg if {
	some i, instr in input
	instr.Cmd == "expose"
	some port in instr.Value
	regex.match(`^22(/(tcp|udp))?$`, port)
	msg := sprintf("Line %d: Do not expose SSH (port 22)", [line(i)])
}

warn contains msg if {
	some i, cmd in runs
	regex.match(`\bapt(-get)?\s+([^;&|]*\s)?install\b`, cmd)
	not contains(cmd, "--no-install-recommends")
	msg := sprintf("Line %d: Use --no-install-recommends with apt-get install", [line(i)])
}

warn contains msg if {
	last_from >= 0
	not has_healthcheck
	msg := "No HEALTHCHECK instruction found"
}

has_healthcheck if {
	some instr in input
	instr.Cmd == "healthcheck"
}