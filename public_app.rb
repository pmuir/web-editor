require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'slim'
require 'sprockets'
require 'sinatra/sprockets-helpers'
require 'bundler'
require 'open3'

require_relative 'helpers/repository'

module AwestructWebEditor
  class PublicApp < Sinatra::Base
    register Sinatra::Sprockets::Helpers
    set :sprockets, Sprockets::Environment.new(root)
    set :assets_prefix, '/assets'
    set :public_folder, '/public'
    set :digest_assets, true

    configure do
      # Setup Sprockets
      sprockets.append_path File.join(root, 'assets', 'stylesheets')
      sprockets.append_path File.join(root, 'assets', 'javascripts')
      sprockets.append_path File.join(root, 'assets', 'images')
      sprockets.append_path File.join(root, 'assets', 'font')

      configure_sprockets_helpers
    end

    configure :development do
      require 'sinatra/reloader'
      register Sinatra::Reloader
      also_reload 'app.rb'
      also_reload 'models/**/*.rb'
      set :raise_errors, true
      enable :logging, :dump_errors, :raise_errors
    end

    # Views

    get '/' do
      slim :index
    end

    get '/assets/*' do
      sprockets
    end

    get '/partials/*.*' do |basename, ext|
      slim "partials/#{basename}".to_sym
    end

    # Application API

    # Repo APIs

    get '/repo' do
      repo_base = ENV['RACK_ENV'] =~ /test/ ? 'tmp/repos' : 'repos'
      return_structure = {}
      Dir[repo_base + '/*'].each do |f|
        if File.directory? f
          basename = File.basename f
          return_structure[basename] = { 'links' => [AwestructWebEditor::Link.new({ :url => url("/repo/#{basename}"),
                                                                                    :text => f,
                                                                                    :method => 'GET' })] }
        end
      end
      [200, JSON.dump(return_structure)]
    end

    # File related APIs

    get '/repo/:repo_name' do |repo_name|
      files = AwestructWebEditor::Repository.new({ 'name' => repo_name }).all_files
      return_links = {}
      files.each do |f|
        links = []

        unless f[:directory]
          links = links_for_file(f, repo_name)
        end

        if f[:path_to_root] =~ /\./
          return_links[f[:location]] = { :links => links, :directory => f[:directory], :children => {},
                                         :path => File.join(f[:path_to_root], f[:location]) }
        else
          directory_paths = f[:path_to_root].split(File::SEPARATOR)
          final_location = return_links[directory_paths[0]]
          directory_paths.delete(directory_paths[0])
          directory_paths.each { |path| final_location = final_location[:children][path] } unless directory_paths.nil?
          final_location[:children][f[:location]] = { :links => links, :directory => f[:directory], :children => {},
                                                      :path => File.join(f[:path_to_root], f[:location]) }
        end
      end
      [200, JSON.dump(return_links)]
    end

    get '/repo/:repo_name/*' do |repo_name, path|
      repo = AwestructWebEditor::Repository.new({ :name => repo_name })
      json_return = { :content => repo.file_content(path), :links => links_for_file(repo.file_info(path), repo_name) }
      [200, JSON.dump(json_return)]
    end

    post '/repo/:repo_name/*' do |repo_name, path|
      save_or_create(repo_name, path)
    end

    put '/repo/:repo_name/*' do |repo_name, path|
      save_or_create(repo_name, path)
    end

    delete '/repo/:repo_name/*' do |repo_name, path|
      repo = AwestructWebEditor::Repository.new({ :name => repo_name })
      result = repo.remove_file path
      result ? [200] : [500]
    end

    # Preview APIs

    get '/preview/:repo_name' do |repo_name|
      retrieve_rendered_file(repo_name, 'index', 'html')
    end

    get '/preview/:repo_name/*.*' do |repo_name, path, ext|
      retrieve_rendered_file(repo_name, path, ext)
    end

    # Git related APIs
    # TODO post '/repo/:repo_name/change_set' # should do a git fetch upstream && git checkout -b <name> upstream/master
    # TODO post '/repo/:repo_name/commit' # params[:message]
    # TODO post '/repo/:repo_name/push'

    helpers do
      Sinatra::JSON

      def links_for_file(f, repo_name)
        links = []
        links << AwestructWebEditor::Link.new({ :url => url("/repo/#{repo_name}/#{f[:path_to_root]}/#{f[:location]}"), :text => f[:location], :method => 'GET' })
        links << AwestructWebEditor::Link.new({ :url => url("/repo/#{repo_name}/#{f[:path_to_root]}/#{f[:location]}"), :text => f[:location], :method => 'PUT' })
        links << AwestructWebEditor::Link.new({ :url => url("/repo/#{repo_name}/#{f[:path_to_root]}/#{f[:location]}"), :text => f[:location], :method => 'POST' })
        links << AwestructWebEditor::Link.new({ :url => url("/repo/#{repo_name}/#{f[:path_to_root]}/#{f[:location]}"), :text => f[:location], :method => 'DELETE' })
        links << AwestructWebEditor::Link.new({ :url => url("/repo/#{repo_name}/#{f[:path_to_root]}/#{f[:location]}/preview"), :text => "Preview #{f[:location]}", :method => 'GET' })
      end

      def save_or_create(repo_name, path)
        repo = AwestructWebEditor::Repository.new({ :name => repo_name })
        request.body.rewind # in case someone already read it
        repo.save_file path, params[:content]

        retrieve_rendered_file(repo, path) unless ENV['RACK_ENV'] =~ /test/
      end

      def retrieve_rendered_file(repo, path)
        # TODO use bundler, do a clean system execute of exec_awestruct.rb, load the json to get the path, return the contents of the loaded the file
        Bundler.with_clean_env do
          Open3.popen3("ruby exec_awestruct.rb --repo #{repo.name} --url '#{request.scheme}://#{request.host}' --profile development") do |stdin, stdout, stderr, thr|
            mapping = JSON.load stdout
            File.open(File.join(repo.base_repository_path, '_site', mapping['/' + path]), 'r') { |f| f.readlines }
          end
        end
      end
    end
  end
end