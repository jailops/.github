#!/usr/bin/env bash
# Puts the same repository settings on every jailops repository: what a repository has switched off (wiki, projects,
# merge commits, rebase merges), what it has switched on (squash merges, deleted branches after a merge, alerts,
# secret scanning with push protection, private vulnerability reporting) and what its workflows may do by default (read
# the contents, nothing else; a fork's pull request waits for approval). The rulesets (pull request, signed commits,
# green checks, frozen release tags) are scripts/apply-rulesets.sh. Run it yourself, with a token that may administer
# the repositories:
#
#   scripts/apply-settings.sh            show what would be sent
#   scripts/apply-settings.sh --apply    send it
#   scripts/apply-settings.sh --apply jailops-recipes      only these repositories
#
# Safe to repeat: every call sets a value, none adds. A setting a repository's plan does not have is reported and the
# run goes on. The merge setting `allow_auto_merge` is left alone: jailops-packages merges its own bump pull requests
# with it. Environments (signing, source, github-pages) and secrets are not here: docs/supply-chain.md of
# jailops-packages lists them.
set -euo pipefail
cd "$(dirname "$0")/.."
org=jailops
apply=0
if [ "${1:-}" = "--apply" ]; then apply=1; shift; fi
command -v jq >/dev/null || { echo "x jq is needed" >&2; exit 1; }
[ $apply -eq 0 ] || command -v gh >/dev/null || { echo "x gh is needed to apply" >&2; exit 1; }

repos=("$@")
[ ${#repos[@]} -gt 0 ] || repos=(jailops jailops-pkgops jailops-packages jailops-recipes .github)

# the facts of each repository that the others do not share: its description and topics (empty: leave them)
description() {
	case $1 in
	jailops-recipes) echo "Practical recipes for FreeBSD jails: set up, harden, back up and run your services with JailOps." ;;
	esac
}
homepage() {
	case $1 in
	jailops-recipes) echo "https://jailops.net/recipe-book/" ;;
	esac
}
topics() {
	case $1 in
	jailops-recipes) echo "freebsd jails jailops recipes infrastructure devops sysadmin configuration-management postgresql nginx" ;;
	esac
}

failed=""
call() { # call REPO METHOD PATH [JSON]: show the call, or send it; a refusal is reported and the run goes on
	local repo=$1 method=$2 path=$3 json=${4:-} out
	local url="repos/$org/$repo${path:+/$path}"
	if [ $apply -eq 0 ]; then
		printf '  %s %s %s\n' "$method" "$url" "$(printf '%s' "$json" | jq -c . 2>/dev/null || true)"
		return 0
	fi
	if [ -n "$json" ]; then
		out=$(printf '%s' "$json" | gh api --method "$method" "$url" --input - 2>&1) || {
			echo "  x $method ${path:-the repository}: $(printf '%s' "$out" | jq -r '.message // .' 2>/dev/null || printf '%s' "$out")" >&2
			failed="$failed $repo"
			return 0
		}
	else
		out=$(gh api --method "$method" "$url" 2>&1) || {
			echo "  x $method ${path:-the repository}: $(printf '%s' "$out" | jq -r '.message // .' 2>/dev/null || printf '%s' "$out")" >&2
			failed="$failed $repo"
			return 0
		}
	fi
	echo "  ok $method ${path:-the repository}"
}

# Only rulesets protect a branch here (scripts/apply-rulesets.sh), never the classic branch protection rules: a classic rule on the
# default branch is reported (it is not removed for you) so that the two never overlap.
classic_rule() { # classic_rule REPO: say so when the default branch has a classic protection rule
	[ $apply -eq 1 ] || return 0
	local branch
	branch=$(gh api "repos/$org/$1" --jq .default_branch 2>/dev/null) || return 0
	if gh api "repos/$org/$1/branches/$branch/protection" >/dev/null 2>&1; then
		echo "  ! $branch has a classic branch protection rule: delete it (Settings, Branches), the ruleset master-protection replaces it" >&2
	fi
}

for repo in "${repos[@]}"; do
	echo "$repo:"
	# the repository itself: issues stay (people ask and propose there), the rest of the side bar goes; one way to merge
	patch=$(jq -n '{
		has_issues: true, has_projects: false, has_wiki: false, has_discussions: false,
		allow_squash_merge: true, allow_merge_commit: false, allow_rebase_merge: false,
		delete_branch_on_merge: true, allow_update_branch: true, web_commit_signoff_required: false,
		security_and_analysis: {
			secret_scanning: {status: "enabled"},
			secret_scanning_push_protection: {status: "enabled"}
		}
	}')
	d=$(description "$repo"); h=$(homepage "$repo")
	[ -z "$d" ] || patch=$(printf '%s' "$patch" | jq --arg d "$d" '. + {description: $d}')
	[ -z "$h" ] || patch=$(printf '%s' "$patch" | jq --arg h "$h" '. + {homepage: $h}')
	call "$repo" PATCH "" "$patch"
	t=$(topics "$repo")
	[ -z "$t" ] || call "$repo" PUT topics "$(printf '%s\n' $t | jq -R . | jq -s '{names: .}')"
	# alerts about vulnerable dependencies (not version-update pull requests), and a private way to report a vulnerability
	call "$repo" PUT vulnerability-alerts
	call "$repo" PUT private-vulnerability-reporting
	# what the workflows may do by default: read the contents; they cannot approve pull requests; a fork's pull request
	# waits for approval of a person (every external contributor)
	# can_approve_pull_request_reviews is also the switch "Actions may open pull requests": jailops-packages needs it on (its
	# check-updates workflow opens the bump pull requests), every other repository has it off
	approve=false; [ "$repo" != jailops-packages ] || approve=true
	call "$repo" PUT actions/permissions/workflow "{\"default_workflow_permissions\":\"read\",\"can_approve_pull_request_reviews\":$approve}"
	call "$repo" PUT actions/permissions/fork-pr-contributor-approval '{"approval_policy":"all_external_contributors"}'
	classic_rule "$repo"
done
[ $apply -eq 1 ] || echo "(nothing sent: add --apply)"
[ -z "$failed" ] || { echo "x some settings were refused for:$failed (see above)" >&2; exit 1; }
