#!/usr/bin/env bats

# Tests for bin/gh_actions_cost.sh. What they pin down is the verdict: a
# forecast that under-counts reads as "ok" all month and the bill arrives
# anyway, and one that counts public repos warns about minutes that are free.
# Repo names and numbers here are made up; real usage never goes in this repo.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/bin/gh_actions_cost.sh"
    TMP="$(mktemp -d)"
    export GH_ACTIONS_COST_USAGE_JSON="$TMP/usage.json"
    export GH_ACTIONS_COST_REPOS_JSON="$TMP/repos.json"
    export GH_ACTIONS_COST_JOBS_JSON="$TMP/jobs.json"
    cat >"$GH_ACTIONS_COST_REPOS_JSON" <<'EOF'
[{"name":"secret-app","isPrivate":true},{"name":"open-lib","isPrivate":false}]
EOF
}

teardown() {
    rm -rf "$TMP"
}

# usage_items REPO:DAY:MINUTES ... — Linux minutes at the Linux rate.
usage_items() {
    local items=() r d m
    for spec in "$@"; do
        IFS=: read -r r d m <<<"$spec"
        items+=("$(jq -cn --arg r "$r" --arg d "2030-04-${d}T00:00:00Z" --argjson m "$m" \
            '{date: $d, product: "actions", sku: "Actions Linux", unitType: "Minutes",
              quantity: $m, grossAmount: ($m * 0.006), repositoryName: $r}')")
    done
    local IFS=,
    echo "{\"usageItems\":[${items[*]}]}" >"$GH_ACTIONS_COST_USAGE_JSON"
}

@test "forecast: a pace that ends the month under the plan is ok" {
    usage_items secret-app:01:50 secret-app:02:50
    GH_ACTIONS_COST_TODAY=2030-04-03 run "$SCRIPT" forecast someone
    [ "$status" -eq 0 ]
    [[ "$output" == *"projected month-end: 1500 (50% of included)"* ]]
    [[ "$output" == *"status: ok"* ]]
}

@test "forecast: a pace just under the plan stays quiet" {
    # 90% is a normal month here; warning on it would warn every day.
    usage_items secret-app:01:90 secret-app:02:90
    GH_ACTIONS_COST_TODAY=2030-04-03 run "$SCRIPT" forecast someone
    [ "$status" -eq 0 ]
    [[ "$output" == *"(90% of included)"* ]]
}

@test "forecast: a pace that runs out warns with exit 1 and names the day" {
    usage_items secret-app:01:150 secret-app:02:150
    GH_ACTIONS_COST_TODAY=2030-04-03 run "$SCRIPT" forecast someone
    [ "$status" -eq 1 ]
    [[ "$output" == *"projected month-end: 4500"* ]]
    [[ "$output" == *"run out on day 20 of 30"* ]]
    [[ "$output" == *"status: WARN"* ]]
}

@test "forecast: public repo minutes are free and never count" {
    usage_items secret-app:01:10 open-lib:01:5000 open-lib:02:5000
    GH_ACTIONS_COST_TODAY=2030-04-03 run "$SCRIPT" forecast someone
    [ "$status" -eq 0 ]
    [[ "$output" == *"used 10 of 3000"* ]]
    [[ "$output" != *"open-lib"* ]]
}

@test "forecast: today's partial day is shown as used but not projected" {
    # A burst this morning would otherwise be stretched over the whole month.
    usage_items secret-app:01:30 secret-app:02:30 secret-app:03:900
    GH_ACTIONS_COST_TODAY=2030-04-03 run "$SCRIPT" forecast someone
    [ "$status" -eq 0 ]
    [[ "$output" == *"used 960 of 3000"* ]]
    [[ "$output" == *"projected month-end: 900 "* ]]
}

@test "forecast: on day 1 there is nothing to project" {
    usage_items secret-app:01:500
    GH_ACTIONS_COST_TODAY=2030-04-01 run "$SCRIPT" forecast someone
    [ "$status" -eq 0 ]
    [[ "$output" == *"too early"* ]]
}

@test "forecast: broken input exits 2, not the warning code" {
    echo 'not json' >"$GH_ACTIONS_COST_USAGE_JSON"
    GH_ACTIONS_COST_TODAY=2030-04-03 run "$SCRIPT" forecast someone
    [ "$status" -eq 2 ]
}

@test "breakdown: each job is billed rounded up to a whole minute" {
    cat >"$GH_ACTIONS_COST_JOBS_JSON" <<'EOF'
[
 {"workflow":"CI","job":"lint","started_at":"2030-04-01T00:00:00Z","completed_at":"2030-04-01T00:00:05Z"},
 {"workflow":"CI","job":"lint","started_at":"2030-04-02T00:00:00Z","completed_at":"2030-04-02T00:00:05Z"},
 {"workflow":"CI","job":"test","started_at":"2030-04-01T00:00:00Z","completed_at":"2030-04-01T00:01:01Z"}
]
EOF
    run "$SCRIPT" breakdown someone/secret-app 2030-04-01
    [ "$status" -eq 0 ]
    # 61 s → 2 billed; two 5 s jobs → 2 billed, 91% of it rounding.
    [[ "$output" == *$'2\t1\t49%\t1\tCI / test'* ]]
    [[ "$output" == *$'2\t0\t91%\t2\tCI / lint'* ]]
}

@test "no subcommand prints usage and exits 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"forecast"* ]]
}
