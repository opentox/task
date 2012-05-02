require 'bundler'
require 'bundler/setup'
Bundler.require
Bundler.setup
require './application.rb'
run OpenTox::Application
