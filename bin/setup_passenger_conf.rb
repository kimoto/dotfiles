#!/bin/env ruby
# encoding: utf-8
# Author: kimoto

PASSENGER_TMPL="/usr/local/nginx/conf/passenger.conf.tmpl"
PASSENGER_CONF="/usr/local/nginx/conf/passenger.conf"

data = File.read(PASSENGER_TMPL)
data.gsub!(/\$RUBY_PATH/, `rbenv which ruby`.chomp)
data.gsub!(/\$PASSENGER_ROOT/, `passenger-config --root`.chomp)
puts data
puts "writing..."
File.write(PASSENGER_CONF, data)
puts "done"

