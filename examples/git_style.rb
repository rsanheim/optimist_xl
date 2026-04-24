#!/usr/bin/env ruby
# examples/git_style.rb
#
# Demonstrates building a git-style CLI with OptimistXL. Covers:
#
#   * Global options that come BEFORE the subcommand name
#   * First-level subcommands via `subcmd`
#   * Nested subcommands via a second `Parser` on leftovers
#   * Long/short/equals/negated forms all out of the box
#   * Inexact long-option matching (git-style abbreviation)
#   * `--` to separate options from positional args
#   * `alt:` for long-option synonyms (e.g. --message / --msg)
#   * `permitted:` for enum-like values
#   * DidYouMean suggestions for typos
#
# Not shown (XL limitations vs. real git):
#   * Counting `-v -v -v` to raise a verbosity level — XL booleans are on/off
#     only; you'd need an integer opt and parse `-vvv` yourself.
#   * Attached short values like `git log -n10` — XL reads `-n10` as combined
#     flags `-n -1 -0`. Require `-n 10` instead.
#   * Subcommand abbreviation (`git co` → `checkout`) — inexact matching
#     applies to long options, not subcommand names.
#   * Multi-level nesting beyond what's shown in `remote` — each level needs
#     its own Parser (the pattern scales, it's just not automatic).
#
# Try these invocations to see each feature:
#
#   ./git_style.rb --help
#   ./git_style.rb commit --help
#   ./git_style.rb remote --help
#   ./git_style.rb remote add --help
#
#   # Long option, three forms:
#   ./git_style.rb commit --message "fix bug"
#   ./git_style.rb commit --message="fix bug"
#   ./git_style.rb commit -m "fix bug"
#
#   # Combined short flags (like `git commit -am "msg"`):
#   ./git_style.rb commit -am "fix bug"
#
#   # Negated boolean (like `git commit --no-verify`):
#   ./git_style.rb commit -m "wip" --no-verify
#
#   # Global option before subcommand (like `git -C /tmp status`):
#   ./git_style.rb -C /tmp status
#
#   # Inexact long-option match (git-style abbreviation):
#   ./git_style.rb commit --mess "fix bug"     # matches --message
#   ./git_style.rb log --one                   # matches --oneline
#
#   # DidYouMean typo correction:
#   ./git_style.rb commit --mesage "oops"      # suggests --message
#
#   # `--` separator for filenames that start with a dash:
#   ./git_style.rb checkout -- --weird-file.txt
#
#   # Permitted values (enum):
#   ./git_style.rb log --format=oneline
#   ./git_style.rb log --format=bogus          # error, shows allowed values
#
#   # Nested subcommands:
#   ./git_style.rb remote add origin git@example.com:foo/bar.git
#   ./git_style.rb remote remove origin
#   ./git_style.rb remote list

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'optimist_xl'

SUB_COMMANDS = {
  'commit'   => 'Record changes to the repository',
  'log'      => 'Show commit logs',
  'status'   => 'Show the working tree status',
  'checkout' => 'Switch branches or restore files',
  'remote'   => 'Manage tracked repositories',
}

# ---- Top-level parser ------------------------------------------------------
#
# Global options (those that come BEFORE the subcommand name) go here.
# Each `subcmd` block declares a subcommand and its own options.

parser = OptimistXL::Parser.new do
  version "git-style-demo 0.1.0"
  usage   "[global options] <command> [command options] [args...]"
  synopsis "A tiny demonstration of git-style parsing with OptimistXL."

  # Global options — these must appear BEFORE the subcommand name.
  # `paginate` being a boolean with default false means users can also pass
  # `--no-paginate` to force-disable (auto-generated negation).
  opt :change_dir, "Run as if started in <path>", short: 'C', type: :string
  opt :verbose,    "Be more verbose",              short: 'v'
  opt :paginate,   "Pipe output through a pager",  short: 'p'

  # ---- Subcommand: commit ------------------------------------------------
  subcmd "commit", SUB_COMMANDS['commit'] do
    opt :message,  "Commit message", short: 'm', type: :string, alt: [:msg]
    opt :all,      "Stage all tracked, modified files", short: 'a'
    opt :amend,    "Amend the previous commit"
    opt :verify,   "Run pre-commit hooks", default: true  # --no-verify disables
    opt :author,   "Override author", type: :string
  end

  # ---- Subcommand: log ---------------------------------------------------
  subcmd "log", SUB_COMMANDS['log'] do
    opt :oneline,   "Compact one-line format"
    opt :max_count, "Limit number of commits", short: 'n', type: :integer, default: 25
    opt :format,    "Output format",
        type: :string,
        default: "medium",
        permitted: %w[oneline short medium full fuller raw]
    opt :author,    "Only commits by author", type: :string
    opt :since,     "Commits more recent than <date>", type: :string
  end

  # ---- Subcommand: status ------------------------------------------------
  subcmd "status", SUB_COMMANDS['status'] do
    opt :short, "Give output in short format", short: 's'
    opt :branch, "Show branch info", short: 'b'
  end

  # ---- Subcommand: checkout ----------------------------------------------
  subcmd "checkout", SUB_COMMANDS['checkout'] do
    opt :branch, "Create and check out a new branch", short: 'b', type: :string
    opt :force,  "Force checkout, throw away local changes", short: 'f'
  end

  # ---- Subcommand: remote ------------------------------------------------
  #
  # `remote` itself has nested subcommands (add, remove, list). OptimistXL's
  # `subcmd` is one level deep, so we use `stop_on_unknown` inside the `remote`
  # parser — it parses the remote-level options, then hands the remaining
  # tokens (the nested subcommand name + its args) back as leftovers. We
  # dispatch those to a second `Parser` below.
  subcmd "remote", SUB_COMMANDS['remote'] do
    opt :verbose, "Show URLs for each remote", short: 'v'
    stop_on %w[add remove list]  # stop parsing at these words
  end
end

# Parse global + first-level subcommand:
result = OptimistXL.with_standard_exception_handling(parser) { parser.parse(ARGV) }

# When no subcommands are registered, `parse` returns a plain Hash. When
# subcommands ARE registered, it returns a SubcommandResult. If the user gave
# only global options without a subcommand, raise so they see help.
unless result.is_a?(OptimistXL::SubcommandResult)
  OptimistXL.die "no command given (try --help)"
end

global = result.global_options
cmd    = result.subcommand
opts   = result.subcommand_options
rest   = result.leftovers

# ---- Nested subcommands: `remote add|remove|list` --------------------------
#
# At this point `rest` holds everything after the `remote` subcommand
# stopped. The first token is the nested subcommand name.
if cmd == "remote"
  nested = rest.shift
  case nested
  when "add"
    add_parser = OptimistXL::Parser.new do
      usage "remote add [-f] <name> <url>"
      opt :fetch, "Fetch the remote after adding", short: 'f'
    end
    add_opts = OptimistXL.with_standard_exception_handling(add_parser) { add_parser.parse(rest) }
    name, url, *extra = add_parser.leftovers
    OptimistXL.die "remote add: need <name> and <url>" unless name && url
    OptimistXL.die "remote add: unexpected extra args: #{extra.inspect}" unless extra.empty?
    puts "→ remote add name=#{name.inspect} url=#{url.inspect} fetch=#{add_opts[:fetch]}"

  when "remove", "rm"
    name = rest.shift
    OptimistXL.die "remote remove: need <name>" unless name
    puts "→ remote remove name=#{name.inspect}"

  when "list", nil
    puts "→ remote list (verbose=#{opts[:verbose]})"

  else
    OptimistXL.die "unknown `remote` subcommand: #{nested.inspect} (expected add|remove|list)"
  end

  # Show how the global options propagated
  puts "  global: change_dir=#{global[:change_dir].inspect} verbose=#{global[:verbose]}"
  exit 0
end

# ---- Everything else: just pretty-print what we parsed ---------------------
puts "command: #{cmd}"
puts "global:  #{global.reject { |k, _| k.to_s.end_with?('_given') }.inspect}"
puts "opts:    #{opts.reject   { |k, _| k.to_s.end_with?('_given') }.inspect}"
puts "rest:    #{rest.inspect}" unless rest.empty?
