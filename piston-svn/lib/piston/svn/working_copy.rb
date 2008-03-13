require "piston/working_copy"
require "piston/svn"
require "piston/svn/client"
require "yaml"

module Piston
  module Svn
    class WorkingCopy < Piston::WorkingCopy
      extend Piston::Svn::Client

      class << self
        def understands_dir?(dir)
          result = svn(:info, dir) rescue :failed
          result == :failed ? false : true
        end
      end

      def svn(*args)
        self.class.svn(*args)
      end

      def svnadmin(*args)
        self.class.svnadmin(*args)
      end

      def exist?
        logger.debug {"svn info on #{path}"}
        result = svn(:info, path) rescue :failed
        logger.debug {"result: #{result.inspect}"}
        result == :failed ? false : true
      end

      def create
        info = YAML.load(svn(:info, path.parent))
        local_rev = info["Last Changed Rev"]
        svn(:mkdir, path)
        svn(:propset, Piston::Svn::LOCAL_REV, local_rev, path)
      end

      def copy_from(revision)
        revision.each do |relpath|
          target = path + relpath
          target.dirname.mkdir rescue nil
          revision.copy_to(target)
        end
      end

      def remember(values)
        values.each_pair do |k, v|
          svn(:propset, k, v, path)
        end
      end

      def finalize
      end
    end
  end
end