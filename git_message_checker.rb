#!/usr/bin/env ruby

require 'json'
require 'tmpdir'

MODEL='gemini-2.5-flash'

REVIEW_PROMPT = %q(
You are a member of the Git community, and you know the commit message guidelines
used by the Git source code. Rewrite the message following those guidelines.
Return only the message without any extra word.
)

def get_commit_list from, to
  `git rev-list #{from}..#{to}`
    .lines
    .map {|x| x.strip}
    .filter {|x| !x.empty?}
end

def get_commit_msg commit
  `git cat-file -p #{commit}`
    .lines
    .map {|x| x.strip}
    .drop_while {|x| !x.empty?}
    .drop(1)
    .join("\n")
end

def review_message msg
  prompt = REVIEW_PROMPT.gsub("\n", " ")
  cmd = "gemini -p '#{prompt}' -m '#{MODEL}' --output-format=json"

  response = IO.popen(cmd, 'w+') do |gemini|
    gemini.puts(msg)
    gemini.close_write
    gemini.read
  end

  if $? != 0
    exit(1)
  end

  JSON.parse(response)['response']
end

def diff_msg commit, original, suggestion
  commit = commit[0..7]

  original_file = "#{commit}_original"
  suggestion_file = "#{commit}_suggestion"

  Dir.mktmpdir do |dir|
    Dir.chdir(dir) do
      File.write original_file, original + "\n"
      File.write suggestion_file, suggestion + "\n"
      `git --no-pager diff '#{original_file}' '#{suggestion_file}'`
    end
  end
end

def suggest_diff commit
  original = get_commit_msg(commit)
  suggested = review_message(original)
  diff = diff_msg(commit, original, suggested)
  diff
end

if ARGV.length < 1
  exit 1
end

from = ARGV[0]
to = ARGV[1] or 'HEAD'

commits = get_commit_list(from, to)
diffs = commits
          .map {|commit| suggest_diff(commit)}
          .join("\n")

IO.popen('delta', 'w') do |delta|
  delta.print(diffs)
  delta.close_write
end
