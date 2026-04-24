# OptimistXL vs. Optimist: A Comparison

A side-by-side look at `optimist_xl` and the upstream `optimist` gem it was forked from, plus a frank assessment of the trade-offs.

*Reference versions: `optimist_xl` 3.3.0 (released 2020-11-12) vs. `optimist` 3.2.1 (released 2025-03-19).*

## TL;DR

When OptimistXL was forked in early 2020, it carried a handful of features upstream Optimist lacked. Between 2023 and 2024, most of those features (written by the same author, `@nanobowers`) were merged back into upstream Optimist. Today, the feature gap has narrowed sharply in the *other* direction:

* **XL-only features still worth having:** subcommands (`subcmd`) and the `:stringflag` option type.
* **Upstream-only features XL is missing:** the `either` constraint, help-output column alignment, frozen-string-literal support, and a clean `Constraint` class refactor.
* **Upstream advantage:** actively maintained (last release 2025), tested against Ruby 2.7-3.4 + JRuby; XL has not had a release in >5 years and its CI config references Travis with Ruby 2.3-2.7.

If you don't need subcommands or `:stringflag`, upstream Optimist is the better choice in 2026. If you do need them, XL still has a niche — but weigh it against the maintenance risk.

## Origin

OptimistXL was forked from Optimist at v3.0.1 in January 2020 by Ben Bowers (`@nanobowers`). At the time, upstream Optimist had been quiet since the 2018 rename from "Trollop" and v3.0.0. The fork added several features at once (subcommands, inexact matching, suggestions, permitted values, short-option arrays, alt long-names) that the upstream project was not accepting at that pace.

Upstream subsequently picked up speed: Optimist 3.1.0 (2023), 3.2.0 (2024), and 3.2.1 (2025) accepted PRs from `@nanobowers` (among others) that brought most of the fork's feature set back into the mainline.

## Feature matrix

| Feature | optimist_xl 3.3.0 | optimist 3.2.1 | Notes |
|---|:-:|:-:|---|
| `opt :name, :type => :flag` (boolean) | Yes | Yes | Core; identical |
| `:string`, `:integer`, `:float`, `:io`, `:date` types | Yes | Yes | Same registry-based design; derived from Optimist 2.1.3 |
| Array types (`:strings`, `:ints`, `:floats`, etc.) | Yes | Yes | Identical |
| `:required`, `:multi`, `:default`, `:callback` | Yes | Yes | Identical |
| `depends` / `conflicts` constraints | Yes | Yes | Identical semantics; upstream uses dedicated `Constraint` classes |
| `either` constraint (require exactly one) | **No** | **Yes** | Added in Optimist 3.1.0 |
| `:permitted` + `:permitted_response` | Yes | Yes | XL had first (3.1.1); upstream added in 3.2.0 |
| Permitted as Array / Range / Regexp | Yes | Yes | Both support all three |
| Inexact long-option matching | Yes (`exact_match: false` default) | Yes (`exact_match: false` default) | XL added 3.1.1; upstream 3.2.0. Defaults match. |
| DidYouMean suggestions | Yes (`suggestions: true`) | Yes (`suggestions: true`) | XL added 3.1.1; upstream 3.2.0. Identical code path. |
| `alt:` for long-option aliases | Yes (3.2.0) | Yes (3.2.0) | Same PR from `@nanobowers` landed in both |
| `short:` accepting an Array of chars | Yes (3.2.0) | Yes (3.2.0) | Same PR |
| Disable auto short-opts globally | `explicit_short_opts: false` (default) | `implicit_short_opts: true` (default) | **Same feature, opposite naming convention.** Not source-compatible. |
| `:stringflag` option type | **Yes** (3.3.0) | **No** | XL-exclusive. Tri-state: unset / flagged-with-default / string-value. |
| Git-style `subcmd` / `SubcommandParser` | **Yes** (3.1.1) | **No** | XL-exclusive. Upstream users work around this with `stop_on` + a second `Parser`. |
| Help output aligns short/long into columns | No | **Yes** (3.2.0) | Minor but visible in `--help` output |
| `frozen_string_literal` compatibility | No | **Yes** (3.2.0) | XL will fail on frozen-string Rubies in places upstream has fixed |
| Negative-flag output correctness | Has upstream bug | **Fixed** (3.2.1, #179) | XL still contains the pre-fix code |
| JRuby 10 / frozen-string JRuby fixes | No | **Yes** (3.2.1, #180) | |

## Where the two are interface-compatible

For the overlapping feature set, the DSL is effectively identical — `opt`, `version`, `banner`, `depends`, `conflicts`, `stop_on`, `stop_on_unknown`, `educate_on_error`, and the module-level `options` / `die` / `educate` / `with_standard_exception_handling` all look the same. Migrating XL code to upstream Optimist (or vice-versa) is mostly a module-name swap (`OptimistXL` ⇄ `Optimist`).

## Where they diverge

### `explicit_short_opts` vs. `implicit_short_opts`

Same feature, inverted flag:

```ruby
# optimist_xl: turn OFF auto-generated short options
OptimistXL::Parser.new(explicit_short_opts: true) { ... }

# optimist: turn OFF auto-generated short options
Optimist::Parser.new(implicit_short_opts: false) { ... }
```

A mechanical migration has to translate this setting rather than copy it verbatim.

### Subcommands (XL-exclusive)

XL provides first-class subcommand support via `subcmd`:

```ruby
opts = OptimistXL.options do
  opt :verbose, "Talk more"
  subcmd "push", "Push changes" do
    opt :force, "Force push"
  end
end

# opts is a SubcommandResult carrying the chosen subcommand name + its opts
```

See `examples/subcommands.rb` in the XL repo. Upstream Optimist has no equivalent; the documented pattern is to use `stop_on` with a list of subcommand names, then instantiate a second parser per subcommand. That pattern works but it leaves you to wire help output, `--help subcommand`, and error handling by hand.

### `:stringflag` (XL-exclusive)

A tri-state string option that can also behave as a flag:

```ruby
opt :log, "Log file", :type => :stringflag, :default => "app.log"

# unset         -> {log: "app.log"}             (default used, :log_given absent)
# --log         -> {log: "app.log", log_given: true}   (default used, flag given)
# --log foo.log -> {log: "foo.log", log_given: true}   (explicit value)
# --no-log      -> {log: false,     log_given: true}   (disabled)
```

Useful when a flag has a sensible default filename but the user may want to override or disable it. Not present upstream; closest upstream workaround is a `:string` option with a non-nil default, but that loses the `--no-log` and bare-flag behaviors.

### `either` (upstream-exclusive)

Upstream Optimist 3.1.0 added a mutual-exclusion-with-requirement constraint:

```ruby
opt :read,  "Read mode"
opt :write, "Write mode"
either :read, :write  # exactly one must be given
```

XL users have to simulate this with `conflicts` + a post-parse `die` check.

### Internal design

* **Constraints.** Upstream refactored `depends` / `conflicts` / `either` into a `Constraint` class hierarchy (`DependConstraint`, `ConflictConstraint`, `EitherConstraint`) in 3.2.0. XL still stores them as `[:depends, syms]` tuples in `@constraints`. Functionally equivalent for the features both support, but the upstream code is cleaner to extend.
* **Help output.** Upstream 3.2.0 aligns `-s, --long` pairs into proper columns. XL still uses the older single-column layout.
* **Frozen strings.** Upstream is frozen-string-literal-safe across the file. XL has no `# frozen_string_literal:` pragmas and mutates strings in several places that would break under `--enable-frozen-string-literal`.

## Downsides of going with OptimistXL

These are the real risks, not marketing:

* **Maintenance is effectively stalled.** The last gem release was 3.3.0 on 2020-11-12. The last commit on master is from 2024-11-11 (merging a contributor PR). Upstream cut two releases in 2024-2025 and fixes bugs regularly. For a dependency you expect to carry through the next few Ruby versions, that's a meaningful risk.
* **No Ruby 3.x CI.** `.travis.yml` tests 2.3-2.7 on a CI provider (Travis) that has been unusable for open-source since 2021. There is no GitHub Actions replacement. The gem *probably* works on Ruby 3.x, but nobody is verifying it on every change.
* **Frozen-string bugs.** Upstream has specifically patched places where string mutation fails on frozen-string Rubies (JRuby 10, future Ruby with default-frozen literals). XL has not.
* **Known upstream fixes missing.** The negative-boolean-flag output fix (upstream #179, 3.2.1) hasn't been backported.
* **The feature pitch is out of date.** XL's README still lists "Extended features unavailable in the original Optimist gem" for features that *are* now in the original Optimist gem (permitted, suggestions, inexact matching, alt names, Array shorts). Only `subcmd` and `:stringflag` remain truly XL-exclusive.
* **Single-maintainer.** Upstream has multiple active maintainers under ManageIQ (`@Fryguy`, `@kbrock`, `@nanobowers`, `@akhoury6`). XL is a solo project.
* **Dev dep is old.** `minitest "~> 5.4.3"` pins to 2014-era Minitest; upstream uses `~> 5.25`. Not a runtime concern but signals the dev environment hasn't been touched in a long time.
* **Switching later is non-trivial if you use subcommands.** The `Optimist` ⇄ `OptimistXL` module name is mechanical, but replacing `subcmd` with a hand-rolled `stop_on` pattern isn't. Committing to XL for subcommands means you're committing to XL.

## When XL is still the right call

* You need `subcmd` and don't want to roll subcommand handling by hand.
* You specifically want the `:stringflag` tri-state behavior.
* You're already running XL in production on a stable Ruby version and the upgrade cost outweighs the maintenance risk.

## When to prefer upstream Optimist

* You're starting a new project in 2026.
* You don't need subcommands (or you're happy to use `stop_on` + a second `Parser`).
* You want `either` or aligned help output.
* You care about Ruby 3.x / JRuby 10 / frozen-string-literal safety.
* You want a dependency under active maintenance.

## A note on the fork's trajectory

Several of the features XL pioneered were upstreamed by the same author who maintains XL. That's a sign that the fork served its purpose — it was a fast lane to prove out new ideas while the upstream project's release cadence was slower. With upstream now releasing steadily, the case for maintaining a parallel fork is weaker, and the practical outcome is that XL has drifted behind on fixes its own author wrote for upstream.

If you're auditing an existing codebase's use of XL, the most useful question is: *is the subcommand or stringflag support load-bearing?* If yes, stay on XL and pin aggressively. If no, plan a migration to upstream.
