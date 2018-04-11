module Querly
  class ScriptEnumerator
    attr_reader :paths
    attr_reader :config

    def initialize(paths:, config:)
      @paths = paths
      @config = config
    end

    def each(&block)
      if block_given?
        paths.each do |path|
          if path.directory?
            enumerate_files_in_dir(path, &block)
          else
            load_script_from_path path, &block
          end
        end
      else
        self.enum_for :each
      end
    end

    @loaders = []

    def self.register_loader(pattern, loader)
      @loaders << [pattern, loader]
    end

    def self.find_loader(path)
      basename = path.basename.to_s
      @loaders.find {|pair| pair.first === basename }&.last
    end

    private

    def load_script_from_path(path, &block)
      preprocessor = preprocessors[path.extname]

      begin
        source = if preprocessor
                   preprocessor.run!(path)
                 else
                   path.read
                 end

        buffer = Parser::Source::Buffer.new(path.to_s, 1)
        buffer.source = source
        script = Script.new(path: path, node: parser.parse(buffer))
      rescue StandardError, LoadError, Preprocessor::Error => exn
        script = exn
      end

      yield(path, script)
    end

    def parser
      Parser::CurrentRuby.new(Builder.new).tap do |parser|
        parser.diagnostics.all_errors_are_fatal = true
        parser.diagnostics.ignore_warnings = true
      end
    end

    def preprocessors
      config&.preprocessors || {}
    end

    def enumerate_files_in_dir(path, &block)
      if path.basename.to_s =~ /\A\.[^\.]+/
        # skip hidden paths
        return
      end

      case
      when path.directory?
        path.children.each do |child|
          enumerate_files_in_dir child, &block
        end
      when path.file?

    
        extensions = %w[
          .rb .builder .fcgi .gemspec .god .jbuilder .jb .mspec .opal .pluginspec
          .podspec .rabl .rake .rbuild .rbw .rbx .ru .ruby .spec .thor .watchr
        ]
        basenames = %w[
          .irbrc .pryrc buildfile Appraisals Berksfile Brewfile Buildfile Capfile
          Cheffile Dangerfile Deliverfile Fastfile Gemfile Guardfile Jarfile Mavenfile
          Podfile Puppetfile Rakefile Snapfile Thorfile Vagabondfile Vagrantfile
        ]
        should_load_file = case
                           when extensions.include?(path.extname)
                             true
                           when basenames.include?(path.basename.to_s)
                             true
                           else
                             preprocessors.key?(path.extname)
                           end

        load_script_from_path(path, &block) if should_load_file
      end
    end

    class Builder < Parser::Builders::Default
      def string_value(token)
        value(token)
      end
      
      def emit_lambda
        true
      end
    end
  end
end
