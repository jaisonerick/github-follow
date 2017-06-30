require 'rubygems'
require 'bundler/setup'

require 'netrc'
require 'octokit'
require 'pry'
require 'time_difference'
require 'circleci'

HEADER = { Accept: 'application/vnd.github.inertia-preview+json' }

CircleCi.configure do |config|
  config.token = ENV['CIRCLECI_TOKEN']
end

class CircleCiInfo
  def coverage_info(build)
    build = CircleCi::Build.new build['username'], build['reponame'], nil, build['build_num']
    res = build.get.body

    spec = res["steps"].detect { |step| step["name"] == "bin/rake spec" }
    spec = res["steps"].detect { |step| step["name"] == "bin/rake" } unless spec
    binding.pry unless spec
    output_url = spec["actions"].first["output_url"]

    content = JSON.parse(Net::HTTP.get(URI.parse(output_url)))
    matches = content.first["message"].match(/(\d+) \/ (\d+) LOC/)

    { covered: matches[1].to_i, total: matches[2].to_i }
  end
  
  def last_build_for_repo(repo_full_name, branch: nil)
    username, reponame = repo_full_name.split('/')

    project = CircleCi::Project.new username, reponame
    if branch
      res = project.recent_builds_branch(branch).body.first
    else
      res = project.recent_builds(limit: 1).body.first
    end
  end
end

class GithubInfo
  attr_reader :client

  def initialize
    @client = Octokit::Client.new(netrc: true)
  end

  def closed_prs(repository)
    Enumerator.new do |y|
      closed_pulls = client.pull_requests(repository, state: :closed)

      loop do
        break if closed_pulls.count.zero?

        closed_pulls.each do |pull|
          y << pull
        end

        closed_pulls = client.last_response.rels[:next].get.data
      end
    end
  end

  def pr_reviews(repository, pr_number)
    Enumerator.new do |y|
      reviews = client.pull_request_reviews(repository, pr_number, headers: HEADER)

      loop do
        break if reviews.count.zero?

        reviews.each do |review|
          y << review
        end

        reviews = client.last_response.rels[:next].get.data
      end
    end
  end

  def last_week_prs(repository)
    prs = client.pull_requests(repository, state: :open)
    closed_prs(repository).each do |pull|
      break if pull.closed_at < Time.now - 7 * 86_000

      prs << pull
    end

    prs
  end

  def last_week_opened_prs(repository)
    prs = client.pull_requests(repository, state: :open).select { |pr| pr.created_at >= Time.now - 7 * 86_000 }
    closed_prs(repository).each do |pull|
      break if pull.created_at < Time.now - 7 * 86_000

      prs << pull
    end

    prs
  end

  def last_week_closed_prs(repository)
    prs = []

    closed_prs(repository).each do |pull|
      break if pull.closed_at < Time.now - 7 * 86_000

      prs << pull
    end

    prs
  end

  def avg_closing_time(repository)
    days = last_week_closed_prs(repository).map { |pr| days = (pr.closed_at - pr.created_at) / 86_000 }
    days.inject(&:+).to_f / days.count
  end

  def first_reviews(repository)
    last_week_prs(repository).map do |pr|
      first_approved = nil
      first_rejected = nil

      client.pull_request_reviews(repository, pr.number).each do |review|
        if review.state === 'APPROVED' && first_approved == nil
          first_approved = review
        end

        if review.state === 'REQUEST_CHANGES'
          first_rejected = review
          break
        end
      end

      { pr: pr, review: first_rejected ? first_rejected : first_approved }
    end
  end
end

=begin

Ultimos 7  dias:

- Quantos PR abertos
- Quantos fechados
- Tempo médio de fechamento
- PR por tag
- Tempo médio para o primeiro review (primeiro review negativo, se não existir, primeiro positivo)
- Merge de PR sem review
- Reviews por pessoa

=end

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



REPO_LIST = ['bonuz-api', 'companion-backend', 'companion-pdv']

circle = CircleCiInfo.new

coverage = REPO_LIST.inject({ covered: 0, total: 0 }) do |sum, repo|
  last_build = circle.last_build_for_repo("sumoners/#{repo}", branch: 'master')
  unless last_build
    puts "Repo didn't build: #{repo}"
    next sum
  end
  coverage = circle.coverage_info(last_build)
  sum[:covered] += coverage[:covered]
  sum[:total] += coverage[:total]
  sum
end

printf("Total coverage: %.2f%%\n", coverage[:covered].to_f / coverage[:total] * 100)
exit

client = GithubInfo.new

=begin
REPO_LIST.each do |repository_name|
  puts "@#{repository_name}"

  prs = client.last_week_prs("sumoners/#{repository_name}")
  prs.group_by(&:state).each do |(state, list)|
    if state == 'open'
      puts ' --- OPEN --- '

      list.each do |pr|
        days = (Time.now - pr.created_at) / 86_000
        printf("   (%s) %.2f days - %s\n", pr.user.login, days, pr.title)
      end
    end
  end
end
=end

times = REPO_LIST.map { |repo| client.first_reviews("sumoners/#{repo}") }
                 .flatten
                 .reject { |item| item[:review].nil? }
                 .map { |item| (item[:review].submitted_at - item[:pr].created_at) / 3_600 }

printf("AVG FIRST REVIEW TIME: %.4f\n", times.inject(&:+) / times.count)

