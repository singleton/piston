require "piston/working_copy"
require "piston/git/client"

module Piston
  module Git
    class WorkingCopy < Piston::WorkingCopy
      # Register ourselves as a handler for working copies
      Piston::WorkingCopy.add_handler self

      class << self
        def understands_dir?(dir)
          path = dir
          begin
            begin
              logger.debug {"git status on #{path}"}
              Dir.chdir(path) do
                response = git(:status)
                return true if response =~ /# On branch /
              end
            rescue Errno::ENOENT
              # NOP, we assume this is simply because the folder hasn't been created yet
              path = path.parent
              retry unless path.to_s == "/"
              return false
            end
          rescue Piston::Git::Client::BadCommand
            # NOP, as we return false below
          rescue Piston::Git::Client::CommandError
            # This is certainly not a Git repository
            false
          end

          false
        end

        def client
          @@client ||= Piston::Git::Client.instance
        end

        def git(*args)
          client.git(*args)
        end
      end

      def git(*args)
        self.class.git(*args)
      end

      def create
        path.mkpath rescue nil
      end

      def exist?
        path.directory?
      end

      def finalize
        Dir.chdir(path) { git(:add, ".") }
      end

      protected
      def do_update(to, lock)
        puts "tmpdir: #{to.dir}"
        puts "exist? #{to.dir.exist?}"
        puts "file? #{to.dir.file?}"
        puts "directory? #{to.dir.directory?}"
        path.children.reject {|item| ['.git', '.piston.yml'].include?(item.basename.to_s)}.each do |item|
          puts "rm -rf #{item}"
          FileUtils.rm_rf(item)
        end
        to.dir.children.reject {|item| item.basename.to_s == '.git'}.each do |item|
          puts "cp -r #{item} #{path}"
          FileUtils.cp_r(item, path)
        end
        Dir.chdir(path) do
          repository = to.repository
          remember(
            {:repository_url => repository.url, :lock => lock, :repository_class => repository.class.name},
            to.remember_values
          )
          git(:add, ".")
        end
      end
    end
  end
end
