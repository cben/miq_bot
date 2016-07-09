class PullRequestMonitor
  class PrBranchRecord
    def self.create(repo, pr, branch_name)
      repo.git_fetch
      html_url   = pr.head.repo.try(:html_url) || pr.base.repo.html_url
      commit_uri = File.join(html_url, "commit", "$commit")
      branch     = repo.branches.build(
        :name         => branch_name,
        :commits_list => [],
        :commit_uri   => commit_uri,
        :pull_request => true,
        :merge_target => pr.base.ref
      )
      branch.last_commit = branch.git_service.merge_base
      branch.save!
    end

    def self.delete(repo, *branch_names)
      return if branch_names.empty?

      repo.branches.where(:name => branch_names).destroy_all
    end

    def self.prune(repo)
      delete(repo, *repo.stale_pr_branches)
    end
  end
end
