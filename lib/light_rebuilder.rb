
require_relative 'libutil/lib/term_color'
require_relative 'branch_names'
require_relative 'git'

class LightRebuilder

    STATUS_FILE_NAME = 'light_rebuild.status'

    class NotOnTheRightBranch < StandardError; end
    class NothingToDo < StandardError; end
    class UncommitedChanges < StandardError; end
    class NotInReposRoot < StandardError; end

    def run base_rev = nil, dry: false
        raise NotOnTheRightBranch, "not on the #{LIGHT_BRANCH_NAME} branch" unless Git.branch_name == LIGHT_BRANCH_NAME
        resuming = load_status_file
        raise ArgumentError, 'rebuild in progress, no base_rev argument expected' if resuming and not base_rev.nil?
        raise ArgumentError, 'cannot dry run resume operation' if resuming and dry

        if revs_to_go.nil?
            start base_rev, dry: dry
            return if dry
        else
            resume
        end

        cherry_pick
        delete_status_file
        puts TermColor.bold_green("\nRebuild success")
    end

    def abort
        raise NothingToDo, 'nothing to abort' unless load_status_file
        Git.hard_reset_to backup_branch_name
        delete_status_file
    end

    private

    def start base_rev = nil, dry:
        raise NotInReposRoot, 'not in repos root' unless File.exist? '.git'
        raise UncommitedChanges, 'repos contains uncommited changes' if Git.has_uncommited_changes? or not Git.index_empty?
        raise NothingToDo, "nothing to do, base is already #{CUSTOM_BRANCH_NAME}" if Git.base_is_custom_branch?
        self.revs_to_go = base_rev.nil? ? Git.light_rev_list : Git.rev_list(base_rev..'HEAD')
        raise 'no commit to pick' if revs_to_go.empty?
        display_revs_to_go "# #{dry ? "Would rebuild" : "Starting rebuilding"} using light commits:"
        return if dry
        backup_branch
        Git.hard_reset_to CUSTOM_BRANCH_NAME
    rescue Git::LightCustomBaseNotFound
        raise ArgumentError, "the #{CUSTOM_BRANCH_NAME} base hasn't been found, you need to specify the base revision"
    end

    def resume
        if revs_to_go.empty?
            puts TermColor.bold('# Resuming rebuilding')
        else
            display_revs_to_go '# Resuming rebuilding, commits left to pick:'
        end

        unless Git.index_empty?
            puts TermColor.bold('# Committing changes')
            Git.commit_no_edit
        end

    rescue Git::FailedToCommit
        raise "failed to commit, conflicts are probably left"
    end

    def backup_branch
        self.backup_branch_name = Git.head_backup_branch_name
        if backup_branch_name.nil?
            self.backup_branch_name = Git.backup_branch
            puts TermColor.bold("# Branch backed up with name ") + TermColor.yellow(backup_branch_name)
        end
    end

    def display_revs_to_go header
        puts
        puts TermColor.bold(header)
        Git.display_one_line_log revs_to_go
        puts
    end

    def cherry_pick
        while not revs_to_go.empty? do
            rev = revs_to_go.shift
            puts TermColor.bold("# Cherry picking rev ") + Git.rev_one_line_log(rev)
            Git.cherry_pick rev
        end
    rescue Interrupt
        raise
    rescue Git::CherryPickingFailed
        STDERR.puts TermColor.bold_yellow("\nCherry-picking failed, please fix the conflict(s) and run again")
        exit 4
    ensure
        write_status_file
    end

    def load_status_file
        status = YAML.load_file STATUS_FILE_NAME
        raise 'status file error' unless status[:revs_to_go].is_a? Array and status[:backup_branch_name].is_a? String
        @revs_to_go = status[:revs_to_go]
        @backup_branch_name = status[:backup_branch_name]
        true
    rescue Errno::ENOENT
        false
    end

    def write_status_file
        status = { revs_to_go: revs_to_go, backup_branch_name: backup_branch_name }
        File.open(STATUS_FILE_NAME, 'w') { |f| YAML.dump status, f }
        nil
    end

    def delete_status_file
        File.delete STATUS_FILE_NAME
        nil
    rescue Errno::ENOENT
    end

    attr_accessor :revs_to_go, :backup_branch_name

end
