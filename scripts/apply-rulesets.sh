#!/usr/bin/env bash
# Puts the same repository rulesets on every jailops repository: one on the default branch (pull request, signed
# commits, green checks, no force-push, no deletion) and one that freezes release tags. Run it yourself, with a token that
# may administer the repositories:
#
#   scripts/apply-rulesets.sh            show what would be sent
#   scripts/apply-rulesets.sh --apply    create or update the rulesets
#   scripts/apply-rulesets.sh --apply jailops jailops-web      only these repositories
#
# Safe to repeat: a ruleset with the same name is updated, never duplicated. The required checks are the job names of
# each repository's workflow (they change when a job is renamed: change them here too).
set -euo pipefail
cd "$(dirname "$0")/.."
org=jailops
apply=0
if [ "${1:-}" = "--apply" ]; then apply=1; shift; fi
command -v jq >/dev/null || { echo "x jq is needed" >&2; exit 1; }
[ $apply -eq 0 ] || command -v gh >/dev/null || { echo "x gh is needed to apply" >&2; exit 1; }

checks() { # the job names that must be green before a pull request can merge
	case $1 in
	jailops) printf '%s\n' "Web consoles (build)" "Web consoles (types, unit tests, end-to-end)" \
		"Go (format, vet, build, types, SDK)" "Go fuzz" \
		"Go race detector (a)" "Go race detector (b)" "Go race detector (c)" "Go race detector (rest)" \
		"Cross-build (FreeBSD) (amd64)" "Cross-build (FreeBSD) (arm64)" \
		"FreeBSD VM (go)" "FreeBSD VM (e2e)" "FreeBSD VM (pf)" ;;
	jailops-pkgops) printf '%s\n' "build and test (Linux)" "web UI (build, unit tests, e2e)" ;;
	jailops-freebsd) printf '%s\n' "build and test (Linux)" ;;
	jailops-web) printf '%s\n' "Build and check" ;;
	jailops-packages) printf '%s\n' "build" ;;
	.github) ;; # no workflows: nothing to wait for
	*) return 1 ;;
	esac
}

put() { # put REPO NAME JSON: create the ruleset, or update the one that has this name
	local repo=$1 name=$2 json=$3 list id
	# gh prints the error body on stdout when a call fails: keep the status, and take an id only when it is a number
	if ! list=$(gh api "repos/$org/$repo/rulesets" 2>&1); then
		echo "  x cannot read the rulesets of $repo: $(printf '%s' "$list" | jq -r '.message // .' 2>/dev/null || printf '%s' "$list")" >&2
		return 1
	fi
	id=$(printf '%s' "$list" | jq -r --arg n "$name" '.[] | select(.name == $n) | .id')
	case $id in
	"") echo "$json" | gh api --method POST "repos/$org/$repo/rulesets" --input - >/dev/null && echo "  created $name" ;;
	*[!0-9]*) echo "  x unexpected ruleset id '$id' for $name" >&2; return 1 ;;
	*) echo "$json" | gh api --method PUT "repos/$org/$repo/rulesets/$id" --input - >/dev/null && echo "  updated $name" ;;
	esac
}

failed=""
repos=("$@")
[ ${#repos[@]} -gt 0 ] || repos=(jailops jailops-pkgops jailops-freebsd jailops-web jailops-packages .github)
for repo in "${repos[@]}"; do
	contexts=$(checks "$repo") || { echo "x unknown repository $repo" >&2; exit 1; }
	n=$(printf '%s' "$contexts" | grep -c . || true)
	if [ "$n" -gt 0 ]; then
		branch=$(jq --argjson c "$(printf '%s\n' "$contexts" | jq -R . | jq -s 'map({context: .})')" \
			'(.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks) = $c' rulesets/branch.json)
	else # a repository without workflows has no check to require
		branch=$(jq '.rules |= map(select(.type != "required_status_checks"))' rulesets/branch.json)
	fi
	echo "$repo: $n required checks"
	if [ $apply -eq 1 ]; then
		put "$repo" master-protection "$branch" && put "$repo" release-tags "$(cat rulesets/tags.json)" || failed="$failed $repo"
	else
		printf '%s\n' "$branch" | jq -c '{name, rules: [.rules[].type]}'
	fi
done
[ $apply -eq 1 ] || echo "(nothing sent: add --apply)"
[ -z "$failed" ] || { echo "x not applied to:$failed" >&2; exit 1; }
