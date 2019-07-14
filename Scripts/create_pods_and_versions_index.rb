#!/usr/bin/env ruby
# frozen_string_literal: true

require 'cocoapods'
require 'concurrent'
require 'open3'

source = Pod::Source.new('.')
pods = source.pods
sharding_pid = fork do
  shards = pods.each_with_object({}) do |pod, hash|
    shard = source.metadata.path_fragment(pod)[0...-1].join('_')
    versions = source.versions(pod).map(&:to_s).reverse
    hash[shard] ||= {}
    hash[shard][pod] = versions
  end

  # write all `all_pods_versions_2_2_2.txt` files that are structured like so:
  # DfPodTest/0.0.1/0.0.2
  shards.each do |shard, pods_versions|
    File.open("#{ARGV[0]}/all_pods_versions_#{shard}.txt", 'w') do |file|
      pods_versions.keys.sort.each do |pod|
        row = [pod] + pods_versions[pod].sort
        file.puts row.join('/')
      end
    end
  end
  STDERR.puts "Generated #{shards.count} shards"
  STDERR.puts "Total podspec count: #{shards.values.map(&:values).flatten.count}"
end

# write a list of all pods, separated by newline
File.open("#{ARGV[0]}/all_pods.txt", 'w') do |file|
  pods.each do |pod|
    file.puts pod
  end
end
STDERR.puts "Total pod count: #{pods.count}"

# get a list of all deprecated pods
executor = Concurrent::ThreadPoolExecutor.new(
  min_threads: Concurrent.processor_count,
  max_threads: Concurrent.processor_count,
  max_queue: 0 # unbounded work queue
)

# to split into groups
class Array
  def in_groups(num_groups)
    return [] if num_groups == 0

    slice_size = (size / Float(num_groups)).ceil
    each_slice(slice_size).to_a
  end
end

all_podspecs = Dir['Specs/**/*.podspec.json'].in_groups(Concurrent.processor_count)
STDERR.puts "Going to find all deprecated podspecs on #{Concurrent.processor_count} threads"
deprecated_podspecs_futures = all_podspecs.map do |podspecs|
  Concurrent::Promises.future_on(executor) do
    args = podspecs.compact.join("\n")
    out, = Open3.capture2('bundle exec Scripts/print_deprecated_podspecs.rb', stdin_data: args)
    deprecated = out.split("\n").map(&:chomp)
    deprecated
  end
end

deprecated_podspecs = Concurrent::Promises.zip(*deprecated_podspecs_futures).value!.flatten.sort

# write a list of all deprecated podspecs, separated by newline
File.open("#{ARGV[0]}/deprecated_podspecs.txt", 'w') do |file|
  deprecated_podspecs.each do |podspec_path|
    file.puts podspec_path
  end
end
STDERR.puts "Deprecated podspec count: #{deprecated_podspecs.count}"

Process.wait(sharding_pid)
