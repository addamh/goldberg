require "ostruct"
require 'fileutils'

class Build < ActiveRecord::Base
  include Comparable

  attr_accessor :previous_build_revision
  after_create :create_dir
  before_create :update_revision

  belongs_to :project

  default_scope order('number DESC')

  def self.nil
    OpenStruct.new(:number => 0, :status => 'not available', :revision => '', :nil_build? => true, :timestamp => nil, :build_log => '')
  end

  def timestamp
    self.created_at
  end

  def path
    File.join(project.path, "builds", number.to_s)
  end

  %w(change_list build_log).each do |file_name|
    define_method "#{file_name}_path".to_sym do
      File.join(path, file_name)
    end

    define_method "#{file_name}" do
      file_path = send("#{file_name}_path")
      Environment.file_exist?(file_path) ? Environment.read_file(file_path) : ''
    end
  end

  def artefacts_path
    File.join(path, "artefacts")
  end

  def <=>(other)
    number.to_i <=> other.number.to_i
  end

  def run
    before_build
    Bundler.with_clean_env do
      Env['BUNDLE_GEMFILE'] = nil
      Env["RUBYOPT"] = nil # having RUBYOPT was causing problems while doing bundle install resulting in gems not being installed - aakash
      Env['BUILD_ARTIFACTS'] = Env['BUILD_ARTEFACTS'] = artefacts_path
      RVM.prepare_ruby(ruby)
      go_to_project_path = "cd #{project.code_path}"
      build_command = "#{environment_string} #{project.build_command}"
      output_redirects = "1>>#{build_log_path} 2>>#{build_log_path}"
      Environment.system("(#{RVM.use_script(ruby, project.name)} ; #{go_to_project_path}; #{build_command}) #{output_redirects}").tap do |success|
        self.status = success ? 'passed' : 'failed'
        save
      end
    end
  end

  def before_build
    self.status = "building"
    save
    persist_change_list
    FileUtils.mkdir_p(artefacts_path)
  end

  def persist_change_list
    change_list = project.repository.change_list(previous_build_revision, revision)
    File.open(change_list_path, "w+") do |file|
      file.write(change_list)
    end
  end

  def create_dir
    FileUtils.mkdir_p(path)
  end

  def update_revision
    self.revision = project.repository.revision if self.revision.blank?
  end

  def nil_build?
    false
  end

  def artefacts
    if Environment.exist?(artefacts_path)
      Dir.entries(artefacts_path) - ['.', '..']
    else
      []
    end
  end
end
