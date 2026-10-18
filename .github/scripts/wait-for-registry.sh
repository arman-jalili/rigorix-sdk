#!/usr/bin/env bash
# ============================================================================
# wait-for-registry.sh — wait for a just-published artifact to become visible
#
# Usage:
#   .github/scripts/wait-for-registry.sh <pypi|npm> <command> [args...]
#
# Env:
#   REGISTRY_MAX_ATTEMPTS   default 45   (45 x 20s = 15 minutes)
#   REGISTRY_RETRY_SECONDS  default 20
#
# Exit:
#   0  the command succeeded (artifact visible and installable)
#   2  artifact is VISIBLE but the command failed for a non-propagation reason
#   3  PROPAGATION TIMEOUT — still not visible after the window (published,
#      smoke unverified)
#
# Only "not yet visible" errors are retried. Any other failure fails fast, so a
# real post-publish defect is not masked by a long retry loop. This script runs
# only the command it is given (read/install); it never publishes.
# ============================================================================
set -uo pipefail

ecosystem="${1:-}"
if [[ "$ecosystem" != "pypi" && "$ecosystem" != "npm" ]]; then
	echo "usage: $0 <pypi|npm> <command> [args...]" >&2
	exit 64
fi
shift
if [[ $# -eq 0 ]]; then
	echo "usage: $0 <pypi|npm> <command> [args...]" >&2
	exit 64
fi

max_attempts="${REGISTRY_MAX_ATTEMPTS:-45}"
retry_seconds="${REGISTRY_RETRY_SECONDS:-20}"

case "$ecosystem" in
pypi)
	# pip's "this version is not on the index yet" signatures, plus transient
	# CDN/network failures. A visible-but-broken wheel produces other errors
	# (build failure, metadata conflict) and is not retried.
	retryable='No matching distribution found|Could not find a version that satisfies|404 Client Error|503 Service Unavailable|Read timed out|Connection reset|Connection aborted|Temporary failure in name resolution|NewConnectionError'
	;;
npm)
	# ETARGET / E404 / "No matching version found" = the version has not
	# propagated yet; the rest are transient transport failures. ERESOLVE,
	# EINTEGRITY and tarball errors mean the artifact IS visible but broken.
	retryable='ETARGET|No matching version found|E404|404 Not Found|ETIMEDOUT|ECONNRESET|ECONNREFUSED|EAI_AGAIN|ENOTFOUND|network timeout|socket hang up'
	;;
esac

window=$((max_attempts * retry_seconds))
attempt=0
output=""

while ((attempt < max_attempts)); do
	attempt=$((attempt + 1))

	if output="$("$@" 2>&1)"; then
		printf '%s\n' "$output"
		echo "✅ registry-visible: ${ecosystem} succeeded on attempt ${attempt}/${max_attempts}"
		exit 0
	fi

	if ! printf '%s' "$output" | grep -Eq "$retryable"; then
		echo "::error title=Registry artifact is visible but broken::${ecosystem} install failed for a non-propagation reason (not retrying)" >&2
		printf '%s\n' "$output" >&2
		if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
			{
				echo "### ❌ Registry artifact visible but broken"
				echo ""
				echo "\`${ecosystem}\` install failed for a reason other than propagation — this is a real artifact defect, not a timing issue."
			} >>"$GITHUB_STEP_SUMMARY"
		fi
		exit 2
	fi

	echo "⏳ attempt ${attempt}/${max_attempts}: ${ecosystem} not yet visible; retrying in ${retry_seconds}s"
	if ((attempt < max_attempts)); then
		sleep "$retry_seconds"
	fi
done

echo "::error title=Registry propagation timeout::artifacts were published, but ${ecosystem} did not serve them within ${window}s — PROPAGATION TIMEOUT, smoke UNVERIFIED (not a bad artifact)" >&2
printf '%s\n' "$output" >&2
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
	{
		echo "### ⏳ Registry propagation timeout (smoke unverified)"
		echo ""
		echo "Artifacts were published, but \`${ecosystem}\` did not serve them within ${window}s."
		echo "This is **not** a bad artifact. Re-run only the smoke job — it does not re-publish."
	} >>"$GITHUB_STEP_SUMMARY"
fi
exit 3
