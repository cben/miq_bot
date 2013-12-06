#!/usr/bin/env ruby

require_relative 'logging'
require 'yaml'
require 'minigit'
require 'ruby_bugzilla'

# Watches git branches for new commits, and on each new commit, triggers a callback.
class CommitMonitor
  include Logging

  BZ_CREDS_YAML             = File.join(File.dirname(__FILE__), 'config/bugzilla_credentials.yml')
  COMMIT_MONITOR_REPOS_YAML = File.join(File.dirname(__FILE__), 'config/commit_monitor_repos.yml')
  COMMIT_MONITOR_YAML       = File.join(File.dirname(__FILE__), 'config/commit_monitor.yml')
  COMMIT_MONITOR_LOG        = File.join(File.dirname(__FILE__), 'log/commit_monitor.log')

  def initialize
    load_yaml_files
    @repo_base = File.expand_path(@options["repository_base"])
  end

  def process_new_commits
    @repos.each do |repo_name, branches|
      git = MiniGit::Capturing.new(File.join(@repo_base, repo_name))

      branches.each do |branch, options|
        last_commit, commit_uri = options.values_at("last_commit", "commit_uri")

        git.checkout branch
        git.pull

        commits = find_new_commits(git, last_commit)
        commits.each do |commit|
          message_prefix = "New commit detected on #{repo_name}/#{branch}:"
          process_commit(git, commit, message_prefix, commit_uri)
        end

        @repos[repo_name][branch]["last_commit"] = commits.last || last_commit
        dump_repos_file
      end
    end
  end

  private

  def find_new_commits(git, last_commit)
    git.rev_list({:reverse => true}, "#{last_commit}..HEAD").chomp.split("\n")
  end

  def process_commit(git, commit, message_prefix, commit_uri)
    message = git.log({:pretty => "fuller"}, "--stat", "-1", commit)

    message.each_line do |line|
      match = %r{^\s*https://bugzilla\.redhat\.com/show_bug\.cgi\?id=(?<bug_id>\d+)$}.match(line)

      if match
        comment = "#{message_prefix}\n#{commit_uri}#{commit}\n\n#{message}"
        write_to_bugzilla(match[:bug_id], comment)
      end
    end
  end

  def write_to_bugzilla(bug_id, comment)
    logger.info("Updating bug id #{bug_id} in Bugzilla.")
    bz = RubyBugzilla.new(*@bz_creds.values_at("bugzilla_uri", "username", "password"))
    bz.login
    output = bz.query(:product => @options["product"], :bug_id => bug_id).chomp
    if output.length == 0
      logger.error "Unable to write for bug id #{bug_id}: Not a '#{@options["product"]}' bug."
    else
      logger.info "Writing to bugzilla"
      bz.modify(bug_id, :comment => comment)
    end
  rescue => err
    logger.error "Unable to write for bug id #{bug_id}: #{err}"
  end

  def load_yaml_files
    @repos    = YAML.load_file(COMMIT_MONITOR_REPOS_YAML)
    @options  = YAML.load_file(COMMIT_MONITOR_YAML)
    @bz_creds = YAML.load_file(BZ_CREDS_YAML)
  end

  def dump_repos_file
    File.open(COMMIT_MONITOR_REPOS_YAML, 'w+') do |f|
      f.write(YAML.dump(@repos))
    end
  end
end

if $0 == __FILE__
  MiniGit.debug = true
  Logging.logger = Logger.new(STDOUT)

  bot = CommitMonitor.new
  loop do
    bot.process_new_commits
    sleep(60)
  end
end
