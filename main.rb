require 'rubygems'
require 'bundler/setup'

require 'netrc'
require 'octokit'
require 'pry'
require 'time_difference'

HEADER = { Accept: 'application/vnd.github.inertia-preview+json' }

Octokit.auto_paginate = true

client = Octokit::Client.new(netrc: true)


=begin
projects = client.org_projects('sumoners', headers: HEADER)

projects.each do |project|
  puts "Project: #{project.name}"

  columns = project.rels[:columns].get(headers: HEADER).data
  columns.each do |column|
    puts " - #{column.name}"

    items = column.rels[:cards].get(headers: HEADER).data
    items.each do |item|
      item = item.rels[:content].get.data
      repo = item.rels[:repository].get.data
      puts "   ##{item.number} - #{item.title} (#{repo.name})"
    end
  end
end
=end

REPO_LIST = ['bonuz-api', 'companion-backend', 'companion-desktop', 'companion-pdv']

REPO_LIST.each do |repository_name|
  open_pulls = client.pull_requests("sumoners/#{repository_name}", state: :open)

  puts "@#{repository_name}"

  if open_pulls.length > 0
    puts ' --- OPEN --- '

    open_pulls.each do |pull|
      days = (Time.now - pull.created_at) / 86_000
      printf("   (%s) %.2f days - %s\n", pull.user.login, days, pull.title)
    end
  end

  puts ' --- LAST ACTIVITY --- '

  closed_pulls = client.pull_requests("sumoners/#{repository_name}", state: :closed)
  closed_pulls.each do |pull|
    break if pull.closed_at < Time.now - 30 * 86_000

    days = (pull.closed_at - pull.created_at) / 86_000
    printf("   (%s) %.2f days - %s\n", pull.user.login, days, pull.title)
  end
end

