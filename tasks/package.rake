require 'octodown'
require 'fileutils'

module PackageHelpers
  def curl(file)
    system "curl -L -O --fail --silent #{file} > /dev/null"
  end

  def print_to_console(msg)
    puts "[#{arch}]:" + ' ' * (16 - arch.size) + '=>' + ' ' + msg
  end
end

class Package
  PACKAGE_NAME = 'octodown'
  VERSION = Octodown::VERSION
  RB_VERSION = '20141215-2.1.5'
  PACKAGING_DIR = "#{Octodown.root}/packaging"

  include ::PackageHelpers

  attr_reader :arch, :dir, :tar

  def initialize(arch)
    abort 'Ruby 2.1.x required' if RUBY_VERSION !~ /^2\.1\./

    @arch = arch
    @dir = "#{PACKAGE_NAME}-#{VERSION}-#{arch}"
    @tar = "v#{VERSION}.tar.gz"

    build
  end

  singleton_class.send :alias_method, :create, :new

  def build
    initialize_install_dir
    download_octodown
    bundle_install
    remove_unneccesary_files
    install_ruby
    create_executable
    post_cleanup

    create_tarball unless ENV['DIR_ONLY']
    upload_to_s3 unless ENV['DIR_ONLY']
  end

  private

  def post_cleanup
    print_to_console 'Cleaning up...'

    files = ["packaging/traveling-ruby-#{RB_VERSION}-#{arch}.tar.gz"]
    files.each do |file|
      FileUtils.rm file if File.exist? file
    end
  end

  def create_tarball
    print_to_console 'Creating tarball...'

    FileUtils.mkdir_p 'distro'
    system "tar -czf distro/#{dir}.tar.gz #{dir} > /dev/null"
    FileUtils.remove_dir "#{dir}", true
  end

  def create_executable
    print_to_console 'Creating exexutable...'

    FileUtils.cp 'packaging/wrapper.sh', "#{dir}/#{PACKAGE_NAME}"
  end

  def install_ruby
    print_to_console 'Installing Ruby...'

    download_runtime
    FileUtils.mkdir "#{dir}/lib/ruby"
    system(
      "tar -xzf packaging/traveling-ruby-#{RB_VERSION}-#{arch}.tar.gz " \
      "-C #{dir}/lib/ruby " \
      '&> /dev/null'
    )
  end

  def remove_unneccesary_files
    print_to_console 'Removing unneccesary files...'

    FileUtils.cd "#{dir}/lib/app" do
      FileUtils.remove_dir '.git', true
      FileUtils.remove_dir 'spec', true
    end
  end

  def initialize_install_dir
    print_to_console 'Initializing install directory...'

    FileUtils.cd Octodown.root do
      FileUtils.remove_dir(dir, true) if File.exist? dir
      FileUtils.mkdir_p "#{dir}/lib/app"
    end
  end

  def bundle_install
    print_to_console 'Running `bundle install`...'

    Bundler.with_clean_env do
      FileUtils.cd "#{dir}/lib/app" do
        system(
          'BUNDLE_IGNORE_CONFIG=1 bundle install ' \
          '--path vendor --without development --jobs 2 ' \
          '&> /dev/null'
        )
      end
    end
  end

  def download_octodown
    print_to_console 'Downloading octodown...'

    FileUtils.cd "#{dir}/lib/app" do
      curl "https://github.com/ianks/octodown/archive/#{tar}"
      system "tar --strip-components=1 -xzf #{tar} " \
        '&> /dev/null'
      FileUtils.rm tar if File.exist? tar
    end
  end

  def download_runtime
    print_to_console 'Downloading Travelling Ruby...'
    ruby = "traveling-ruby-#{RB_VERSION}-#{arch}.tar.gz"

    FileUtils.cd PACKAGING_DIR do
      unless File.exist? ruby
        curl "http://d6r77u77i8pq3.cloudfront.net/releases/#{ruby}"
      end
    end
  end
end

desc 'Package octodown into self-contained programs'
task :package do
  ['package:linux:x86', 'package:linux:x86_64', 'package:osx'].each do |task|
    fork do
      Rake::Task[task].invoke
      exit
    end
  end

  Process.waitall
end

namespace :package do
  namespace :linux do
    desc 'Package for Linux x86'
    task :x86 do
      Package.create 'linux-x86'
    end

    desc 'Package for Linux x86_64'
    task :x86_64 do
      Package.create 'linux-x86_64'
    end
  end

  desc 'Package for OS X'
  task :osx do
    Package.create 'osx'
  end
end
