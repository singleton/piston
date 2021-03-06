require "yaml"

module Piston
  module Svn
    class WorkingCopy < Piston::WorkingCopy
      # Register ourselves as a handler for working copies
      Piston::WorkingCopy.add_handler self

      class << self
        def understands_dir?(dir)
          result = svn(:info, dir) rescue :failed
          result == :failed ? false : true
        end

        def client
          @@client ||= Piston::Svn::Client.instance
        end

        def svn(*args)
          client.svn(*args)
        end
      end

      def svn(*args)
        self.class.svn(*args)
      end

      def exist?
        result = svn(:info, path) rescue :failed
        logger.debug {"result: #{result.inspect}"}
        return false if result == :failed
        return false if result.nil? || result.chomp.strip.empty?
        return true if YAML.load(result).has_key?("Path")
      end

      def create
        svn(:mkdir, path)
      end

      def after_remember(path)
        begin
          info = svn(:info, path)
        rescue Piston::Svn::Client::CommandError
        ensure
          return unless info =~ /\(not a versioned resource\)/i || info =~ /\(is not under version control\)/i || info.blank?
          svn(:add, path)
        end
      end

      def finalize
        targets = []
        Dir[path + "*"].each do |item|
          svn(:add, item)
        end
      end

      # Returns all defined externals (recursively) of this WC.
      # Returns a Hash:
      #   {"vendor/rails" => {:revision => :head, :url => "http://dev.rubyonrails.org/svn/rails/trunk"},
      #    "vendor/plugins/will_paginate" => {:revision => 1234, :url => "http://will_paginate.org/svn/trunk"}}
      def externals
        externals = svn(:proplist, "--recursive", "--verbose")
        return Hash.new if externals.blank?
        returning(Hash.new) do |result|
          YAML.load(externals).each_pair do |dir, props|
            next if props["svn:externals"].blank?
            next unless dir =~ /Properties on '([^']+)'/
            basedir = self.path + $1
            exts = props["svn:externals"]
            exts.split("\n").each do |external|
              data = external.match(/^([^\s]+)\s+(?:(?:-r|--revision)\s*(\d+)\s+)?(.+)$/)
              case data.length
              when 4
                subdir, rev, url = data[1], data[2].nil? ? :head : data[2].to_i, data[3]
              else
                raise SyntaxError, "Could not parse svn:externals on #{basedir}: #{external}"
              end

              result[basedir + subdir] = {:revision => rev, :url => url}
            end
          end
        end
      end

      def merge_changes(to)
        data = svn(:info, yaml_path)
        info = YAML.load(data)
        initial_revision = info["Last Changed Rev"].to_i
        logger.debug {"Going to merge #{initial_revision} to #{to.revision}"}
        svn(:merge, "--revision", "#{initial_revision}:#{to.revision}", path, path)
        logger.debug {"after merge"}
      end

      def remove_external_references(*targets)
        svn(:propdel, "svn:externals", *targets)
      end
      
      protected
      def do_update(to, lock)
        logger.info "Copying new changes in place"
        copy_from(to)
        logger.info "Merging local changes into working copy"
        merge_changes(to)
        remember(recall.merge(:lock => lock), to.remember_values)
      end
    end
  end
end
