#!/bin/env ruby
# encoding: utf-8
# Author: kimoto

filepath = ARGV.shift
if filepath.nil?
  STDERR.puts "please specify CentOS-base.repo"
  exit 1
end

results = []
File.readlines(filepath).each{ |line|
  if line =~ /priority/
    # already configured
    exit 0
  end

  line.chomp!
  if line =~ /gpgkey/
    puts line
    puts "priority=1"
  else
    puts line
  end
}
