#!/usr/bin/env ruby
# frozen_string_literal: true

require 'cocoapods'

args = $stdin.read.split("\n").map(&:chomp)
STDERR.puts "Received #{args.count} specs"
args.each do |podspec|
  puts podspec if Pod::Specification.from_file(podspec).deprecated?
end
