
require_relative 'branch_names'

module Git

    BASE_LOOKBACK_LIMIT = 100 # commits
    CUSTOM_BACKUP_BRANCH_PATTERN = /\A#{CUSTOM_BACKUP_BRANCH_NAME}(\d*)\Z/
    LIGHT_BACKUP_BRANCH_PATTERN = /\A#{LIGHT_BACKUP_BRANCH_NAME}(\d*)\Z/
    BRANCH_PATTERN = /(?:tag:\s)?[\w-]+(?:\/[\w-]+)*/
    BRANCHES_PATTERN = /#{BRANCH_PATTERN}(?:,\s#{BRANCH_PATTERN})*/

    class LightCustomBaseNotFound < StandardError; end
    class NoBackupBranchFound < StandardError; end
    class FailedToCommit < StandardError; end

    def self.has_uncommited_changes?
        not system 'git diff --name-only --diff-filter=M --exit-code > /dev/null'
    end

    def self.branch_name
        `git rev-parse --abbrev-ref HEAD`.chomp
    end

    def self.light_custom_base
        IO.popen('git log --decorate --oneline') do |gitio|
            lines = 0
            loop do
                log_line = gitio.readline.chomp
                lines += 1
                log_match = log_line.match /\A(?<commit>\w+)\s(?:\((?<branches>#{BRANCHES_PATTERN})?\)\s)?/
                commit = log_match['commit']
                branches = log_match['branches'] ? log_match['branches'].split(', ') : []
                break [ commit, CUSTOM_BRANCH_NAME ] if branches.include? CUSTOM_BRANCH_NAME
                base_name = branches.find { |bn| bn.match(CUSTOM_BACKUP_BRANCH_PATTERN) or bn.match(/\Atag:\s#{CUSTOM_TAG_PATTERN}\Z/) }
                break [ commit, base_name ] unless base_name.nil?
                raise LightCustomBaseNotFound, 'light custom base not found' if lines > BASE_LOOKBACK_LIMIT
            end
        end
    end

    def self.base_is_custom_branch?
        light_custom_base[1] == CUSTOM_BRANCH_NAME
    end

    def self.rev_list rev_range
        `git rev-list #{rev_range}`.split("\n").reverse
    end

    def self.light_rev_list
        rev_list light_custom_base[0]..'HEAD'
    end

    def self.branches
        `git branch`.split("\n").map { |bn| bn[2..-1] }
    end

    def self.backup_branches
        branches.find_all { |bn| bn =~ LIGHT_BACKUP_BRANCH_PATTERN }
    end

    def self.last_backup_branch_number
        numbers = backup_branches.map { |bn| bn.match(LIGHT_BACKUP_BRANCH_PATTERN)[1].to_i }
        raise NoBackupBranchFound, 'no backup branch found' if numbers.empty?
        numbers.max
    end

    def self.last_backup_branch_name
        "#{LIGHT_BACKUP_BRANCH_NAME}#{last_backup_branch_number}"
    end

    def self.next_backup_branch_number
        last_backup_branch_number + 1
    rescue NoBackupBranchFound
        1
    end

    def self.next_backup_branch_name
        "#{LIGHT_BACKUP_BRANCH_NAME}#{next_backup_branch_number}"
    end

    def self.head_branches
        branches = `git log --decorate --oneline -1`.chomp.match(/\A\w+\s\(HEAD(?:\s->\s(#{BRANCHES_PATTERN}))?\)/)[1]
        branches.nil? ? [] : branches.split(', ')
    end

    def self.head_backup_branch_name
        head_branches.find { |bn| bn =~ LIGHT_BACKUP_BRANCH_PATTERN }
    end

    def self.backup_branch
        head_backup_branch_name || next_backup_branch_name.tap do |branch_name|
            result = system "git branch \"#{branch_name}\" > /dev/null"
            raise 'failed to backup branch' unless result
        end
    end

    def self.hard_reset_to rev
        result = system "git reset --hard \"#{rev}\" > /dev/null 2>&1"
        raise "failed to hard reset to #{rev}" unless result
    end

    def self.cherry_pick rev
        result = system "git cherry-pick \"#{rev}\" > /dev/null 2>&1"
        raise "failed to cherry-pick rev #{rev}" unless result
    end

    def self.display_one_line_log revs
        if revs.is_a? Range
            result = system "git log --oneline --no-decorate #{revs}"
            raise "failed to display log for rev range #{rev_range}" unless result
        else
            revs = [*revs]
            revs.each do |rev|
                result = system "git log --oneline --no-decorate #{rev}^..#{rev}"
                raise "failed to display log for rev #{rev}" unless result
            end
        end
    end

    def self.rev_one_line_log rev, color: true
        `git log --oneline --no-decorate #{'--color ' if color}#{rev}^..#{rev}`.chomp
    end

    def self.commit_no_edit
        result = system "git commit --no-edit > /dev/null 2>&1"
        raise FailedToCommit, "failed to commit" unless result
    end

    def self.index_empty?
        system "git diff --cached --exit-code > /dev/null"
    end

end
