#!/bin/sh
# seed/node/release.sh -- build, start, check, stop and restore one Omega Node coding workflow
# (DRA-292). Every program it runs is compiled from .om; this script only composes sources, starts
# processes and reads their state. POSIX sh; no systemd.
#
#   release.sh build OUT
#       Compose and compile omnode-infer, omnode-tool, omnode-code (code-main), code-test, omnode-op
#       and fake-serve into OUT with this checkout's seed/out/omc; prints one sha256 line each.
#   release.sh serve STATE PORT OLLM VERB CK MERGES
#       Start the own-model server `OLLM VERB PORT CK MERGES` (VERB serve on the CPU, gserve on the
#       GB10 inside an authorized window) in this network namespace; STATE/serve.pid, serve.log.
#   release.sh start STATE BIN OMC PORT VIEW
#       Start omnode-code on STATE (root/, work/, journal/, objs.txt: one objective per line) with the
#       binaries in BIN, the compiler OMC whose messages the prompts carry, the model on 127.0.0.1:PORT
#       and the operator view on VIEW. Writes STATE/release.env and node.pid, appends run.out, and
#       waits until the view listens. Refuses (exit 3) while node.pid is alive.
#   release.sh health STATE
#       The model server's GET /health and the node's GET /view; exit 0 when both answer 200.
#   release.sh stop STATE
#       Pause through the view (op 1: nothing new is granted), wait until no job is running or in
#       review (at most 900 s), then SIGTERM the creator. Waiting jobs stay in the journal; a restore
#       cancels them and resumes each objective from the durable workspace.
#   release.sh restore STATE
#       Start again on the same journal and workspace (incarnation + 1). The journaled pause is
#       replayed, so restore then posts resume (op 2) and prints the view.
#   release.sh unserve STATE
#       SIGTERM the model server started by serve.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
die() { echo "release: $*" >&2; exit "${2:-1}"; }
alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }
env_load() { [ -f "$1/release.env" ] || die "no $1/release.env (start first)" 2; . "$1/release.env"; }
# the view's JSON has a fixed field order: the first "name": is the top-level, authority or queue
# field (incarnation, version, paused, running, review, journal_failed)
vfield() { grep -o "\"$2\":[0-9]*" "$1" | head -1 | cut -d: -f2; }
# the view answers 503 while the creator is between snapshots: retried for 5 s, written whole
view() {
	i=0
	until "$BIN/op" "$VIEW" view > "$1/view.tmp" 2> /dev/null; do
		i=$((i + 1)); [ $i -lt 50 ] || return 1
		sleep 0.1
	done
	mv "$1/view.tmp" "$1/view.json"
}
# post operator op $2 (1 pause, 2 resume) from a fresh view until it is committed; "invalid" is
# the node already in that state, "stale" a version that moved on (posted again)
post() {
	i=0
	while :; do
		view "$1" || return 1
		"$BIN/op" "$VIEW" cmd "$(date +%s%N | cut -c4-16)" "$2" 0 "$(vfield "$1/view.json" incarnation)" \
			"$(vfield "$1/view.json" version)" > "$1/ack.json"
		r=$?
		cat "$1/ack.json"
		[ $r = 0 ] || grep -q '"invalid"' "$1/ack.json" && return 0
		i=$((i + 1)); [ $i -lt 50 ] || return 1
		sleep 0.1
	done
}

build() {
	out=$1
	mkdir -p "$out"
	cd "$here" || exit 1
	N=seed/node A=seed/authority/action.om
	L="$N/transport.om $N/pool.om $N/super.om $N/sched.om $A $N/journal.om $N/auth.om"
	V="seed/net/http.om seed/net/notls.om $L $N/view.om"
	rc=0
	# shellcheck disable=SC2086
	for p in "infer:seed/json/json.om seed/json/jsonw.om seed/net/http.om seed/net/notls.om $N/infer.om" \
		"tool:seed/agent/path.om $N/gram.om $N/tool.om" \
		"code-main:$V $N/gram.om $N/code.om $N/code-main.om" \
		"code-test:$V $N/gram.om $N/code.om $N/code-test.om" \
		"op:seed/net/http.om seed/net/notls.om $N/op.om" \
		"fake-serve:seed/net/http.om seed/net/notls.om $N/tests/fake-serve.om"; do
		n=${p%%:*}
		{ printf 'om2\n'; cat ${p#*:}; } > "$out/$n.om" || exit 1
		if seed/out/omc < "$out/$n.om" > "$out/$n.tmp" 2> "$out/$n.cerr"; then
			chmod +x "$out/$n.tmp" && mv "$out/$n.tmp" "$out/$n"
			echo "BUILD_OK $n $(wc -c < "$out/$n") $(sha256sum "$out/$n" | cut -d' ' -f1)"
		else
			echo "BUILD_FAIL $n $(cat "$out/$n.cerr")"
			rm -f "$out/$n.tmp"
			rc=1
		fi
	done
	echo "omc $(sha256sum seed/out/omc | cut -d' ' -f1)"
	return $rc
}

serve() {
	st=$1 port=$2 ollm=$3 verb=$4 ck=$5 mg=$6
	[ "$port" != 18091 ] || die "never 18091" 2
	alive "$st/serve.pid" && die "a server is running (serve.pid $(cat "$st/serve.pid"))" 3
	mkdir -p "$st"
	: > "$st/serve.log"
	"$ollm" "$verb" "$port" "$ck" "$mg" >> "$st/serve.log" 2>&1 &
	echo $! > "$st/serve.pid"
	i=0
	until grep -q "^PORT $port" "$st/serve.log"; do
		alive "$st/serve.pid" || die "server exited: $(tail -3 "$st/serve.log")"
		i=$((i + 1)); [ $i -lt 3000 ] || die "no PORT line in 300 s"
		sleep 0.1
	done
	echo "serve pid $(cat "$st/serve.pid") port $port ollm $(sha256sum "$ollm" | cut -d' ' -f1) verb $verb"
}

run() {
	st=$1
	alive "$st/node.pid" && die "the node is running (node.pid $(cat "$st/node.pid"))" 3
	mkdir -p "$st/journal" "$st/work"
	n=$(grep -c '^RUN ' "$st/run.out" 2>/dev/null)
	echo "RUN ${n:-0} $(date -u +%FT%TZ)" >> "$st/run.out"
	# one objective per line, each one argument (tasks hold spaces)
	set --
	while IFS= read -r o; do set -- "$@" "$o"; done < "$st/objs.txt"
	"$BIN/code-main" "$BIN/infer" "$BIN/tool" "$OMC" "$st/root" "$st/work" "$st/journal" "$PORT" "$VIEW" "$@" \
		>> "$st/run.out" 2>> "$st/run.err" &
	echo $! > "$st/node.pid"
	i=0
	until "$BIN/op" "$VIEW" view > /dev/null 2>&1; do
		alive "$st/node.pid" || die "the node exited: $(tail -3 "$st/run.out")"
		i=$((i + 1)); [ $i -lt 300 ] || die "the view did not answer in 30 s"
		sleep 0.1
	done
	view "$st" || die "the view did not answer twice"
	echo "node pid $(cat "$st/node.pid") view $VIEW incarnation $(vfield "$st/view.json" incarnation) version $(vfield "$st/view.json" version)"
}

cmd=${1:-}
[ $# -ge 2 ] || die "usage: release.sh build OUT | serve STATE PORT OLLM VERB CK MERGES | start STATE BIN OMC PORT VIEW | health|stop|restore|unserve STATE" 2
case $cmd in
build) build "$2" ;;
serve) [ $# -eq 7 ] || die "usage: serve STATE PORT OLLM VERB CK MERGES" 2; serve "$2" "$3" "$4" "$5" "$6" "$7" ;;
start)
	[ $# -eq 6 ] || die "usage: start STATE BIN OMC PORT VIEW" 2
	[ "$5" != 18091 ] && [ "$6" != 18091 ] || die "never 18091" 2
	st=$2
	mkdir -p "$st"
	printf 'BIN=%s\nOMC=%s\nPORT=%s\nVIEW=%s\n' "$(cd "$3" && pwd)" "$4" "$5" "$6" > "$st/release.env"
	env_load "$st"
	run "$st" ;;
health)
	st=$2; env_load "$st"
	"$BIN/op" "$PORT" health > "$st/health.json"; m=$?
	view "$st"; v=$?
	echo "model $m $(cat "$st/health.json") node $v incarnation $(vfield "$st/view.json" incarnation) running $(vfield "$st/view.json" running) journal_failed $(vfield "$st/view.json" journal_failed)"
	[ $m = 0 ] && [ $v = 0 ] ;;
stop)
	st=$2; env_load "$st"
	alive "$st/node.pid" || die "the node is not running" 3
	post "$st" 1 || die "the pause was not committed"
	i=0
	while :; do
		if view "$st"; then
			[ "$(vfield "$st/view.json" running)" = 0 ] && [ "$(vfield "$st/view.json" review)" = 0 ] && break
		else
			alive "$st/node.pid" || die "the node exited while stopping"
		fi
		i=$((i + 1)); [ $i -lt 9000 ] || die "jobs still running after 900 s; not stopped"
		sleep 0.1
	done
	cp "$st/view.json" "$st/view-at-stop.json"
	p=$(cat "$st/node.pid")
	kill -TERM "$p" 2>/dev/null
	while kill -0 "$p" 2>/dev/null; do sleep 0.1; done
	echo "stopped pid $p running $(vfield "$st/view-at-stop.json" running) waiting $(vfield "$st/view-at-stop.json" waiting) ready $(vfield "$st/view-at-stop.json" ready)" ;;
restore)
	st=$2; env_load "$st"
	run "$st" || exit $?
	if [ "$(vfield "$st/view.json" paused)" = 1 ]; then
		post "$st" 2 || die "the resume was not committed"
		echo
	fi
	view "$st" || die "the view does not answer"
	echo "restored incarnation $(vfield "$st/view.json" incarnation) paused $(vfield "$st/view.json" paused)" ;;
unserve)
	st=$2
	alive "$st/serve.pid" || die "no server running" 3
	p=$(cat "$st/serve.pid")
	kill -TERM "$p"
	while kill -0 "$p" 2>/dev/null; do sleep 0.1; done
	echo "server $p stopped" ;;
*) die "unknown command $cmd" 2 ;;
esac
